"""Real loopback HTTP + real MCP stdio; all credentials/data temporary and synthetic."""
import asyncio
import copy
import json
import os
import socket
import sys
import threading
import time
import uvicorn
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from turbo_dashboard.client import Client
from turbo_dashboard.contracts import TEMPLATES
from turbo_dashboard.server import create_app
from turbo_dashboard.store import Store


def test_real_http_and_mcp_stdio(tmp_path):
    store = Store(tmp_path/'test.sqlite3')
    token = store.issue('writer', 'synthetic_device')
    token_file = tmp_path/'writer.token'; token_file.write_text(token); token_file.chmod(0o600)
    sock = socket.socket(); sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(create_app(store), log_level='error', access_log=False))
    thread = threading.Thread(target=server.run, kwargs={'sockets': [sock]}, daemon=True)
    thread.start()
    try:
        for _ in range(100):
            if server.started: break
            time.sleep(.01)
        assert server.started
        url = f'http://127.0.0.1:{port}'
        client = Client(url, token)
        try:
            card = client.save(copy.deepcopy(TEMPLATES[0]))
            changed = client.update(card['document']['id'], {'cpu_bar': {'value': 63}}, card['revision'])
            job = client.publish(changed['document']['id'], changed['revision'], changed['hash'], 'smoke')
            assert client.job(job['id'])['state'] == 'awaiting_phone_approval'
            async def exchange():
                params = StdioServerParameters(command=sys.executable, args=['-m', 'turbo_dashboard.mcp_server'],
                    env={'TURBOIO_API_URL': url, 'TURBOIO_TOKEN_FILE': str(token_file)})
                async with stdio_client(params) as (read, write):
                    async with ClientSession(read, write) as session:
                        await session.initialize()
                        tools = await session.list_tools()
                        assert len(tools.tools) == 12
                        result = await session.call_tool('card_get', {'ident': card['document']['id']})
                        assert not result.isError
                        payload = result.structuredContent or json.loads(result.content[0].text)
                        assert payload['revision'] == 2
                        gallery = await session.call_tool('app_gallery', {})
                        assert not gallery.isError
                        entries = (gallery.structuredContent or json.loads(gallery.content[0].text))['entries']
                        assert len(entries) == 20
                        built = await session.call_tool('app_build_snapshot', {
                            'recipe': 'city_weather', 'version': 2,
                            'snapshot': {'headline': '自己的 Server', 'lines': ['测试数据 26°C'],
                                         'observedAt': '2026-09-26T12:00:00+08:00'}})
                        assert not built.isError
                        result = built.structuredContent or json.loads(built.content[0].text)
                        import base64, hashlib
                        from turbo_dashboard.app_package import read_package
                        blob = base64.b64decode(result['zipBase64'], validate=True)
                        assert hashlib.sha256(blob).hexdigest() == result['sha256']
                        assert not result['installed']
                        assert read_package(blob)['document']['version'] == 2
                        invalid = await session.call_tool('card_save', {'document': {}, 'expected_revision': 0})
                        assert invalid.isError
            asyncio.run(asyncio.wait_for(exchange(), timeout=20))
        finally:
            client.close()
    finally:
        server.should_exit = True
        thread.join(timeout=5)
        sock.close()
        assert not thread.is_alive()
