"""Bounded stdin/JSON adapter to the owner's installed Hermes AIAgent.

Tested against Hermes 0.18.2, upstream 7b5ba205. Never imports the interactive
CLI or starts its gateway. Run through adapter.mjs's macOS write sandbox.
"""
import copy
import json
import logging
import os
import sys


def conversation_config(config):
    result = copy.deepcopy(config)
    result.setdefault('memory', {})['provider'] = ''
    result.setdefault('context', {})['engine'] = 'compressor'
    result.setdefault('sessions', {})['write_json_snapshots'] = False
    result.setdefault('compression', {})['enabled'] = False
    result['mcp_servers'] = {}
    result['hooks'] = {}
    result['fallback_model'] = None
    return result


def final_answer(result):
    if not isinstance(result, dict) or result.get('completed') is not True or result.get('failed') or result.get('interrupted'):
        raise ValueError('hermes_failed')
    text = result.get('final_response')
    if not isinstance(text, str) or not text.strip() or len(text.encode('utf-8')) > 8192:
        raise ValueError('invalid_answer')
    if any(message.get('tool_calls') or message.get('role') == 'tool' for message in result.get('messages', [])):
        raise ValueError('tools_forbidden')
    return text


def validate_input(payload):
    if not isinstance(payload, dict) or set(payload) != {'text', 'history'}:
        raise ValueError('invalid_input')
    if not isinstance(payload['text'], str) or not payload['text'].strip() or len(payload['text'].encode('utf-8')) > 8192:
        raise ValueError('invalid_input')
    history = payload['history']
    if not isinstance(history, list) or len(history) > 6:
        raise ValueError('invalid_input')
    for item in history:
        if not isinstance(item, dict) or set(item) != {'role', 'content'} or item['role'] not in ('user', 'assistant') or not isinstance(item['content'], str) or len(item['content'].encode('utf-8')) > 8192:
            raise ValueError('invalid_input')


def main():
    # Keep the protocol fd private. Third-party prints and exceptions never reach
    # the phone or bridge logs, including native writes to stdout/stderr.
    output = os.fdopen(os.dup(1), 'w', encoding='utf-8')
    sink = os.open(os.devnull, os.O_WRONLY)
    os.dup2(sink, 1)
    os.dup2(sink, 2)
    os.close(sink)
    logging.disable(logging.CRITICAL)
    stage = 'input'
    try:
        # History permits six messages plus the question. JSON can expand each
        # control character to six ASCII bytes; bound the envelope accordingly.
        limit = 512 * 1024
        raw = sys.stdin.buffer.read(limit + 1)
        if len(raw) > limit:
            raise ValueError('input_limit')
        payload = json.loads(raw)
        validate_input(payload)
        os.environ['HERMES_SAFE_MODE'] = '1'  # upstream plugin discovery kill switch
        os.environ['HERMES_INTERACTIVE'] = '0'
        os.environ.pop('HERMES_KANBAN_TASK', None)
        for name in ('HERMES_DUMP_REQUESTS', 'HERMES_DEBUG', 'HERMES_PLUGINS_DEBUG'):
            os.environ.pop(name, None)
        stage = 'runtime'
        import hermes_cli.config as config
        # Suppress first-run directory/template maintenance. Runtime files must
        # already exist in the owner's installation; do not seed or migrate it.
        config.ensure_hermes_home = lambda: None
        original_load = config.load_config
        restricted = conversation_config(original_load())
        config.load_config = lambda: copy.deepcopy(restricted)
        if hasattr(config, 'load_config_readonly'):
            config.load_config_readonly = lambda: copy.deepcopy(restricted)
        # AIAgent normally installs rotating file logs even in quiet mode.
        # The bridge deliberately has no transcript/debug-file sink.
        import hermes_logging
        hermes_logging.setup_logging = lambda *args, **kwargs: None
        hermes_logging.setup_verbose_logging = lambda *args, **kwargs: None
        import run_agent
        # .env is loaded internally by Hermes; reassert the process policy.
        os.environ['HERMES_SAFE_MODE'] = '1'
        os.environ.pop('HERMES_KANBAN_TASK', None)
        os.environ.pop('HERMES_DUMP_REQUESTS', None)
        from hermes_cli.runtime_provider import resolve_runtime_provider
        model_config = restricted.get('model', {})
        model = model_config.get('default', '')
        if not isinstance(model, str) or not model:
            raise ValueError('model_not_configured')
        runtime = resolve_runtime_provider(target_model=model)
        # External ACP/Codex app-server providers may carry their own tools.
        if runtime.get('api_mode') not in ('chat_completions', 'anthropic_messages', 'codex_responses'):
            raise ValueError('unsupported_transport')
        agent_config = restricted.get('agent', {})
        persona = agent_config.get('system_prompt', '')
        if not isinstance(persona, str):
            raise ValueError('invalid_persona')
        policy = ('当前通过 Norman IO 与用户对话。保留你的人设和记忆，默认中文、自然简洁，'
                  '适合眼镜阅读。这一入口只提供对话和已有记忆，不具备工具执行或记忆写入能力；'
                  '不要声称已操作文件、发消息或保存新记忆。不使用 Markdown 排版。')
        stage = 'initialization'
        agent = run_agent.AIAgent(
            model=model, provider=runtime['provider'], api_mode=runtime['api_mode'],
            api_key=runtime.get('api_key'), base_url=runtime.get('base_url'),
            enabled_toolsets=[], disabled_toolsets=[], max_iterations=2,
            max_tokens=1024, quiet_mode=True, verbose_logging=False,
            save_trajectories=False, session_db=None, checkpoints_enabled=False,
            skip_context_files=True, load_soul_identity=True, skip_memory=False,
            ephemeral_system_prompt=persona + '\n' + policy,
            platform='norman-conversation', fallback_model=None,
        )
        agent._skip_mcp_refresh = True
        agent._session_json_enabled = False
        agent._memory_nudge_interval = 0
        agent._skill_nudge_interval = 0
        if agent.tools or agent.valid_tool_names or agent._memory_manager is not None:
            raise ValueError('tools_not_disabled')
        # Defence in depth: even a provider that invents a tool call cannot dispatch it.
        def forbidden_tool(*_args, **_kwargs):
            raise ValueError('tools_forbidden')
        run_agent.handle_function_call = forbidden_tool
        stage = 'conversation'
        result = agent.run_conversation(payload['text'], conversation_history=payload['history'])
        answer = final_answer(result)
        output.write(json.dumps({'answer': answer}, ensure_ascii=False) + '\n')
        output.flush()
        return 0
    except Exception:
        # Fixed diagnostic only: raw provider exceptions may contain credentials.
        output.write(json.dumps({'error': 'hermes_' + stage + '_failed'}) + '\n')
        output.flush()
        return 1


if __name__ == '__main__':
    sys.exit(main())
