"""Read-only verification of the exact TWR1 release. No flash or device access."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = json.loads((HERE / 'release-manifest.json').read_text())


def verify(archive, rebuilt=False):
    archive = Path(archive)
    if archive.stat().st_size > 12 * 1024 * 1024:
        raise ValueError('Archive exceeds bound')
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    if not rebuilt and (sha != RELEASE['archiveSHA256'] or archive.stat().st_size != RELEASE['archiveBytes']):
        raise ValueError('Not the exact released ZIP; stop, do not change hash pins')
    baseline = json.loads((HERE.parent.parent / 'metadata/baseline.json').read_text())
    pins = {r['name']: r for r in baseline['files']}
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        if len(infos) != 15 or set(z.namelist()) != set(pins) | {'OtaFileInfo.json'}:
            raise ValueError('Duplicate, missing or unexpected ZIP member')
        if any(i.flag_bits & 1 or i.file_size > 16*1024*1024 for i in infos) or sum(i.file_size for i in infos) > 40*1024*1024:
            raise ValueError('Encrypted or oversized ZIP member')
        data = {i.filename: z.read(i) for i in infos}
    if hashlib.sha256(data['OtaFileInfo.json']).hexdigest() != RELEASE['manifestSHA256']:
        raise ValueError('Manifest bytes differ, including burn metadata')
    rows = json.loads(data['OtaFileInfo.json'])
    if len(rows) != 14 or {r['Name'] for r in rows} != set(pins):
        raise ValueError('Unexpected manifest records')
    for row in rows:
        name = row['Name']
        blob = data[name]
        expected = RELEASE['apSHA256'] if name == 'nuttx_ap.bin' else pins[name]['sha256']
        if hashlib.sha256(blob).hexdigest() != expected:
            raise ValueError('Payload differs: ' + name)
        if row['Size'] != len(blob) or row['Md5'] != hashlib.md5(blob).hexdigest():
            raise ValueError('Size/MD5 differs: ' + name)
    if len(data['nuttx_ap.bin']) != RELEASE['apBytes']:
        raise ValueError('AP length differs')
    return {'archiveSHA256': sha, 'exactReleasedZIP': sha == RELEASE['archiveSHA256'],
            'apSHA256': RELEASE['apSHA256'], 'unchangedStockPayloads': 13,
            'membersVerified': 15, 'deviceIO': False, 'flashAuthorized': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive', type=Path)
    p.add_argument('--rebuilt', action='store_true', help='Require identical members; permit different ZIP timestamps. Not a phone authorization.')
    a = p.parse_args()
    print(json.dumps(verify(a.archive, a.rebuilt), indent=2))
