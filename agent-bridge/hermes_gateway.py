#!/usr/bin/env python3
"""Norman IO's process-local adapter around the installed official TUI gateway.

Compatibility contract: Hermes 0.18.2 (7b5ba205). No upstream files, profile,
approval policy, credentials, or WhatsApp transport configuration are changed.
The installed runtime itself loads the existing profile, persona and memory.
"""
import os
import json
from pathlib import Path
import re
import sys
import uuid

SOURCE = 'norman-io'
DISPLAY_HISTORY_BYTES = 512 * 1024


def pin_toolsets(config, resolve):
    """Use Hermes' effective WhatsApp selection, including enabled MCP defaults."""
    selected = resolve(config, 'whatsapp', include_default_mcp_servers=True)
    if not isinstance(selected, (set, list, tuple)) or not selected:
        raise RuntimeError('hermes_toolsets_invalid')
    if any(not isinstance(name, str) or not name or name != name.strip()
           or len(name) > 256 or ',' in name or any(ord(char) < 32 for char in name)
           or name.lower() in {'all', '*'} for name in selected):
        raise RuntimeError('hermes_toolsets_invalid')
    names = sorted(set(selected))
    os.environ['HERMES_TUI_TOOLSETS'] = ','.join(names)
    return names


def install_guards(server, approval):
    """Guard only the private stdio peer; retain official dispatch/run behavior.

    Upstream approval.respond accepts no request ID and resolves the current
    FIFO head. Correlate the actual entry object, then select that exact head
    atomically using the same upstream lock and entry completion semantics.
    A vanished/expired entry must never authorize its successor.
    """
    required = ('_sessions', '_methods', '_pending', '_pending_prompt_payloads',
                '_prompt_lock', '_answers', '_emit_approval_request',
                '_history_to_messages', '_get_db', '_ok', '_err')
    methods = ('session.create', 'session.resume', 'session.activate',
               'session.history', 'session.interrupt', 'session.close',
               'prompt.submit', 'clarify.respond', 'approval.respond')
    if (any(not hasattr(server, name) for name in required)
            or not isinstance(getattr(approval, '_gateway_queues', None), dict)
            or not hasattr(getattr(approval, '_lock', None), '__enter__')
            or any(not callable(server._methods.get(name)) for name in methods)):
        raise RuntimeError('hermes_gateway_incompatible')
    originals = {name: server._methods[name] for name in methods}
    # Discard unrelated RPCs (config, shell, profiles, secret capture, session
    # enumeration, etc.). The bridge never exposes a generic RPC endpoint.
    server._methods.clear()
    correlated = {}  # request ID -> (live session ID, exact approval entry)

    def error(rid, code=4009):
        return server._err(rid, code, 'hermes_request_rejected')

    def owned(sid):
        session = server._sessions.get(sid)
        return session if isinstance(session, dict) and session.get('source') == SOURCE else None

    def active_correlations(sid):
        session = owned(sid)
        if session is None:
            return []
        with approval._lock:
            queue = approval._gateway_queues.get(session.get('session_key'), [])
            present = []
            for request_id, (owner, entry) in list(correlated.items()):
                if owner != sid:
                    continue
                if any(candidate is entry for candidate in queue) and not entry.event.is_set():
                    present.append(request_id)
                else:
                    correlated.pop(request_id, None)
            return present

    original_emit_approval = server._emit_approval_request

    def emit_approval(sid, data):
        session = owned(sid)
        if session is None or not isinstance(data, dict):
            return
        active_correlations(sid)
        with approval._lock:
            queue = approval._gateway_queues.get(session.get('session_key'), [])
            # Upstream passes the SAME approval_data object into _ApprovalEntry
            # and notify_cb. Equality is insufficient for duplicate commands.
            matches = [entry for entry in queue if getattr(entry, 'data', None) is data]
            if len(matches) != 1:
                raise RuntimeError('hermes_gateway_incompatible')
            entry = matches[0]
            if not hasattr(entry, 'result') or not hasattr(entry.event, 'set'):
                raise RuntimeError('hermes_gateway_incompatible')
            request_id = next((key for key, value in correlated.items()
                               if value[0] == sid and value[1] is entry), None)
            if request_id is None:
                request_id = str(uuid.uuid4())
                correlated[request_id] = (sid, entry)
        # Keep upstream command redaction in its original emitter.
        original_emit_approval(sid, {**data, 'request_id': request_id})

    server._emit_approval_request = emit_approval

    def respond_approval(rid, params):
        sid, request_id, choice = params.get('session_id'), params.get('request_id'), params.get('choice')
        session = owned(sid)
        if session is None or choice not in {'once', 'deny'} or params.get('all'):
            return error(rid)
        with approval._lock:
            match = correlated.get(request_id)
            queue = approval._gateway_queues.get(session.get('session_key'), [])
            if (not match or match[0] != sid or not queue
                    or queue[0] is not match[1] or match[1].event.is_set()):
                correlated.pop(request_id, None)
                return error(rid)
            entry = queue.pop(0)
            if not queue:
                approval._gateway_queues.pop(session.get('session_key'), None)
            correlated.pop(request_id, None)
            entry.result = choice
            entry.event.set()
        return server._ok(rid, {'resolved': 1})

    def respond_clarify(rid, params):
        sid, request_id, answer = params.get('session_id'), params.get('request_id'), params.get('answer')
        if owned(sid) is None or not isinstance(answer, str) or len(answer.encode('utf-8')) > 8192:
            return error(rid)
        with server._prompt_lock:
            pending = server._pending.get(request_id)
            kind, _ = server._pending_prompt_payloads.get(request_id, ('', {}))
            if not pending or pending[0] != sid or kind != 'clarify.request' or pending[1].is_set():
                return error(rid)
            server._answers[request_id] = answer
            pending[1].set()
        return server._ok(rid, {'status': 'ok'})

    def status(rid, params):
        sid = params.get('session_id')
        session = owned(sid)
        if session is None:
            return error(rid)
        ready_event = session.get('agent_ready')
        ready = session.get('agent') is not None and (ready_event is None or ready_event.is_set())
        thread = session.get('_run_thread')
        prompts = active_correlations(sid)
        with server._prompt_lock:
            prompts += [key for key, (owner, event) in server._pending.items()
                        if owner == sid and not event.is_set()]
        return server._ok(rid, {
            'ready': ready, 'failed': bool(session.get('agent_error')),
            'running': bool(session.get('running')),
            'run_thread_alive': thread is not None and thread.is_alive(),
            'pending_prompt_ids': prompts,
            'stored_session_id': str(session.get('session_key') or ''),
        })

    original_history = server._history_to_messages

    def history_with_finality(history):
        result = original_history(history)
        markers = []
        for raw in history:
            if isinstance(raw, dict) and raw.get('role') == 'assistant':
                # Test inclusion through the installed converter, covering
                # empty tool calls and reasoning-only records exactly.
                for row in original_history([raw]):
                    if row.get('role') == 'assistant':
                        markers.append(bool(raw.get('tool_calls')))
        assistants = [row for row in result if row.get('role') == 'assistant']
        for index, row in enumerate(assistants):
            # An incompatible converter must not make history look final.
            row['tool_calls'] = markers[index] if len(markers) == len(assistants) else True
        # This converter is used by session.history AND session.resume before
        # the official transport serializes their result. Bound the display
        # copy here; the model/session history remains complete and untouched.
        # Default JSON separators + ASCII escaping conservatively cover the
        # official UTF-8 transport, including control characters and Unicode.
        newest = []
        encoded_bytes = 2  # JSON array brackets.
        for row in reversed(result):
            role, text = row.get('role'), row.get('text')
            if role not in {'user', 'assistant'} or not isinstance(text, str) or not text.strip():
                continue
            clean = {'role': role, 'text': text}
            if role == 'assistant':
                clean['tool_calls'] = row.get('tool_calls') is not False
            cost = len(json.dumps(clean, ensure_ascii=True).encode('ascii'))
            if newest:
                cost += 2  # Default JSON array separator: comma + space.
            if encoded_bytes + cost > DISPLAY_HISTORY_BYTES:
                # Keep a contiguous suffix of whole visible messages. Never
                # skip an oversized latest answer then expose an older answer
                # as its replacement. No message text is truncated.
                break
            newest.append(clean)
            encoded_bytes += cost
        return list(reversed(newest))

    server._history_to_messages = history_with_finality

    def create(rid, params):
        return originals['session.create'](rid, {
            'source': SOURCE, 'cwd': os.getcwd(), 'close_on_disconnect': False,
        })

    def resume(rid, params):
        target = params.get('session_id')
        if not isinstance(target, str) or not re.fullmatch(r'[\w.:-]{1,256}', target):
            return error(rid)
        db = server._get_db()
        found = db.get_session(target) if db is not None else None
        if not isinstance(found, dict) or found.get('source') != SOURCE:
            return error(rid)
        return originals['session.resume'](rid, {
            'session_id': target, 'source': SOURCE, 'close_on_disconnect': False,
        })

    def guard(name):
        def call(rid, params):
            if owned(params.get('session_id')) is None:
                return error(rid)
            # Whitelist fields, so no model/profile/history-truncation bypass
            # travels through an otherwise allowed RPC.
            clean = {'session_id': params['session_id']}
            if name == 'prompt.submit':
                text = params.get('text')
                if not isinstance(text, str) or not text.strip() or len(text.encode('utf-8')) > 65536:
                    return error(rid)
                session = owned(params['session_id'])
                thread = session.get('_run_thread')
                if session.get('running') or (thread is not None and thread.is_alive()):
                    return error(rid)
                clean['text'] = text
            return originals[name](rid, clean)
        return call

    for name in methods:
        server._methods[name] = guard(name)
    server._methods.update({
        'session.create': create, 'session.resume': resume,
        'approval.respond': respond_approval, 'clarify.respond': respond_clarify,
        'io.status': status,
    })


