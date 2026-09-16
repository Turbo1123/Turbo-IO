"""Pure bootstrap tests: never import or start the owner's Hermes runtime."""
import ast
import importlib.util
import json
import os
from pathlib import Path
import threading
import time
import types
import unittest
from unittest.mock import patch

path = Path(__file__).with_name('hermes_gateway.py')
bootstrap = None
if path.exists():
    spec = importlib.util.spec_from_file_location('io_gateway_test', path)
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(bootstrap, 'Hermes bootstrap exists')

    def test_effective_whatsapp_tools_are_pinned_in_process(self):
        cfg = {'platform_toolsets': {'whatsapp': ['terminal', 'skills']}}
        calls = []
        def resolve(config, platform, *, include_default_mcp_servers):
            calls.append((config, platform, include_default_mcp_servers))
            return {'terminal', 'skills', 'enabled-mcp'}
        with patch.dict(os.environ, {}, clear=True):
            chosen = bootstrap.pin_toolsets(cfg, resolve)
            self.assertEqual(chosen, ['enabled-mcp', 'skills', 'terminal'])
            self.assertEqual(os.environ['HERMES_TUI_TOOLSETS'], 'enabled-mcp,skills,terminal')
            self.assertNotIn('HERMES_YOLO_MODE', os.environ)
        self.assertEqual(calls, [(cfg, 'whatsapp', True)])

    def test_empty_all_or_invalid_toolsets_cannot_fall_back_to_all(self):
        for selection in [set(), {'all'}, {'*'}, {'bad,name'}, {''}, None]:
            with self.subTest(selection=selection):
                with self.assertRaisesRegex(RuntimeError, 'hermes_toolsets_invalid'):
                    bootstrap.pin_toolsets({}, lambda *a, **kw: selection)

    def test_configured_mcp_names_with_spaces_are_preserved(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(bootstrap.pin_toolsets({}, lambda *a, **kw: {'paper research', 'skills'}), ['paper research', 'skills'])

    def test_real_pinned_upstream_approval_waiter_resolves_exact_correlated_entry(self):
        # Compile only the public approval data structure and wait/resolve
        # functions. Module imports/config/auth paths are never executed.
        source = Path(__file__).with_name('fixtures') / 'approval-upstream-7b5ba205.py.txt'
        parsed = ast.parse(source.read_text())
        names = {'_ApprovalEntry', '_await_gateway_decision', 'resolve_gateway_approval'}
        nodes = [node for node in parsed.body if isinstance(node, (ast.ClassDef, ast.FunctionDef)) and node.name in names]
        namespace = {'threading': threading, 'time': time, 'Optional': __import__('typing').Optional,
                     '_lock': threading.Lock(), '_gateway_queues': {},
                     '_fire_approval_hook': lambda *a, **kw: None,
                     '_get_approval_config': lambda: {'gateway_timeout': 1},
                     'is_interrupted': lambda: False,
                     'logger': types.SimpleNamespace(warning=lambda *a, **kw: None)}
        exec(compile(ast.Module(body=nodes, type_ignores=[]), str(source), 'exec'), namespace)
        self.assertEqual(len(nodes), 3)
        server, _, events = self.server()
        approval = types.SimpleNamespace(**namespace)
        bootstrap.install_guards(server, approval)
        notified = threading.Event()
        result = []
        def notify(data):
            server._emit_approval_request('owned', data)
            notified.set()
        worker = threading.Thread(target=lambda: result.append(namespace['_await_gateway_decision']('stored-owned', notify, {'command': 'echo fixture'})))
        worker.start()
        self.assertTrue(notified.wait(.5))
        request_id = events[0][2]['request_id']
        response = server._methods['approval.respond'](1, {'session_id': 'owned', 'request_id': request_id, 'choice': 'once'})
        self.assertEqual(response['result'], {'resolved': 1})
        worker.join(1)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result, [{'resolved': True, 'choice': 'once', 'reason': None}])

    def server(self):
        emit_log = []
        session = {'session_key': 'stored-owned', 'source': 'norman-io', 'agent': object(), 'agent_ready': threading.Event(), 'running': False}
        session['agent_ready'].set()
        server = types.SimpleNamespace(_sessions={'owned': session}, _pending={}, _pending_prompt_payloads={}, _prompt_lock=threading.Lock(), _answers={}, _methods={}, _emit=lambda kind, sid, payload=None: emit_log.append((kind, sid, payload)))
        server._ok = lambda rid, result: {'id': rid, 'result': result}
        server._err = lambda rid, code, message: {'id': rid, 'error': {'code': code, 'message': message}}
        server._get_db = lambda: types.SimpleNamespace(get_session=lambda key: {'source': 'norman-io' if key == 'stored-owned' else 'whatsapp'})
        server._emit_approval_request = lambda sid, data: server._emit('approval.request', sid, dict(data))
        server._history_to_messages = lambda history: [{'role': row['role'], 'text': row.get('content', '')} for row in history if row['role'] != 'assistant' or row.get('content') or not row.get('tool_calls')]
        for method in ('session.create', 'session.resume', 'session.activate', 'session.history', 'session.interrupt', 'session.close', 'prompt.submit', 'clarify.respond', 'approval.respond'):
            server._methods[method] = lambda rid, params: server._ok(rid, dict(params))
        approval = types.SimpleNamespace(_lock=threading.Lock(), _gateway_queues={})
        return server, approval, emit_log

    def test_approval_has_correlated_id_and_resolves_only_matching_head(self):
        server, approval, events = self.server()
        bootstrap.install_guards(server, approval)
        a = types.SimpleNamespace(data={'command': 'echo a'}, event=threading.Event(), result=None)
        b = types.SimpleNamespace(data={'command': 'echo b'}, event=threading.Event(), result=None)
        approval._gateway_queues['stored-owned'] = [a, b]
        server._emit_approval_request('owned', a.data)
        server._emit_approval_request('owned', b.data)
        aid, bid = [event[2]['request_id'] for event in events]
        handler = server._methods['approval.respond']
        self.assertIn('error', handler(1, {'session_id': 'owned', 'request_id': bid, 'choice': 'once'}))
        self.assertEqual(handler(2, {'session_id': 'owned', 'request_id': aid, 'choice': 'once'})['result'], {'resolved': 1})
        self.assertEqual(a.result, 'once')
        self.assertTrue(a.event.is_set())
        self.assertFalse(b.event.is_set())
        self.assertIn('error', handler(3, {'session_id': 'owned', 'request_id': aid, 'choice': 'once'}))
        self.assertFalse(b.event.is_set())

    def test_expired_approval_cannot_resolve_a_new_queue_head(self):
        server, approval, events = self.server()
        bootstrap.install_guards(server, approval)
        first = types.SimpleNamespace(data={'command': 'same'}, event=threading.Event(), result=None)
        second = types.SimpleNamespace(data={'command': 'same'}, event=threading.Event(), result=None)
        approval._gateway_queues['stored-owned'] = [first]
        server._emit_approval_request('owned', first.data)
        stale_id = events[-1][2]['request_id']
        approval._gateway_queues['stored-owned'] = [second]
        server._emit_approval_request('owned', second.data)
        result = server._methods['approval.respond'](1, {'session_id': 'owned', 'request_id': stale_id, 'choice': 'once'})
        self.assertIn('error', result)
        self.assertFalse(second.event.is_set())

    def test_guard_rejects_unsupported_approval_internals(self):
        server, approval, _ = self.server()
        del approval._gateway_queues
        with self.assertRaisesRegex(RuntimeError, 'hermes_gateway_incompatible'):
            bootstrap.install_guards(server, approval)

    def test_status_requires_actual_thread_exit_and_exposes_no_metadata(self):
        server, approval, _ = self.server()
        server._sessions['owned']['_run_thread'] = types.SimpleNamespace(is_alive=lambda: True)
        bootstrap.install_guards(server, approval)
        status = server._methods['io.status'](1, {'session_id': 'owned'})['result']
        self.assertEqual(status, {'ready': True, 'failed': False, 'running': False, 'run_thread_alive': True, 'pending_prompt_ids': [], 'stored_session_id': 'stored-owned'})
        self.assertIn('error', server._methods['io.status'](2, {'session_id': 'foreign'}))

    def test_history_preserves_tool_call_markers_without_copying_tool_arguments(self):
        server, approval, _ = self.server()
        bootstrap.install_guards(server, approval)
        history = [{'role': 'user', 'content': 'q'}, {'role': 'assistant', 'content': 'checking', 'tool_calls': [{'secret': 'hidden'}]}, {'role': 'assistant', 'content': 'answer'}]
        result = server._history_to_messages(history)
        self.assertEqual(result[-2]['tool_calls'], True)
        self.assertEqual(result[-1]['tool_calls'], False)
        self.assertNotIn('hidden', str(result))

    def test_display_history_and_resume_fit_json_budget_without_changing_model_history(self):
        server, approval, _ = self.server()
        # Escapes use far more JSON bytes than raw UTF-8: the protocol limit
        # must measure encoded output, not just string length or UTF-8 length.
        history = [{'role': 'assistant', 'content': ('\x00\n"\\' * 8192) + str(index),
                    'tool_calls': [{'function': {'name': 'fixture'}}]}
                   for index in range(100)]
        marker = 'question\n\n[Norman IO request: 8f1ea18a-15a8-4785-a920-fcd6489f939d]'
        history += [{'role': 'user', 'content': marker}, {'role': 'assistant', 'content': 'Latest answer'}]
        raw_before = json.dumps(history)
        for method in ('session.history', 'session.resume'):
            server._methods[method] = lambda rid, params: server._ok(rid, {
                'session_id': 'owned', 'stored_session_id': 'stored-owned',
                'messages': server._history_to_messages(history),
            })
        bootstrap.install_guards(server, approval)
        for method, session_id in (('session.history', 'owned'), ('session.resume', 'stored-owned')):
            response = server._methods[method](1, {'session_id': session_id})
            messages = response['result']['messages']
            self.assertLessEqual(len(json.dumps(messages).encode()), 512 * 1024)
            self.assertLess(len(messages), len(history))
            self.assertEqual(messages[-2], {'role': 'user', 'text': marker})
            self.assertEqual(messages[-1], {'role': 'assistant', 'text': 'Latest answer', 'tool_calls': False})
            self.assertTrue(all(row.get('tool_calls') for row in messages[:-2]))
            self.assertLess(len(json.dumps(response).encode()), 2 * 1024 * 1024)
        self.assertEqual(json.dumps(history), raw_before, 'real model history stays untouched')

    def test_display_history_strips_non_chat_roles_and_private_fields(self):
        server, approval, _ = self.server()
        convert = server._history_to_messages
        server._history_to_messages = lambda history: [{**row, 'reasoning': 'PRIVATE', 'metadata': {'secret': 'PRIVATE'}} for row in convert(history)]
        bootstrap.install_guards(server, approval)
        result = server._history_to_messages([
            {'role': 'system', 'content': 'PRIVATE'}, {'role': 'user', 'content': 'question'},
            {'role': 'tool', 'content': 'PRIVATE'}, {'role': 'assistant', 'content': 'answer'},
        ])
        self.assertEqual(result, [{'role': 'user', 'text': 'question'}, {'role': 'assistant', 'text': 'answer', 'tool_calls': False}])

    def test_oversized_latest_message_does_not_expose_an_earlier_answer_as_final(self):
        server, approval, _ = self.server()
        bootstrap.install_guards(server, approval)
        history = [{'role': 'user', 'content': 'marker'},
                   {'role': 'assistant', 'content': 'Earlier answer'},
                   {'role': 'assistant', 'content': '\x00' * 600000}]
        self.assertEqual(server._history_to_messages(history), [])
        self.assertEqual(history[-1]['content'], '\x00' * 600000)

    def test_clarification_respond_checks_ownership_and_rejects_secret_rpc(self):
        server, approval, _ = self.server()
        bootstrap.install_guards(server, approval)
        server._pending['question'] = ('foreign', threading.Event())
        result = server._methods['clarify.respond'](1, {'session_id': 'owned', 'request_id': 'question', 'answer': 'a'})
        self.assertIn('error', result)
        self.assertNotIn('secret.respond', server._methods)
        self.assertNotIn('sudo.respond', server._methods)

    def test_resume_is_owned_source_only_and_new_sessions_cannot_change_source(self):
        server, approval, _ = self.server()
        bootstrap.install_guards(server, approval)
        self.assertIn('error', server._methods['session.resume'](1, {'session_id': 'stored-whatsapp'}))
        self.assertIn('result', server._methods['session.resume'](1, {'session_id': 'stored-owned'}))
        params = server._methods['session.create'](2, {'source': 'whatsapp', 'profile': 'other', 'cwd': '/tmp'})['result']
        self.assertEqual(params['source'], 'norman-io')
        self.assertEqual(params['cwd'], os.getcwd())
        self.assertNotIn('profile', params)


if __name__ == '__main__':
    unittest.main()
