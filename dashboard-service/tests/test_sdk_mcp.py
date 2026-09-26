import asyncio
import json
import httpx
from turbo_dashboard.client import Client
from turbo_dashboard.mcp_server import create_mcp


def test_client_no_redirect_and_auth():
    observed = []
    def handler(request):
        observed.append(request)
        return httpx.Response(307, json={'error': {'code': 'redirect'}}, headers={'Location': 'https://elsewhere.invalid/'})
    from turbo_dashboard.contracts import Fault
    import pytest
    client = Client('http://127.0.0.1:1', 'synthetic-test-token', httpx.MockTransport(handler))
    with pytest.raises(Fault): client.cards()
    assert len(observed) == 1
    assert observed[0].headers['Authorization'] == 'Bearer synthetic-test-token'
    client.close()
    for url in ['http://example.com', 'https://u:p@example.com', 'https://example.com/?key=secret']:
        with pytest.raises(ValueError): Client(url, 'x')


def test_mcp_real_tool_registration_and_calls():
    observed = []
    def handler(request):
        observed.append(request)
        return httpx.Response(200, json={'physicalVerified': False, 'cardProtocol': 'TCE1'})
    client = Client('http://127.0.0.1:1', 'synthetic-test-token', httpx.MockTransport(handler))
    server = create_mcp(client)
    async def run():
        tools = await server.list_tools()
        names = {t.name for t in tools}
        assert len(names) == 12 and 'card_request_publish' in names and 'app_build_snapshot' in names
        assert not any('flash' in n or 'approve' in n for n in names)
        result = await server.call_tool('capabilities', {})
        assert result
    asyncio.run(run())
    assert observed[0].url.path == '/v1/capabilities'
    client.close()
