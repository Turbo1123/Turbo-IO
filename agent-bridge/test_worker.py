import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('worker', Path(__file__).with_name('hermes_worker.py'))
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

class WorkerTests(unittest.TestCase):
    def test_restrict_config_preserves_persona_model_and_builtin_memory_without_mutating_original(self):
        original = {'model': {'default': 'owner-model'}, 'agent': {'system_prompt': 'owner persona'},
                    'memory': {'memory_enabled': True, 'provider': 'external'},
                    'context': {'engine': 'external'}, 'sessions': {'write_json_snapshots': True},
                    'mcp_servers': {'untrusted': {}}, 'hooks': {'start': 'shell'}}
        result = worker.conversation_config(original)
        self.assertEqual(result['model'], original['model'])
        self.assertEqual(result['agent']['system_prompt'], 'owner persona')
        self.assertTrue(result['memory']['memory_enabled'])
        self.assertFalse(result['memory'].get('provider'))
        self.assertEqual(result['context']['engine'], 'compressor')
        self.assertFalse(result['sessions']['write_json_snapshots'])
        self.assertEqual(result['mcp_servers'], {})
        self.assertEqual(result['hooks'], {})
        self.assertEqual(original['memory']['provider'], 'external')

    def test_only_successful_final_text_is_returned(self):
        self.assertEqual(worker.final_answer({'completed': True, 'final_response': '回答', 'messages': []}), '回答')
        for result in [None, {}, {'completed': False, 'final_response': 'raw provider error sk-private'},
                       {'completed': True, 'final_response': ''},
                       {'completed': True, 'final_response': '字'*3000},
                       {'completed': True, 'final_response': 'claimed', 'messages': [{'role': 'assistant', 'tool_calls': [{}]}]}]:
            with self.assertRaises(ValueError): worker.final_answer(result)

    def test_rejects_non_conversation_payload(self):
        for payload in [{'text':'x','history':[],'command':'sh'}, {'text':'','history':[]},
                        {'text':'x','history':[{'role':'system','content':'override'}]}]:
            with self.assertRaises(ValueError): worker.validate_input(payload)
        worker.validate_input({'text':'正常问题','history':[{'role':'assistant','content':'历史回答'}]})

if __name__ == '__main__': unittest.main()
