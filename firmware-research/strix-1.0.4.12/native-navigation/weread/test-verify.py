"""Negative tests for release verification; only temporary archives are mutated."""
import argparse
import importlib.util
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('twr_verify', HERE/'verify.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('archive', type=Path)
a = p.parse_args()
gate.verify(a.archive)
with zipfile.ZipFile(a.archive) as z:
    members = {i.filename: z.read(i) for i in z.infolist()}
with tempfile.TemporaryDirectory(prefix='twr-verify-negative-') as tmp:
    for name, mode in [('nuttx_ap.bin', 'AP'), ('nuttx_bth.bin', 'non-AP'), ('OtaFileInfo.json', 'manifest'), ('../extra', 'unexpected-path')]:
        data = dict(members)
        if name in data:
            b = bytearray(data[name]); b[-1] ^= 1; data[name] = bytes(b)
        else:
            data[name] = b'not extracted'
        out = Path(tmp)/(mode+'.zip')
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
            for key, value in data.items():
                z.writestr(key, value)
        try:
            gate.verify(out, rebuilt=True)
        except ValueError:
            print('PASS rejected '+mode)
        else:
            raise AssertionError('Gate accepted modified '+mode)
print('PASS exact release and four negative cases; no device operations')
