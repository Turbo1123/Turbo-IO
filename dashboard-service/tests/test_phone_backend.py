"""Compile canonical Objective-C gates against the real API snapshot contract."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import time

import pytest
from turbo_dashboard.contracts import TEMPLATES, digest


@pytest.mark.skipif(not shutil.which('xcrun'), reason='macOS Foundation required')
def test_native_phone_backend(tmp_path):
    source = Path(__file__).resolve().parents[2]/'official-addon/research/dashboard-editor-v1'
    docs = copy.deepcopy(TEMPLATES)
    unusual = copy.deepcopy(docs[0])
    unusual['name'] = '中文/é😀 · 数据'
    unusual['components'][0]['text'] = 'x/y "引号" \\ é😀'
    docs.append(unusual)
    fixture = {'cards': [{'document': d, 'hash': digest(d)} for d in docs],
               'job': dict(id='a'*32, hash=digest(docs[0]), device='fixture',
                           state='awaiting_phone_approval', revision=1,
                           expires=time.time()+600, card=docs[0]['id'], document=docs[0])}
    path = tmp_path/'fixture.json'
    path.write_text(json.dumps(fixture, ensure_ascii=False))
    binary = tmp_path/'backend-tests'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-Wno-incompatible-pointer-types',
                    '-framework', 'Foundation', '-framework', 'Security',
                    str(source/'BackendTests.m'), str(source/'EditorBackend.m'),
                    str(source/'EditorModel.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(path)], check=True, timeout=30)
