import copy
import io
import json
import stat
import zipfile
import pytest
from turbo_dashboard.app_package import build_package, read_package, validate_app, Simulator
from turbo_dashboard.contracts import Fault, canonical


def example():
    return dict(schema=1, id='tasks', name='任务示例', version=1, entry='home', permissions=[], assets={}, pages=[
        dict(id='home', components=[dict(id='next', kind='button', x=8, y=8, w=500, h=28, font=24,
             text='查看详情', action=dict(type='page', target='detail'))]),
        dict(id='detail', components=[dict(id='exit', kind='button', x=8, y=8, w=500, h=28, font=24,
             text='退出', action=dict(type='exit', target='system'))])])


def test_reproducible_package():
    doc = example(); a = build_package(doc); b = build_package(doc)
    assert a == b
    checked = read_package(a)
    assert checked['document'] == doc
    assert not checked['budget']['runtimeAvailable']
    assert checked['unpackedBytes'] <= 20480


def test_four_slots_and_lifecycle():
    simulator = Simulator()
    for i in range(4):
        doc = example(); doc['id'] = 'app_'+str(i); simulator.install(build_package(doc))
    doc['id'] = 'fifth'
    with pytest.raises(Fault, match='four'):
        simulator.install(build_package(doc))
    for _ in range(1000):
        simulator.start('app_0'); assert simulator.page == 'home'
        simulator.event('touch')  # Touch alone is not a wheel step or press.
        assert simulator.page == 'home'
        simulator.event('short_press'); assert simulator.page == 'detail'
        simulator.event('long_press'); assert simulator.active is None
    simulator.start('app_1'); simulator.start('app_2')
    assert simulator.active == 'app_2'
    simulator.remove('app_2'); assert simulator.active is None


def test_failed_update_preserves_old():
    simulator = Simulator(); doc = example(); simulator.install(build_package(doc)); simulator.start('tasks')
    with pytest.raises(Fault):
        simulator.install(b'not zip')
    assert simulator.active == 'tasks' and simulator.slots['tasks']['version'] == 1
    with pytest.raises(Fault):
        simulator.install(build_package(doc))
    doc['version'] = 2; simulator.install(build_package(doc))
    assert simulator.active is None and simulator.slots['tasks']['version'] == 2


@pytest.mark.parametrize('edit', [
    lambda d: d.update(entry='missing'),
    lambda d: d.update(script='while(true){}'),
    lambda d: d.update(permissions=['filesystem']),
    lambda d: d['pages'][0]['components'][0].update(x=539),
    lambda d: d['pages'][0]['components'][0].update(action=dict(type='eval', target='code')),
    lambda d: d['pages'][0]['components'][0].update(action=dict(type='emit', target='network')),
    lambda d: d['pages'][0]['components'][0].update(font=True),
    lambda d: d['pages'][0]['components'][0].update(text='x'*97),
])
def test_reject_bad_apps(edit):
    doc = example(); edit(doc)
    with pytest.raises(Fault):
        build_package(doc)


@pytest.mark.parametrize('attack', ['traversal', 'duplicate', 'symlink', 'bomb', 'hash', 'extra'])
def test_zip_rejection(attack):
    original = zipfile.ZipFile(io.BytesIO(build_package(example())))
    files = [(n, original.read(n)) for n in original.namelist()]
    if attack == 'traversal': files[0] = ('../app.json', files[0][1])
    if attack == 'duplicate': files.append(files[0])
    if attack == 'extra': files.append(('evil.js', b'alert(1)'))
    if attack == 'bomb': files[0] = (files[0][0], b'x'*100000)
    if attack == 'hash':
        obj = json.loads(files[1][1]); obj['sha256'] = '0'*64; files[1] = (files[1][0], canonical(obj))
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for n, content in files:
            if attack == 'symlink' and n == 'app.json':
                info = zipfile.ZipInfo(n); info.external_attr = (stat.S_IFLNK | 0o777) << 16; z.writestr(info, content)
            else: z.writestr(n, content)
    with pytest.raises(Fault):
        read_package(buffer.getvalue())
