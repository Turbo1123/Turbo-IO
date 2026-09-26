import os
import shutil
import subprocess
from pathlib import Path
from turbo_dashboard.app_wire import encode
from test_app_package import example


def test_native_decoder_under_sanitizers(tmp_path):
    root = Path(__file__).resolve().parents[2]
    src = root/'official-addon/research/app-runtime-v1'
    wire = tmp_path/'fixture.tap'; wire.write_bytes(encode(example()))
    binary = tmp_path/'native-test'
    if shutil.which('xcrun'):
        sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        cc = ['xcrun', '--sdk', 'macosx', 'clang', '-isysroot', sdk]
    else:
        cc = ['clang']
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                       str(src/'app.c'), str(src/'test_app.c'), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary), str(wire)], check=True, text=True, capture_output=True, timeout=60)
    assert '100000 mutations' in result.stdout
    view = tmp_path/'native-view-test'
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-fsanitize=address,undefined',
                       str(src/'app.c'), str(src/'app_view.c'), str(src/'test_view.c'), '-o', str(view)], check=True)
    result = subprocess.run([str(view), str(wire)], check=True, text=True, capture_output=True, timeout=60)
    assert '10000 ownership cycles' in result.stdout
    import base64
    full = example()
    full['assets']['logo'] = dict(format='mono1-msb', width=32, height=32, pixels=base64.b64encode(bytes([255])*128).decode())
    full['pages'][0]['components'] += [
        dict(id='picture', kind='image', x=8, y=50, w=32, h=32, asset='logo'),
        dict(id='progress', kind='progress', x=60, y=50, w=200, h=8, value=63),
        dict(id='box', kind='frame', x=60, y=70, w=200, h=40)]
    wire.write_bytes(encode(full))
    subprocess.run([str(view), str(wire)], check=True, capture_output=True, timeout=60)
    store = tmp_path/'native-store-test'
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                       str(src/'app.c'), str(src/'app_store.c'), str(src/'test_store.c'), '-o', str(store)], check=True)
    result = subprocess.run([str(store), str(wire)], check=True, capture_output=True, text=True, timeout=60)
    assert 'every truncated write' in result.stdout
    runner = tmp_path/'native-runner-test'
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                       *[str(src/n) for n in ['app.c', 'app_store.c', 'app_view.c', 'app_runner.c', 'app_command.c', 'app_shelf.c', 'test_runner.c']], '-o', str(runner)], check=True)
    result = subprocess.run([str(runner), str(wire)], check=True, capture_output=True, text=True, timeout=60)
    assert '1000 lifecycles' in result.stdout
    import struct
    from turbo_dashboard.app_transport import command, reply
    commands = [command('query', 1), command('install', 2, session=7392, document=full)]
    commands += [command(op, i, session=7392, slot=0, app_id=full['id'], version=full['version'])
                 for i, op in enumerate(['launch', 'stop', 'remove'], 3)]
    requests = tmp_path/'commands.bin'
    replies = tmp_path/'replies.bin'
    requests.write_bytes(b''.join(struct.pack('<I', len(c))+c for c in commands))
    result = subprocess.run([str(runner), str(wire), str(requests), str(replies)], check=True,
                            capture_output=True, text=True, timeout=60)
    assert 'consent gates passed' in result.stdout
    received = [reply(replies.read_bytes()[i*376:(i+1)*376]) for i in range(5)]
    assert all(r['result'] == 0 and r['session'] == 7392 for r in received)
    assert received[0]['slots'] == [None]*4
    assert received[1]['slots'][0]['id'] == full['id']
    assert received[2]['activeSlot'] == 0
    assert received[3]['activeSlot'] is None
    assert received[4]['slots'][0]['tombstone']
    files = tmp_path/'native-files-test'
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                       *[str(src/n) for n in ['app.c', 'app_store.c', 'app_files.c', 'app_files_native.c', 'test_files.c']], '-o', str(files)], check=True)
    result = subprocess.run([str(files), str(wire)], check=True, capture_output=True, text=True, timeout=60)
    assert 'persistent banks passed' in result.stdout
    lvgl = tmp_path/'native-lvgl-test'
    subprocess.run(cc+['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                       *[str(src/n) for n in ['app.c', 'app_view.c', 'app_lvgl.c', 'test_lvgl.c']], '-o', str(lvgl)], check=True)
    result = subprocess.run([str(lvgl), str(wire)], check=True, capture_output=True, text=True, timeout=60)
    assert 'parent deletion passed' in result.stdout


def test_js_authoring_to_zip(tmp_path):
    from turbo_dashboard.app_package import build_package, read_package
    import json
    root = Path(__file__).resolve().parents[1]
    source = tmp_path/'tasks.json'
    subprocess.run(['node', str(root/'examples/tasks.mjs'), '--out', str(source)], check=True)
    document = json.loads(source.read_text())
    compiled = encode(document)
    checked = read_package(build_package(document))
    assert checked['budget']['components'] == 6
    assert compiled[:4] == b'TAP1'
    assert len(compiled) < 1024