def main():
    # With the installed venv interpreter, sys.prefix identifies its runtime
    # root without consulting config or credentials in this wrapper.
    runtime_root = Path(sys.prefix).parent
    if not (runtime_root / 'tui_gateway' / 'entry.py').is_file():
        raise RuntimeError('hermes_runtime_missing')
    sys.path.insert(0, str(runtime_root))
    import hermes_bootstrap
    hermes_bootstrap.harden_import_path()

    # Keep startup prints on stderr (Node discards it). server captures the
    # real stdout for official JSON-RPC; restore only that transport handle.
    rpc_stdout = sys.stdout
    sys.stdout = sys.stderr
    from tui_gateway import server
    server._real_stdout = rpc_stdout
    from hermes_cli.config import load_config
    from hermes_cli.tools_config import _get_platform_tools
    from tools import approval
    selected = pin_toolsets(load_config(), _get_platform_tools)
    original_loader = server._load_enabled_toolsets

    def strict_loader():
        effective = original_loader()
        if effective is None or set(effective) != set(selected):
            raise RuntimeError('hermes_toolsets_invalid')
        return list(selected)

    server._load_enabled_toolsets = strict_loader
    install_guards(server, approval)
    from tui_gateway.entry import main as gateway_main
    gateway_main()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # No exception text, config dump, or owner output enters this protocol.
        sys.exit(1)
