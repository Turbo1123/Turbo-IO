import base64
import copy
import hashlib
import json
import subprocess
import shutil
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from turbo_dashboard.gallery import catalog, export, snapshot_doc
from turbo_dashboard.app_package import build_package, read_package
from turbo_dashboard.app_wire import encode
from turbo_dashboard.contracts import Fault
from turbo_dashboard.server import create_app
from turbo_dashboard.store import Store

def test_twenty_deterministic_bounded_templates(tmp_path):
    items=export(tmp_path/'gallery');assert len(items)==len({i['id'] for i in items})==20
    assert len({snapshot_doc(i['id'])['assets']['icon']['pixels'] for i in items})==20
    for item in items:
        blob=(tmp_path/'gallery'/(item['resource']+'.zip')).read_bytes()
        assert hashlib.sha256(blob).hexdigest()==item['sha256']
        doc=read_package(blob)['document'];assert doc['permissions']==[]
        assert build_package(doc)==blob and len(encode(doc))<=20480
        assert len(doc['pages'])==2 and '示例' in doc['name']
        assert any('非实时' in c.get('text','') for p in doc['pages'] for c in p['components'])
        assert all(any(c.get('action',{}).get('type')=='exit' for c in p['components']) for p in doc['pages'])

def test_snapshot_whitelist_and_no_overwrite(tmp_path):
    snap=dict(headline='北京天气',lines=['晴 26°C','湿度 40%'],observedAt='2026-09-26T13:00:00+08:00')
    doc=snapshot_doc('city_weather',snap,2);assert doc['version']==2 and '示例' not in doc['name']
    for change in [{'token':'do-not-leak'},{'lines':['x'*81]},{'observedAt':'2026-09-26'},{'lines':[]},{'headline':'bad\ntext'}]:
        with pytest.raises(Fault):snapshot_doc('city_weather',dict(snap,**change))
    for ident in ['../x','missing']:
        with pytest.raises(Fault):snapshot_doc(ident)
    target=tmp_path/'app.zip'
    cmd=['turbo-app','gallery','build','city_weather','--out',str(target)]
    subprocess.run(cmd,check=True,capture_output=True);before=target.read_bytes()
    assert subprocess.run(cmd,capture_output=True).returncode!=0 and target.read_bytes()==before

def test_real_http_package_build_and_auth(tmp_path):
    store=Store(tmp_path/'db');client=TestClient(create_app(store))
    h={r:{'Authorization':'Bearer '+store.issue(r,'demo')} for r in ['reader','writer','phone']}
    assert client.get('/v1/apps/gallery').status_code==401
    assert len(client.get('/v1/apps/gallery',headers=h['reader']).json()['entries'])==20
    doc=snapshot_doc('holiday');expected=build_package(doc)
    for r in ['reader','phone']:
        assert client.post('/v1/apps/package',headers=h[r],json={'document':doc}).status_code==403
    result=client.post('/v1/apps/package',headers=h['writer'],json={'document':doc}).json()
    assert base64.b64decode(result['zipBase64'])==expected and result['installed'] is False
    assert result['sha256']==hashlib.sha256(expected).hexdigest()
    snap=dict(headline='授权后端快照',lines=['来源：自己的 Server'],observedAt='2026-09-26T00:00:00Z')
    result=client.post('/v1/apps/gallery/holiday/package',headers=h['writer'],json={'snapshot':snap,'version':2})
    assert result.status_code==200
    doc=read_package(base64.b64decode(result.json()['zipBase64']))['document'];assert doc['version']==2
    assert client.post('/v1/apps/gallery/holiday/package',headers=h['writer'],json={'snapshot':dict(snap,key='secret'),'version':2}).status_code==422
    assert client.post('/v1/apps/package',headers=h['writer'],content=b'x'*32769).status_code==413

def test_all_gallery_pages_native_sanitizers(tmp_path):
    src=Path(__file__).resolve().parents[2]/'official-addon/research/app-runtime-v1';exe=tmp_path/'views'
    cc=['clang']
    if shutil.which('xcrun'):
        sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        cc=['xcrun','clang','-isysroot',sdk]
    subprocess.run(cc+['-std=c11','-O1','-g','-fsanitize=address,undefined',str(src/'app.c'),str(src/'app_view.c'),str(src/'test_view.c'),'-o',str(exe)],check=True)
    for item in catalog():
        f=tmp_path/(item['id']+'.tap');f.write_bytes(encode(snapshot_doc(item['id'])))
        subprocess.run([str(exe),str(f)],check=True,capture_output=True,timeout=60)
