"""flash_check preflight: synthetic candidates, positive and tamper negative cases."""
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('flash_check', Path(__file__).resolve().parents[1] / 'flash_check.py')
flash_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flash_check)

MEMBERS = {
    'a.bin': b'\x01' * 100,          # AP
    'b.bin': b'\x02' * 50,
    'c.bin': b'\x03' * 30,
}
ORDER = ['OtaFileInfo.json', 'a.bin', 'b.bin', 'c.bin']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def manifest_bytes(ap_size=None, ap_md5=None):
    rows = []
    for name in ORDER[1:]:
        data = MEMBERS[name]
        rows.append({'Name': name, 'Size': len(data), 'Md5': hashlib.md5(data).hexdigest(),
                     'BurnMode': 2, 'BurnAddr': 4096, 'BurnPath': '/dev/mtd1'})
    if ap_size is not None:
        rows[0]['Size'] = ap_size
        rows[0]['Md5'] = ap_md5
    return json.dumps(rows, separators=(',', ':')).encode()


def build_zip(root, name='candidate.zip', manifest=None, members=None):
    members = dict(MEMBERS if members is None else members)
    members['OtaFileInfo.json'] = manifest_bytes() if manifest is None else manifest
    path = root / name
    if path.exists():
        path.unlink()
    with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_DEFLATED) as z:
        for key in ORDER:
            z.writestr(key, members[key])
    return path


def write_stock(root, ap_data=None, manifest=None):
    stock = root / 'stock'
    stock.mkdir(exist_ok=True)
    for name in ORDER[1:]:
        (stock / name).write_bytes(MEMBERS[name] if ap_data is None or name != 'a.bin' else ap_data)
    (stock / 'OtaFileInfo.json').write_bytes(manifest_bytes() if manifest is None else manifest)
    return stock


def candidate(tmp, **overrides):
    pins = [{'name': n, 'size': len(MEMBERS[n]), 'sha256': sha(MEMBERS[n])} for n in ORDER[1:]]
    manifest = manifest_bytes()
    pins.insert(0, {'name': 'OtaFileInfo.json', 'size': len(manifest), 'sha256': sha(manifest)})
    raw = (tmp / 'candidate.zip').read_bytes()
    doc = {
        'schema': 1,
        'codeName': 'SYNTH-01',
        'displayName': 'Synthetic',
        'confirmToken': 'SYNTH',
        'baseVersion': 'Strix OS 1.0.4.12',
        'zip': {'size': len(raw), 'sha256': sha(raw)},
        'otaSize': len(raw),
        'ap': {'name': 'a.bin', 'size': len(MEMBERS['a.bin']), 'sha256': sha(MEMBERS['a.bin'])},
        'apBudgetBytes': 1000000,
        'manifest': {'name': 'OtaFileInfo.json', 'size': len(manifest), 'sha256': sha(manifest)},
        'stockAPSHA256': sha(MEMBERS['a.bin']),
        'payloadPins': pins,
    }
    doc.update(overrides)
    path = tmp / 'candidate.json'
    path.write_text(json.dumps(doc))
    return path


def load(root, path):
    return flash_check.load_candidate(path)


class FlashCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='flash-check-'))
        self.addCleanup(lambda: __import__('shutil').rmtree(self.tmp, ignore_errors=True))
        self.zip_path = build_zip(self.tmp)
        self.desc = candidate(self.tmp)

    def run_check(self, stock=None):
        return flash_check.check(self.zip_path, load(self.tmp, self.desc), stock)

    def names(self, report):
        return {c['name']: c['ok'] for c in report['checks']}

    def test_pass_without_stock(self):
        report = self.run_check()
        self.assertTrue(report['go'], report['checks'])
        self.assertTrue(all(self.names(report).values()))

    def test_pass_with_stock(self):
        stock = write_stock(self.tmp)
        report = self.run_check(stock)
        self.assertTrue(report['go'], report['checks'])

    def test_zip_tampered(self):
        data = bytearray(self.zip_path.read_bytes())
        data[-1] ^= 1
        (self.tmp / 'candidate.zip').write_bytes(bytes(data))
        report = self.run_check()
        self.assertFalse(report['go'])
        self.assertFalse(self.names(report)['zip-sha256'])

    def test_member_tampered(self):
        members = dict(MEMBERS)
        members['b.bin'] = b'\x09' * 50
        build_zip(self.tmp, members=members)
        self.desc = candidate(self.tmp)  # 外层 pin 对准篡改后的包，内层 pins 必须抓住
        report = self.run_check()
        self.assertFalse(self.names(report)['member-pins'])

    def test_extra_member(self):
        members = dict(MEMBERS)
        members['evil.bin'] = b'x'
        with zipfile.ZipFile(self.tmp / 'candidate.zip', 'a') as z:
            pass
        (self.tmp / 'candidate.zip').unlink()
        build_zip(self.tmp, members=members)
        with zipfile.ZipFile(self.tmp / 'candidate.zip', 'a') as z:
            z.writestr('evil.bin', b'x')
        self.desc = candidate(self.tmp)
        report = self.run_check()
        self.assertFalse(self.names(report)['member-set'])

    def test_manifest_md5_wrong(self):
        bad = json.loads(manifest_bytes())
        bad[1]['Md5'] = '0' * 32
        build_zip(self.tmp, manifest=json.dumps(bad, separators=(',', ':')).encode())
        self.desc = candidate(self.tmp)
        report = self.run_check()
        self.assertFalse(self.names(report)['manifest-json'])

    def test_ap_over_budget(self):
        self.desc = candidate(self.tmp, apBudgetBytes=len(MEMBERS['a.bin']))
        report = self.run_check()
        self.assertFalse(self.names(report)['ap-budget'])

    def test_stock_non_ap_changed(self):
        stock = write_stock(self.tmp)
        (stock / 'b.bin').write_bytes(b'\x07' * 50)
        report = self.run_check(stock)
        self.assertFalse(self.names(report)['stock-unchanged'])

    def test_stock_manifest_burn_changed(self):
        bad = json.loads(manifest_bytes())
        bad[0]['BurnAddr'] = 8192
        stock = write_stock(self.tmp, manifest=json.dumps(bad, separators=(',', ':')).encode())
        report = self.run_check(stock)
        self.assertFalse(self.names(report)['stock-manifest'])

    def test_stock_ap_baseline_mismatch(self):
        stock = write_stock(self.tmp, ap_data=b'\x05' * 100)
        report = self.run_check(stock)
        self.assertFalse(self.names(report)['stock-ap'])

    def test_load_candidate_rejects_garbage(self):
        bad = self.tmp / 'bad.json'
        bad.write_text('{"schema": 2}')
        with self.assertRaises(flash_check.CandidateError):
            flash_check.load_candidate(bad)
        doc = json.loads(self.desc.read_text())
        doc['payloadPins'].append(dict(doc['payloadPins'][0]))
        bad.write_text(json.dumps(doc))
        with self.assertRaises(flash_check.CandidateError):
            flash_check.load_candidate(bad)
        doc = json.loads(self.desc.read_text())
        doc['zip']['sha256'] = 'zz'
        bad.write_text(json.dumps(doc))
        with self.assertRaises(flash_check.CandidateError):
            flash_check.load_candidate(bad)

    def test_cli_exit_codes(self):
        stock = write_stock(self.tmp)
        self.assertEqual(flash_check.main(['--zip', str(self.zip_path), '--candidate', str(self.desc), '--stock', str(stock), '--json']), 0)
        (self.tmp / 'candidate.zip').unlink()
        build_zip(self.tmp, members={**MEMBERS, 'b.bin': b'\x09' * 50})
        self.assertEqual(flash_check.main(['--zip', str(self.zip_path), '--candidate', str(self.desc)]), 1)
        self.assertEqual(flash_check.main(['--zip', str(self.zip_path), '--candidate', str(self.tmp / 'missing.json')]), 2)


if __name__ == '__main__':
    unittest.main()
