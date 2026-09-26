"""Authenticated local-first API. No device I/O or credential forwarding."""
import json
import base64
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from .contracts import Fault, SCHEMA, TEMPLATES, exact, validate
from .store import Store
from .app_package import validate_app, read_package, build_package
from .gallery import catalog, snapshot_doc
from .preview import render


def create_app(store: Store):
    app = FastAPI(title='Turbo IO Developer API', version='0.1.0')

    @app.exception_handler(Fault)
    async def fault_handler(request, error):
        return JSONResponse({'error': {'code': error.code, 'message': error.message}}, status_code=error.status)

    @app.middleware('http')
    async def guard(request: Request, call_next):
        if request.url.path == '/health' and request.method == 'GET':
            return await call_next(request)
        try:
            auth = request.headers.get('authorization', '')
            if not auth.startswith('Bearer '):
                raise Fault('unauthorized', 'Bearer token required', 401)
            request.state.identity = store.authenticate(auth[7:])
            # Bound streamed input before FastAPI parses JSON (including chunked input).
            chunks, size = [], 0
            async for chunk in request.stream():
                size += len(chunk)
                if size > 32768:
                    raise Fault('body_limit', 'Request exceeds 32 KiB', 413)
                chunks.append(chunk)
            request._body = b''.join(chunks)
            response = await call_next(request)
            response.headers['Cache-Control'] = 'no-store'
            return response
        except Fault as error:
            return await fault_handler(request, error)

    def principal(request, roles):
        p = request.state.identity
        if p['role'] not in roles:
            raise Fault('forbidden', 'Token role cannot perform this operation', 403)
        return p['device']

    async def body(request, keys):
        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ValueError('duplicate key')
                result[key] = value
            return result
        try:
            value = json.loads(await request.body(), object_pairs_hook=pairs,
                               parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        except (ValueError, UnicodeError, RecursionError):
            raise Fault('invalid_json', 'Invalid JSON object') from None
        exact(value, keys)
        return value

    @app.get('/health')
    def health():
        return {'ok': True, 'deviceConnected': False, 'mode': 'api-only'}

    @app.get('/v1/capabilities')
    def capabilities():
        return {'cardProtocol': 'TCE1', 'cardSchema': SCHEMA, 'templates': TEMPLATES,
                'delivery': 'phone-approval-required', 'phoneAdapterIntegrated': False,
                'phoneAdapterBuild': 'EDITOR-PHONE-04-BACKEND', 'phoneConnectionObserved': False,
                'appRuntimeInstalled': False, 'appPackageValidator': 'TAP1-draft',
                'automaticRetry': False, 'physicalVerified': False}

    @app.get('/v1/identity')
    def identity(request: Request):
        return dict(request.state.identity)

    @app.post('/v1/cards/validate')
    async def check(request: Request):
        data = await body(request, ['document'])
        return validate(data['document'])

    @app.post('/v1/apps/validate')
    async def check_app(request: Request):
        data = await body(request, ['document'])
        return validate_app(data['document'])

    @app.get('/v1/apps/gallery')
    def app_gallery():
        return {'schema':1,'entries':catalog(),'remoteServicesConnected':False}

    def package_result(document):
        raw=build_package(document)
        import hashlib
        return {'zipBase64':base64.b64encode(raw).decode(), 'sha256':hashlib.sha256(raw).hexdigest(),
                'zipBytes':len(raw),'installed':False,'delivery':'manual-phone-import',
                'id':document['id'],'version':document['version']}

    @app.post('/v1/apps/package')
    async def package_app(request:Request):
        principal(request,['writer'])
        data=await body(request,['document'])
        return package_result(data['document'])

    @app.post('/v1/apps/gallery/{ident}/package')
    async def package_recipe(ident:str,request:Request):
        principal(request,['writer'])
        data=await body(request,['snapshot','version'])
        return package_result(snapshot_doc(ident,data['snapshot'],data['version']))

    @app.post('/v1/cards/preview')
    async def preview_card(request: Request):
        data = await body(request, ['document'])
        return Response(render(data['document']), media_type='image/svg+xml', headers={'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; sandbox", 'X-Content-Type-Options': 'nosniff'})

    @app.post('/v1/apps/package/validate')
    async def check_package(request: Request):
        data = await body(request, ['zipBase64'])
        try:
            raw = base64.b64decode(data['zipBase64'], validate=True)
        except (ValueError, TypeError):
            raise Fault('zip_encoding', 'Expected base64 ZIP') from None
        result = read_package(raw)
        return {k: v for k, v in result.items() if k != 'document'}

    @app.get('/v1/cards')
    def cards(request: Request):
        return store.cards(principal(request, ['writer', 'reader', 'phone']))

    @app.get('/v1/cards/{ident}')
    def get_card(ident: str, request: Request):
        return store.get(principal(request, ['writer', 'reader', 'phone']), ident)

    @app.put('/v1/cards/{ident}')
    async def save_card(ident: str, request: Request):
        device = principal(request, ['writer'])
        data = await body(request, ['expectedRevision', 'document'])
        return store.save(device, ident, data['expectedRevision'], document=data['document'])

    @app.patch('/v1/cards/{ident}/data')
    async def data_card(ident: str, request: Request):
        device = principal(request, ['writer'])
        data = await body(request, ['expectedRevision', 'updates'])
        return store.save(device, ident, data['expectedRevision'], updates=data['updates'])

    @app.post('/v1/cards/{ident}/publish')
    async def publish(ident: str, request: Request):
        device = principal(request, ['writer'])
        data = await body(request, ['revision', 'hash', 'idempotencyKey', 'ttlSeconds'])
        return store.publish(device, ident, data['revision'], data['hash'], data['idempotencyKey'], data['ttlSeconds'])

    @app.get('/v1/jobs')
    def jobs(request: Request):
        return store.jobs(principal(request, ['writer', 'reader', 'phone']))

    @app.get('/v1/jobs/{ident}')
    def job(ident: str, request: Request):
        return store.job(principal(request, ['writer', 'reader', 'phone']), ident,
                         include_document=request.state.identity['role'] == 'phone')

    @app.post('/v1/phone/jobs/{ident}/approve')
    async def approve(ident: str, request: Request):
        device = principal(request, ['phone'])
        data = await body(request, ['hash'])
        return store.approve(device, ident, data['hash'])

    @app.post('/v1/phone/jobs/{ident}/receipt')
    async def receipt(ident: str, request: Request):
        device = principal(request, ['phone'])
        data = await body(request, ['receiptToken', 'state', 'code'])
        return store.receipt(device, ident, data['receiptToken'], data['state'], data['code'])

    # Manual bounded parsing above rejects duplicate JSON keys, unlike typical
    # request-model parsing. Still expose honest request schemas for SDK authors.
    schemas = {
        ('/v1/cards/validate', 'POST'): {'document': SCHEMA},
        ('/v1/cards/preview', 'POST'): {'document': SCHEMA},
        ('/v1/cards/{ident}', 'PUT'): {'expectedRevision': {'type': 'integer', 'minimum': 0}, 'document': SCHEMA},
        ('/v1/cards/{ident}/data', 'PATCH'): {'expectedRevision': {'type': 'integer', 'minimum': 1}, 'updates': {'type': 'object', 'minProperties': 1, 'maxProperties': 12}},
        ('/v1/cards/{ident}/publish', 'POST'): {'revision': {'type': 'integer', 'minimum': 1}, 'hash': {'type': 'string'}, 'idempotencyKey': {'type': 'string'}, 'ttlSeconds': {'type': 'integer', 'minimum': 30, 'maximum': 3600}},
        ('/v1/phone/jobs/{ident}/approve', 'POST'): {'hash': {'type': 'string'}},
        ('/v1/phone/jobs/{ident}/receipt', 'POST'): {'receiptToken': {'type': 'string'}, 'state': {'enum': ['device_accepted', 'failed', 'outcome_unknown']}, 'code': {'type': 'string'}},
        ('/v1/apps/validate', 'POST'): {'document': {'type': 'object', 'description': 'TAP1 draft: see App SDK contract'}},
        ('/v1/apps/package','POST'): {'document':{'type':'object','description':'Validated TAP1 app.json'}},
        ('/v1/apps/gallery/{ident}/package','POST'): {'snapshot':{'type':['object','null'],'description':'null for explicit demo; otherwise headline, lines, observedAt'},'version':{'type':'integer','minimum':1,'maximum':65535}},
        ('/v1/apps/package/validate', 'POST'): {'zipBase64': {'type': 'string', 'contentEncoding': 'base64'}},
    }
    for route in app.routes:
        props = next((schemas[(route.path, method)] for method in getattr(route, 'methods', []) if (route.path, method) in schemas), None)
        if props:
            # Card schema local $defs must live at the same request-schema root.
            properties = dict(props)
            defs = None
            if properties.get('document') is SCHEMA:
                properties['document'] = {k: v for k, v in SCHEMA.items() if k not in ('$schema', '$id', '$defs')}
                defs = SCHEMA['$defs']
            schema = {'type': 'object', 'additionalProperties': False, 'required': list(props), 'properties': properties}
            if defs:
                # OpenAPI uses document-root references, not JSON Schema resource roots.
                schema['$defs'] = defs
                schema = json.loads(json.dumps(schema).replace('#/$defs/component', '#/components/schemas/TCEComponent'))
            route.openapi_extra = {'requestBody': {'required': True, 'content': {'application/json': {'schema': schema}}}}
    from fastapi.openapi.utils import get_openapi
    def openapi():
        if app.openapi_schema is None:
            spec = get_openapi(title=app.title, version=app.version, routes=app.routes)
            components = spec.setdefault('components', {})
            components.setdefault('schemas', {})['TCEComponent'] = SCHEMA['$defs']['component']
            components['securitySchemes'] = {'BearerAuth': {'type': 'http', 'scheme': 'bearer'}}
            for path, methods in spec['paths'].items():
                if path != '/health':
                    for operation in methods.values():
                        operation['security'] = [{'BearerAuth': []}]
            app.openapi_schema = spec
        return app.openapi_schema
    app.openapi = openapi
    return app
