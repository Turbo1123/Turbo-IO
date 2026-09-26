import base64
import io
import json
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path
import pytest
from turbo_dashboard.app_package import build_package
from turbo_dashboard.app_examples import examples
from turbo_dashboard.app_wire import encode
from turbo_dashboard.app_transport import command
from turbo_dashboard.contracts import canonical
from test_app_package import example


@pytest.mark.skipif(sys.platform != 'darwin', reason='Foundation host codec check on macOS')
def test_actual_phone_codec_with_python_compiler(tmp_path):
    src = Path(__file__).resolve().parents[2]/'official-addon/research/app-runtime-v1'
    doc = example()
    doc['name'] = '开发者 / 应用'
    package = build_package(doc)
    (tmp_path/'valid.zip').write_bytes(package)
    (tmp_path/'wire.bin').write_bytes(encode(doc))
    rich = example()
    rich['permissions'] = ['backend.events']
    rich['assets'] = {'mark': dict(format='mono1-msb', width=16, height=8,
                                 pixels=base64.b64encode(bytes(range(16))).decode())}
    rich['pages'][0]['components'] += [
        dict(id='label', kind='text', x=8, y=40, w=300, h=24, text='香港 / 75%', font=18),
        dict(id='mark', kind='image', x=340, y=40, w=16, h=8, asset='mark'),
        dict(id='progress', kind='progress', x=8, y=72, w=300, h=10, value=75),
        dict(id='frame', kind='frame', x=332, y=32, w=32, h=24),
        dict(id='refresh', kind='button', x=8, y=110, w=300, h=30, text='刷新数据',
             font=20, action=dict(type='emit', target='refresh'))]
    (tmp_path/'rich.zip').write_bytes(build_package(rich))
    (tmp_path/'rich.bin').write_bytes(encode(rich))
    for stem, builtin in examples().items():
        (tmp_path/('builtin-'+stem+'.zip')).write_bytes(build_package(builtin))
        (tmp_path/('builtin-'+stem+'.bin')).write_bytes(encode(builtin))
    for i, op in enumerate(['query', 'install', 'launch', 'stop', 'remove'], 1):
        args = {} if i == 1 else dict(session=7392, document=doc) if i == 2 else dict(session=7392, app_id=doc['id'], version=doc['version'], slot=0)
        (tmp_path/f'command-{i}.bin').write_bytes(command(op, i, **args))
    with zipfile.ZipFile(io.BytesIO(package)) as z:
        files = {n: z.read(n) for n in z.namelist()}
    def write(label, entries, method=zipfile.ZIP_STORED):
        with zipfile.ZipFile(tmp_path/label, 'w', compression=method) as z:
            for n, data in entries:
                z.writestr(n, data)
    write('deflated.zip', files.items(), zipfile.ZIP_DEFLATED)
    write('invalid-path.zip', [('app.json', files['app.json']), ('../manifest.json', files['manifest.json'])])
    write('invalid-duplicate.zip', [('app.json', files['app.json'])]*2)
    write('invalid-hash.zip', [('app.json', files['app.json'].replace(b'"version":1', b'"version":2')), ('manifest.json', files['manifest.json'])])
    write('invalid-oversized.zip', [('app.json', b'A'*20481), ('manifest.json', files['manifest.json'])], zipfile.ZIP_DEFLATED)
    write('invalid-noncanonical.zip', [('app.json', b' '+files['app.json']), ('manifest.json', files['manifest.json'])])
    (tmp_path/'invalid-trailing.zip').write_bytes(package+b'x')
    record = bytearray(88)
    ident, title = doc['id'].encode(), doc['name'].encode()
    struct.pack_into('<BBBBHHII', record, 0, 1, len(ident), len(title), 0, doc['version'], len(encode(doc)), 1, 0)
    record[16:16+len(ident)] = ident
    record[40:40+len(title)] = title
    reply = struct.pack('<4sBBBBIIII', b'TAR1', 0, 0, 0, 255, 2, 7392, 2, 376)+record+bytes(88*3)
    (tmp_path/'reply.bin').write_bytes(reply)
    data = canonical(dict(cmd='turbo_app_v1', payload=dict(data=reply.hex())))
    n = len(data)
    envelope = bytes([8, 1, 16, 6, 26, (n & 127)|128, n >> 7])+data
    (tmp_path/'envelope.bin').write_bytes(envelope)
    exe = tmp_path/'phone-codec'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fsanitize=address,undefined', '-g', '-Wno-incompatible-pointer-types', '-Wno-deprecated-declarations', '-framework', 'Foundation', '-lz', str(src/'AppPackage.m'), str(src/'AppPackageTests.m'), str(src/'app.c'), '-o', str(exe)], check=True)
    subprocess.run([str(exe), str(tmp_path)], check=True)
