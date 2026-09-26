import copy
import concurrent.futures
import pytest
from fastapi.testclient import TestClient
from turbo_dashboard.server import create_app
from turbo_dashboard.store import Store
from turbo_dashboard.contracts import TEMPLATES, Fault, validate, layout_hash


@pytest.fixture
def api(tmp_path):
    store = Store(tmp_path/'test.sqlite3')
    client = TestClient(create_app(store))
    headers = {r: {'Authorization': 'Bearer '+store.issue(r, 'test')} for r in ['writer', 'phone', 'reader']}
    return store, client, headers


def create(client, headers):
    doc = copy.deepcopy(TEMPLATES[0])
    response = client.put('/v1/cards/'+doc['id'], headers=headers, json={'expectedRevision': 0, 'document': doc})
    assert response.status_code == 200, response.text
    return response.json()


def publish(client, headers, card, key='test'):
    return client.post('/v1/cards/'+card['document']['id']+'/publish', headers=headers,
        json={'revision': card['revision'], 'hash': card['hash'], 'idempotencyKey': key, 'ttlSeconds': 60})


def test_full_lifecycle_simulated_phone(api):
    store, client, h = api
    card = create(client, h['writer'])
    job = publish(client, h['writer'], card).json()
    assert job['state'] == 'awaiting_phone_approval' and not job['physicalVerified']
    assert publish(client, h['writer'], card).json()['id'] == job['id']
    url = '/v1/phone/jobs/'+job['id']
    assert client.post(url+'/approve', headers=h['writer'], json={'hash': card['hash']}).status_code == 403
    claim = client.post(url+'/approve', headers=h['phone'], json={'hash': card['hash']}).json()
    assert claim['document'] == card['document']
    assert client.post(url+'/approve', headers=h['phone'], json={'hash': card['hash']}).status_code == 409
    data = {'receiptToken': claim['receiptToken'], 'state': 'device_accepted', 'code': 'simulated_readback'}
    receipt = client.post(url+'/receipt', headers=h['phone'], json=data)
    assert receipt.status_code == 200 and not receipt.json()['physicalVerified']
    assert client.post(url+'/receipt', headers=h['phone'], json=data).status_code == 200
    data['state'] = 'failed'
    assert client.post(url+'/receipt', headers=h['phone'], json=data).status_code == 409
    assert Store(store.path).job('test', job['id'])['state'] == 'device_accepted'


def test_data_only_revision_and_snapshot(api):
    _, client, h = api
    card = create(client, h['writer']); url = '/v1/cards/'+card['document']['id']
    job = publish(client, h['writer'], card).json()
    changed = client.patch(url+'/data', headers=h['writer'], json={'expectedRevision': 1, 'updates': {'cpu_bar': {'value': 75}}})
    assert changed.status_code == 200
    assert layout_hash(card['document']) == layout_hash(changed.json()['document'])
    assert client.patch(url+'/data', headers=h['writer'], json={'expectedRevision': 1, 'updates': {'cpu_bar': {'value': 10}}}).status_code == 409
    assert client.patch(url+'/data', headers=h['writer'], json={'expectedRevision': 2, 'updates': {'cpu_bar': {'x': 20}}}).status_code == 422
    # Pending publication is immutable even after editing the draft.
    snapshot = client.get('/v1/jobs/'+job['id'], headers=h['phone']).json()['document']
    assert snapshot == card['document']


def test_auth_scope_and_bad_input(api):
    store, client, h = api
    assert client.get('/health').status_code == 200
    assert client.get('/v1/cards').status_code == 401
    assert client.get('/v1/identity').status_code == 401
    assert client.get('/v1/identity', headers=h['phone']).json() == {'role': 'phone', 'device': 'test'}
    card = create(client, h['writer'])
    other = {'Authorization': 'Bearer '+store.issue('writer', 'other')}
    assert client.get('/v1/cards', headers=other).json() == []
    assert client.get('/v1/cards/'+card['document']['id'], headers=other).status_code == 404
    assert client.put('/v1/cards/'+card['document']['id'], headers=h['reader'], json={}).status_code == 403
    assert client.post('/v1/cards/validate', headers=h['writer'], content=b'x'*32769).status_code == 413
    assert client.post('/v1/cards/validate', headers=h['writer'], content=b'{"document":{},"document":{}}').status_code == 422
    assert client.post('/v1/cards/validate', headers=h['writer'], json={'document': card['document'], 'key': 'forbidden'}).status_code == 422
    assert client.get('/openapi.json', headers=h['reader']).status_code == 200


def test_timeouts_do_not_retry(api):
    store, client, h = api
    now = [1000]; store.clock = lambda: now[0]
    card = create(client, h['writer']); job = publish(client, h['writer'], card).json()
    now[0] = 1061
    assert client.get('/v1/jobs/'+job['id'], headers=h['writer']).json()['state'] == 'expired'
    assert client.post('/v1/phone/jobs/'+job['id']+'/approve', headers=h['phone'], json={'hash': card['hash']}).status_code == 409
    job2 = publish(client, h['writer'], card, 'second').json()
    client.post('/v1/phone/jobs/'+job2['id']+'/approve', headers=h['phone'], json={'hash': card['hash']})
    now[0] += 61
    assert client.get('/v1/jobs/'+job2['id'], headers=h['writer']).json()['state'] == 'outcome_unknown'
    job3 = publish(client, h['writer'], card, 'third').json()
    assert client.post('/v1/phone/jobs/'+job3['id']+'/approve', headers=h['phone'], json={'hash': card['hash']}).status_code == 409


def test_concurrent_revision(api):
    store, client, h = api
    card = create(client, h['writer'])
    def update(n):
        try:
            store.save('test', card['document']['id'], 1, updates={'cpu_bar': {'value': n}})
            return True
        except Fault as error:
            assert error.code == 'revision_conflict'
            return False
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        assert sum(pool.map(update, range(8))) == 1


def test_app_api_bad_shapes_and_schema(api):
    _, client, h = api
    for document in [None, [], {}, {'permissions': [[]]}]:
        response = client.post('/v1/apps/validate', headers=h['writer'], json={'document': document})
        assert response.status_code == 422
    for value in [[], None, {}, 'not base64']:
        response = client.post('/v1/apps/package/validate', headers=h['writer'], json={'zipBase64': value})
        assert response.status_code == 422
    schema = client.get('/openapi.json', headers=h['reader']).json()
    assert schema['paths']['/v1/cards/{ident}']['put']['requestBody']['required']
    assert schema['paths']['/v1/cards/{ident}']['put']['security'] == [{'BearerAuth': []}]
    preview = client.post('/v1/cards/preview', headers=h['writer'], json={'document': TEMPLATES[0]})
    assert preview.status_code == 200 and 'sandbox' in preview.headers['content-security-policy']


@pytest.mark.parametrize('edit', [
    lambda d: d['components'][0].update(x=249),
    lambda d: d['components'][0].update(text='好'*33),
    lambda d: d['components'][0].update(font=19),
    lambda d: d['components'][1].update(id='title'),
    lambda d: d['components'][2].update(value=True),
    lambda d: d.update(url='https://example.invalid'),
])
def test_invalid_cards(edit):
    doc = copy.deepcopy(TEMPLATES[0]); edit(doc)
    with pytest.raises(Fault):
        validate(doc)
