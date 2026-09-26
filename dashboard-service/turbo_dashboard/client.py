"""Small SDK: explicit URLs, no redirects, no auto retries, no device secrets."""
from urllib.parse import urlsplit
import httpx
from .contracts import Fault, validate
from .store import identifier


class Client:
    def __init__(self, url, token, transport=None):
        parts = urlsplit(url)
        if parts.username or parts.password or parts.query or parts.fragment or parts.path not in ('', '/'):
            raise ValueError('Use a service origin, not credentials or a URL path')
        if not parts.hostname or not (parts.scheme == 'https' or (parts.scheme == 'http' and parts.hostname in ('127.0.0.1', 'localhost', '::1'))):
            raise ValueError('Remote services require HTTPS; HTTP is loopback-only')
        self.http = httpx.Client(base_url=url.rstrip('/'), headers={'Authorization': 'Bearer '+token},
                                 timeout=15, follow_redirects=False, trust_env=False, transport=transport)

    def close(self):
        self.http.close()

    def request(self, method, path, payload=None):
        try:
            with self.http.stream(method, path, json=payload) as response:
                chunks, size = [], 0
                for chunk in response.iter_bytes():
                    size += len(chunk)
                    if size > 1_048_576:
                        raise Fault('response_limit', 'API response exceeds 1 MiB')
                    chunks.append(chunk)
                import json
                try:
                    data = json.loads(b''.join(chunks))
                except ValueError:
                    raise Fault('upstream', 'API returned non-JSON response', 502) from None
                if response.status_code >= 300:
                    error = data.get('error', {}) if isinstance(data, dict) else {}
                    raise Fault(error.get('code', 'http_error'), 'API rejected request; inspect status/code', response.status_code)
                return data
        except httpx.HTTPError:
            raise Fault('network', 'API network failure; write outcome may be unknown, no retry performed', 502) from None

    def capabilities(self):
        return self.request('GET', '/v1/capabilities')

    def cards(self):
        return self.request('GET', '/v1/cards')

    def app_gallery(self):
        return self.request('GET','/v1/apps/gallery')

    def app_package(self,document):
        from .app_package import validate_app
        validate_app(document)
        return self.request('POST','/v1/apps/package',{'document':document})

    def app_snapshot(self,recipe,snapshot,version):
        from .gallery import snapshot_doc
        snapshot_doc(recipe,snapshot,version)
        return self.request('POST','/v1/apps/gallery/'+identifier(recipe)+'/package',{'snapshot':snapshot,'version':version})

    def get(self, ident):
        return self.request('GET', '/v1/cards/'+identifier(ident))

    def save(self, document, expected_revision=0):
        validate(document)
        return self.request('PUT', '/v1/cards/'+document['id'], {'document': document, 'expectedRevision': expected_revision})

    def update(self, ident, updates, expected_revision):
        return self.request('PATCH', '/v1/cards/'+identifier(ident)+'/data', {'updates': updates, 'expectedRevision': expected_revision})

    def publish(self, ident, revision, doc_hash, idempotency_key, ttl_seconds=300):
        return self.request('POST', '/v1/cards/'+identifier(ident)+'/publish',
                            dict(revision=revision, hash=doc_hash, idempotencyKey=idempotency_key, ttlSeconds=ttl_seconds))

    def job(self, ident):
        return self.request('GET', '/v1/jobs/'+identifier(ident))
