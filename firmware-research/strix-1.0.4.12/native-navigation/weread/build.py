"""Rebuild TWR1 from the public baseline plus original overlay. Never flashes."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent


def run(argv, env):
    subprocess.run([str(x) for x in argv], check=True, env=env)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stock', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True, help='Fresh directory; never overwritten')
    p.add_argument('--llvm', type=Path, required=True, help='OHOS LLVM 15.0.4 bin')
    a = p.parse_args()
    out, llvm = a.out.resolve(), a.llvm.resolve()
    if out.exists():
        raise SystemExit('Output exists; use a fresh path. Nothing removed.')
    version = subprocess.check_output([llvm/'clang', '--version'], text=True)
    if 'OHOS (dev) clang version 15.0.4 (llvm-project 39bec79f56c3b5a629e4bacac1dc022e1da552d0)' not in version:
        raise SystemExit('Compiler differs from the tested release')
    env = dict(os.environ, PATH=str(llvm)+os.pathsep+os.environ.get('PATH', ''))
    for tool in ('clang', 'ld.lld', 'llvm-nm', 'llvm-objcopy', 'node'):
        if not shutil.which(tool, path=env['PATH']):
            raise SystemExit('Missing tool: '+tool)
    shutil.copytree(PARENT/'src', out)
    shutil.copytree(HERE/'src', out, dirs_exist_ok=True)
    baseline = out/'firmware-inspection/StrixOS-1.0.4.12'
    run([sys.executable, PARENT.parent/'src/prepare-baseline.py', a.stock.resolve(), '--output', baseline], env)
    symbols = json.loads((PARENT/'symbols.json').read_text())
    symbols['entries'].extend(json.loads((HERE/'symbols-extra.json').read_text()))
    (baseline/'symbols.json').write_text(json.dumps(symbols))
    png = out/'official-addon/build/turbo-photo-png-10412-20260921/turbo-photo-gray16-rgba-88x98.png'
    png.parent.mkdir(parents=True)
    shutil.copyfile(PARENT.parent/'assets/turbo-photo-firmware.png', png)
    src = out/'official-addon/research'
    candidate = out/'candidate'
    run([sys.executable, src/'music-runtime-v1/build_candidate.py', '--out', candidate], env)
    for script in ('weread-v1/test_menu11_arm.py', 'weread-v1/test_reader_arm.py',
                   'weread-v1/test_open_lifecycle_arm.py', 'music-runtime-v1/test_music_arm.py',
                   'navigation-runtime-v1/test_service_arm.py', 'diagnostics-v1/test_service_arm.py'):
        run([sys.executable, src/script, candidate], env)
    run([sys.executable, src/'display-runtime-v1/test_linked_arm.py', candidate, '--candidate'], env)
    run([sys.executable, src/'weread-v1/audit_candidate.py', candidate, '--out', candidate/'independent-audit.json'], env)
    for name, sources in [('reader', ['reader.c', 'reader_test.c']),
                          ('reader-input', ['reader_input_test.c']),
                          ('reader-view', ['reader.c', 'reader_view.c', 'reader_view_test.c'])]:
        exe = out/name
        run(['xcrun', 'clang', '-std=c11', '-O1', '-g', '-fsanitize=address,undefined',
             *[src/'weread-v1'/s for s in sources], '-o', exe], env)
        run([exe], env)
    report = json.loads((candidate/'report.json').read_text())
    expected = json.loads((HERE/'release-manifest.json').read_text())['apSHA256']
    if hashlib.sha256((candidate/'payload/nuttx_ap.bin').read_bytes()).hexdigest() != expected:
        raise SystemExit('Rebuilt AP differs; do not flash')
    run([sys.executable, HERE/'verify.py', candidate/report['archive']['name'], '--rebuilt'], env)
    print('Offline rebuild and tests passed; AP matches release. No device operation or flash authorization.')


if __name__ == '__main__':
    main()
