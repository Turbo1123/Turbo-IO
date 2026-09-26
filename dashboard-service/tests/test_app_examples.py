import io
import zipfile
import subprocess
import shutil
from pathlib import Path
from turbo_dashboard.app_examples import examples, export
from turbo_dashboard.app_package import build_package, read_package, validate_app
from turbo_dashboard.app_wire import encode


def test_all_builtins_fit_existing_runtime(tmp_path):
    docs=examples();assert len(docs)==4
    assert len({d['id'] for d in docs.values()})==4
    report=export(tmp_path)
    for stem,doc in docs.items():
        assert doc['permissions']==[]
        assert validate_app(doc)['valid']
        blob=(tmp_path/(stem+'.zip')).read_bytes()
        assert blob==build_package(doc)==build_package(examples()[stem])
        read_package(blob)
        assert report[stem]['wireBytes']==len(encode(doc))<=20480
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            assert sum(i.file_size for i in z.infolist())<=20480
        reachable={doc['entry']}
        for _ in range(4):
            for page in doc['pages']:
                if page['id'] in reachable:
                    reachable.update(c['action']['target'] for c in page['components'] if c['kind']=='button' and c['action']['type']=='page')
        assert reachable=={p['id'] for p in doc['pages']}
        for page in doc['pages']:
            assert any(c['kind']=='button' for c in page['components'])
            assert all(c['action']['type'] in ('page','exit') for c in page['components'] if c['kind']=='button')


def test_complex_examples_have_images_and_disclaimers():
    docs=examples()
    for key in ('TurboAppSDKWeather','TurboAppSDKMusic','TurboAppSDKDevice'):
        doc=docs[key];assert doc['assets'] and ('示例' in doc['name'] or key=='TurboAppSDKMusic')
        assert any(c['kind']=='image' for p in doc['pages'] for c in p['components'])
    assert len(docs['TurboAppSDKMusic']['pages'])==4
    assert len(docs['TurboAppSDKWeather']['pages'])==3


def test_examples_native_views_under_sanitizers(tmp_path):
    src=Path(__file__).resolve().parents[2]/'official-addon/research/app-runtime-v1'
    exe=tmp_path/'views'
    cc=['clang']
    if shutil.which('xcrun'):
        sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        cc=['xcrun','--sdk','macosx','clang','-isysroot',sdk]
    subprocess.run(cc+['-std=c11','-O1','-g','-fsanitize=address,undefined',
                    str(src/'app.c'),str(src/'app_view.c'),str(src/'test_view.c'),'-o',str(exe)],check=True)
    for stem,doc in examples().items():
        wire=tmp_path/(stem+'.tap');wire.write_bytes(encode(doc))
        subprocess.run([str(exe),str(wire)],check=True,capture_output=True,timeout=60)
