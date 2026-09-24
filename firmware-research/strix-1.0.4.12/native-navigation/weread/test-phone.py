"""Synthetic original phone-module tests. No account, network or device access."""
import argparse
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CORE = HERE/'src/official-addon/research/weread-v1'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--trace', type=Path, help='New output path for synthetic ARM replay; never overwrite')
    a = p.parse_args()
    if a.trace and a.trace.exists():
        raise SystemExit('Trace exists; choose a fresh path')
    with tempfile.TemporaryDirectory(prefix='turbo-reader-public-test-') as tmp:
        tmp = Path(tmp)
        epub = tmp/'original.epub'
        with zipfile.ZipFile(epub, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('META-INF/container.xml', '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>')
            z.writestr('OPS/book.opf', '<package><manifest><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>')
            for letter, title in [('a', '第一章'), ('b', '第二章')]:
                z.writestr('OPS/'+letter+'.xhtml', '<html><head><title>ignored</title></head><body><p>'+title+' 原创测试正文</p></body></html>')
        sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        common = ['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-O1', '-g', '-Wno-deprecated-declarations',
                  '-fsanitize=address,undefined', '-framework', 'Foundation', '-I', str(Path(sdk)/'usr/include/libxml2'),
                  '-I', str(CORE), '-I', str(HERE/'phone'), '-I', str(ROOT/'official-addon')]
        trace = tmp/'synthetic-trace.json'
        for name, files, arguments in [
            ('overview', ['ReadingOverview.m', 'ReadingOverviewTest.m'], []),
            ('content', ['ReadingContent.m', 'ReadingContentTest.m'], [epub]),
            ('bridge', ['ReadingContent.m', 'ReaderBridge.m', 'ReaderBridgeTest.m'], [trace])]:
            exe = tmp/name
            subprocess.run(common+[str(HERE/'phone'/s) for s in files]+[str(CORE/'reader.c'), '-lz', '-lxml2', '-o', str(exe)], check=True)
            subprocess.run([str(exe), *map(str, arguments)], check=True)
        # Compile the actual transport separately; bridge unit tests mock only SDK I/O.
        subprocess.run(common+['-I', str(HERE.parent/'music/phone'), '-c', str(HERE/'phone/ReaderTransport.m'), '-o', str(tmp/'transport.o')], check=True)
        if a.trace:
            with a.trace.open('xb') as target:
                target.write(trace.read_bytes())
        print(json.dumps({'passed': True, 'tests': ['overview', 'TXT/EPUB', 'bridge', 'transport compilation'],
                          'syntheticOnly': True, 'deviceIO': False, 'networkIO': False}))


if __name__ == '__main__':
    main()
