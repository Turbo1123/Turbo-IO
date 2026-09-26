"""MCP v1 stdio facade, same API and scopes as ordinary SDK clients."""
import os
from pathlib import Path
from mcp.server.fastmcp import FastMCP
from .client import Client
from .contracts import validate
from .app_package import validate_app


def create_mcp(client):
    mcp = FastMCP('Turbo IO Developer SDK')

    @mcp.tool()
    def capabilities() -> dict:
        """Read supported card templates/schema and integration readiness."""
        return client.capabilities()

    @mcp.tool()
    def cards() -> list:
        """List drafts in this token's device scope, not glasses screenshots."""
        return client.cards()

    @mcp.tool()
    def card_get(ident: str) -> dict:
        """Read a draft, its revision and content hash before editing."""
        return client.get(ident)

    @mcp.tool()
    def card_validate(document: dict) -> dict:
        """Validate bounded card locally. Does not send to glasses."""
        return validate(document)

    @mcp.tool()
    def card_save(document: dict, expected_revision: int) -> dict:
        """Save an authorized draft. This does not publish to glasses."""
        return client.save(document, expected_revision)

    @mcp.tool()
    def card_update_data(ident: str, updates: dict, expected_revision: int) -> dict:
        """Change data only, not geometry, using optimistic revision control."""
        return client.update(ident, updates, expected_revision)

    @mcp.tool()
    def card_request_publish(ident: str, revision: int, doc_hash: str, idempotency_key: str) -> dict:
        """Request publication after user approval; phone must separately approve exact hash.

        Returns a pending job, NOT proof of delivery. No firmware flashing.
        """
        return client.publish(ident, revision, doc_hash, idempotency_key)

    @mcp.tool()
    def delivery_status(job_id: str) -> dict:
        """Read job status. Device acceptance is not physical visual verification."""
        return client.job(job_id)

    @mcp.tool()
    def app_validate(document: dict) -> dict:
        """Validate TAP1 app data, without installing or connecting glasses."""
        return validate_app(document)

    @mcp.tool()
    def app_gallery() -> dict:
        """List 20 offline MCP recipes and copyable development prompts; not live integrations."""
        return client.app_gallery()

    @mcp.tool()
    def app_build_package(document:dict) -> dict:
        """Build a bounded ZIP (base64, SHA256). No install, secrets or executable code."""
        return client.app_package(document)

    @mcp.tool()
    def app_build_snapshot(recipe:str,snapshot:dict,version:int) -> dict:
        """Convert user-server MCP display fields to a ZIP; caller supplies actual data/time.

        No external MCP is called by this tool. No automatic refresh or event forwarding.
        """
        return client.app_snapshot(recipe,snapshot,version)

    return mcp


def main():
    # File path avoids putting bearer token into agent configuration or arguments.
    token = Path(os.environ['TURBOIO_TOKEN_FILE']).read_text().strip()
    client = Client(os.environ.get('TURBOIO_API_URL', 'http://127.0.0.1:18796'), token)
    try:
        create_mcp(client).run(transport='stdio')
    finally:
        client.close()


if __name__ == '__main__':
    main()
