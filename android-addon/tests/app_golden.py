"""Generate Android comparison fixtures using the existing public Python SDK."""
import json
import pathlib
import struct
import sys
import zipfile
import zlib

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'dashboard-service'))
from turbo_dashboard.app_wire import encode

out = root / 'android-addon/build/test/app-golden'
out.mkdir(parents=True, exist_ok=True)
for source in sorted((root / 'app-gallery').glob('Gallery_*.zip')):
    with zipfile.ZipFile(source) as archive:
        doc = json.loads(archive.read('app.json'))
    wire = encode(doc)
    (out / (source.stem + '.tap')).write_bytes(wire)
    identity, name = doc['id'].encode(), doc['name'].encode()
    packet = bytearray(b'TAX1' + bytes((2, 255, len(identity), len(name))))
    packet += struct.pack('<IIHHI', 42, 123, doc['version'], len(wire), 0)
    packet += identity + name + wire
    struct.pack_into('<I', packet, 20, zlib.crc32(packet))
    (out / (source.stem + '.tax')).write_bytes(packet)
print('20 TAP1/TAX1 golden packages generated with public SDK')
