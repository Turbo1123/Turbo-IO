"""Generate the iOS OTA candidate descriptor from a built TAP1 candidate folder.

Reads <candidate>/report.json + <candidate>/payload/* and writes a schema-1
descriptor (same shape as focus-edition/candidates/tfp1-focus-04.json) whose
pins/hashes come from the actual build output, then self-validates it with
watch-remote/flash_check.py. The dylib embeds exactly these bytes via
gen_otacandidate.py (TIO_OTA_CANDIDATE), so the phone gate accepts only this
exact ZIP.

Usage: python make-ota-candidate.py <candidate-folder> <out.json> [--code NAME]
"""
import argparse, hashlib, json, sys
from pathlib import Path

STOCK_AP_SHA = '53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988'

def sha256(b): return hashlib.sha256(b).hexdigest()

def main():
    p = argparse.ArgumentParser()
    p.add_argument('candidate', type=Path)
    p.add_argument('out', type=Path)
    p.add_argument('--code', default='TAP1-2026-10')
    a = p.parse_args()
    root = a.candidate
    report = json.loads((root / 'report.json').read_text(encoding='utf-8'))
    if report['kind'] != 'TAP1-developer-runtime-experimental-candidate':
        raise SystemExit('not a TAP1 candidate: ' + report['kind'])
    payload = root / 'payload'
    pins = []
    for f in sorted(payload.iterdir()):
        if not f.is_file():
            continue
        pins.append({'name': f.name, 'size': f.stat().st_size, 'sha256': sha256(f.read_bytes())})
    names = [x['name'] for x in pins]
    if len(pins) != 15 or len(set(names)) != 15 or 'nuttx_ap.bin' not in names or 'OtaFileInfo.json' not in names:
        raise SystemExit('unexpected payload set: %d files' % len(pins))
    manifest_rows = json.loads((payload / 'OtaFileInfo.json').read_text(encoding='utf-8'))
    ap_md5 = next(r['Md5'] for r in manifest_rows if r['Name'] == 'nuttx_ap.bin')
    desc = {
        'schema': 1,
        'codeName': a.code,
        'displayName': 'TAP1 十二项菜单 + 导航路况扩展 + 智记共存 · 2026-10',
        'confirmToken': a.code,
        'baseVersion': 'Strix OS 1.0.4.12',
        'zip': {'size': report['archive']['bytes'], 'sha256': report['archive']['sha256']},
        'otaSize': report['archive']['bytes'],
        'ap': {'name': 'nuttx_ap.bin', 'size': report['candidateAPBytes'],
               'sha256': report['candidateAP'], 'md5': ap_md5},
        'apBudgetBytes': 9600000,
        'manifest': next(x for x in pins if x['name'] == 'OtaFileInfo.json'),
        'stockAPSHA256': STOCK_AP_SHA,
        'payloadPins': pins,
    }
    if desc['stockAPSHA256'] != report['originalAP']:
        raise SystemExit('stock AP mismatch vs report')
    a.out.write_text(json.dumps(desc, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    repo = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(repo / 'watch-remote'))
    import flash_check
    flash_check.load_candidate(str(a.out))
    print(json.dumps({'out': str(a.out), 'codeName': desc['codeName'], 'zipSHA256': desc['zip']['sha256'],
                      'zipBytes': desc['zip']['size'], 'apBytes': desc['ap']['size'], 'pins': len(pins)}))

if __name__ == '__main__':
    main()
