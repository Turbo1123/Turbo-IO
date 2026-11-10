"""One-command offline preflight for a pinned OTA candidate. Never contacts a device.

    python3 watch-remote/flash_check.py --zip CANDIDATE.zip \
        --candidate watch-remote/candidates/tgr1-global-01.json \
        [--stock firmware-research/strix-1.0.4.12/stock]

Exits 0 only when every check passes. The candidate descriptor is the single
source of truth shared with the phone gates; this script proves a ZIP matches
it before anyone reaches for a phone.
"""
import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

HEX64 = __import__('re').compile(r'^[0-9a-f]{64}$')


def _sha(data):
    return hashlib.sha256(data).hexdigest()


class CandidateError(ValueError):
    pass


def load_candidate(path):
    """Parse and structurally validate a candidate descriptor. Fail-closed."""
    try:
        c = json.loads(Path(path).read_text(encoding='utf-8'))
    except Exception as e:
        raise CandidateError('描述文件不可读: %s' % e)
    if not isinstance(c, dict) or c.get('schema') != 1:
        raise CandidateError('描述文件 schema 缺失或不支持')
    for key in ('codeName', 'confirmToken', 'baseVersion'):
        if not isinstance(c.get(key), str) or not c[key]:
            raise CandidateError('描述文件缺少 %s' % key)
    z = c.get('zip')
    if not isinstance(z, dict) or not isinstance(z.get('size'), int) or z['size'] <= 0 \
            or not HEX64.match(str(z.get('sha256', ''))):
        raise CandidateError('描述文件 zip.size/zip.sha256 无效')
    if not isinstance(c.get('otaSize'), int) or c['otaSize'] <= 0:
        raise CandidateError('描述文件 otaSize 无效')
    ap = c.get('ap')
    if not isinstance(ap, dict) or not isinstance(ap.get('size'), int) or ap['size'] <= 0 \
            or not HEX64.match(str(ap.get('sha256', ''))):
        raise CandidateError('描述文件 ap.size/ap.sha256 无效')
    if not isinstance(c.get('apBudgetBytes'), int) or c['apBudgetBytes'] <= 0:
        raise CandidateError('描述文件 apBudgetBytes 无效')
    m = c.get('manifest')
    if not isinstance(m, dict) or not isinstance(m.get('size'), int) or m['size'] <= 0 \
            or not HEX64.match(str(m.get('sha256', ''))):
        raise CandidateError('描述文件 manifest.size/manifest.sha256 无效')
    if not HEX64.match(str(c.get('stockAPSHA256', ''))):
        raise CandidateError('描述文件 stockAPSHA256 无效')
    pins = c.get('payloadPins')
    if not isinstance(pins, list) or len(pins) < 3:
        raise CandidateError('描述文件 payloadPins 无效')
    names = set()
    for pin in pins:
        if not isinstance(pin, dict) or not isinstance(pin.get('name'), str) or not pin['name'] \
                or Path(pin['name']).name != pin['name'] or '/' in pin['name'] or '\\' in pin['name'] \
                or not isinstance(pin.get('size'), int) or pin['size'] <= 0 \
                or not HEX64.match(str(pin.get('sha256', ''))):
            raise CandidateError('描述文件存在无效 pin: %r' % (pin,))
        if pin['name'] in names:
            raise CandidateError('描述文件 pin 重名: ' + pin['name'])
        names.add(pin['name'])
    if ap['name'] not in names or m['name'] not in names:
        raise CandidateError('描述文件 pins 必须包含 AP 与清单成员')
    restore = c.get('manifestRestore')
    if restore is not None:
        if not isinstance(restore, dict) or not isinstance(restore.get('apSize'), int) \
                or not HEX64.match(str(restore.get('canonicalSHA256', ''))):
            raise CandidateError('描述文件 manifestRestore 无效')
    return c


def _row_key(row):
    keep = ('Name', 'BurnMode', 'BurnAddr', 'BurnPath')
    return {k: row.get(k) for k in keep}


def check(zip_path, candidate, stock=None):
    """Validate a candidate ZIP against its descriptor. Returns a report dict."""
    checks = []

    def record(name, ok, detail=''):
        checks.append({'name': name, 'ok': bool(ok), 'detail': detail})

    raw = b''
    zip_ok = False
    try:
        raw = Path(zip_path).read_bytes()
    except Exception as e:
        record('zip-readable', False, str(e))
    if raw:
        record('zip-size', len(raw) == candidate['zip']['size'],
               '%d 字节，期望 %d' % (len(raw), candidate['zip']['size']))
        record('zip-sha256', _sha(raw) == candidate['zip']['sha256'],
               _sha(raw))
        zip_ok = checks[-2]['ok'] and checks[-1]['ok']

    members = {}
    if zip_ok:
        try:
            with zipfile.ZipFile(Path(zip_path)) as z:
                names = z.namelist()
                record('member-set', len(names) == len(set(names)) == len(candidate['payloadPins'])
                       and set(names) == {p['name'] for p in candidate['payloadPins']},
                       '%d 个成员' % len(names))
                if checks[-1]['ok']:
                    record('zip-crc', z.testzip() is None, '')
                    members = {n: z.read(n) for n in names}
        except Exception as e:
            record('member-set', False, str(e))

    pins = {p['name']: p for p in candidate['payloadPins']}
    if members:
        bad = []
        for name, data in members.items():
            pin = pins[name]
            if len(data) != pin['size'] or _sha(data) != pin['sha256']:
                bad.append(name)
        record('member-pins', not bad, '不一致: ' + ', '.join(bad) if bad else '15 项 pins 全对')

        manifest_name = candidate['manifest']['name']
        ap_name = candidate['ap']['name']
        record('manifest-sha256', _sha(members[manifest_name]) == candidate['manifest']['sha256'],
               _sha(members[manifest_name]))
        rows = None
        try:
            rows = json.loads(members[manifest_name].decode('utf-8'))
            if not isinstance(rows, list):
                raise ValueError('manifest 不是数组')
        except Exception as e:
            record('manifest-json', False, str(e))
        if isinstance(rows, list):
            names = {p['name'] for p in candidate['payloadPins']}
            ok = len(rows) == len(names) - 1
            seen = set()
            for row in rows:
                if not isinstance(row, dict) or set(row) != {'Name', 'Size', 'Md5', 'BurnMode', 'BurnAddr', 'BurnPath'}:
                    ok = False
                    break
                name = row['Name']
                data = members.get(name)
                if name not in names or name in seen or name == manifest_name \
                        or not isinstance(row['Size'], int) or row['Size'] != len(data) \
                        or hashlib.md5(data).hexdigest() != row['Md5']:
                    ok = False
                    break
                seen.add(name)
            record('manifest-json', ok and seen == names - {manifest_name},
                   '%d 行' % len(rows))
        record('ap-budget', candidate['ap']['size'] < candidate['apBudgetBytes'],
               'AP %d < 预算 %d' % (candidate['ap']['size'], candidate['apBudgetBytes']))
        record('ap-pin', len(members[ap_name]) == candidate['ap']['size']
               and _sha(members[ap_name]) == candidate['ap']['sha256'],
               'AP %d 字节' % len(members[ap_name]))

    if stock is not None and members:
        stock = Path(stock)
        baseline = None
        try:
            baseline = json.loads((stock / candidate['manifest']['name']).read_bytes())
            if not isinstance(baseline, list):
                raise ValueError('原厂清单不是数组')
        except Exception as e:
            record('stock-baseline', False, str(e))
            baseline = None
        if baseline is not None:
            ap_name = candidate['ap']['name']
            unchanged, changed = [], []
            for name in sorted(pins):
                if name == candidate['manifest']['name']:
                    continue
                same = (stock / name).exists() and (stock / name).read_bytes() == members[name]
                (unchanged if same else changed).append(name)
            record('stock-unchanged', not changed,
                   ('逐字节一致: %d 项' % len(unchanged)) if not changed else '被改动: ' + ', '.join(changed))
            try:
                record('stock-ap', _sha((stock / ap_name).read_bytes()) == candidate['stockAPSHA256'],
                       '原厂 AP 基线')
            except Exception as e:
                record('stock-ap', False, str(e))
            base_rows = len(baseline)
            cand_rows = json.loads(members[candidate['manifest']['name']])
            ok = base_rows == len(cand_rows)
            detail = ''
            if ok:
                for row in cand_rows:
                    name = row['Name']
                    before = next((r for r in baseline if isinstance(r, dict) and r.get('Name') == name), None)
                    if before is None:
                        ok = False
                        break
                    if name == ap_name:
                        if {k: v for k, v in row.items() if k not in ('Size', 'Md5')} != \
                           {k: v for k, v in before.items() if k not in ('Size', 'Md5')}:
                            ok = False
                            detail = 'AP 烧录字段被改动'
                            break
                    elif row != before:
                        ok = False
                        detail = '非 AP 清单行被改动: ' + name
                        break
            record('stock-manifest', ok, detail or 'Burn 字段与原厂一致')

    go = all(c['ok'] for c in checks)
    return {
        'candidate': candidate['codeName'],
        'zip': str(zip_path),
        'zipBytes': len(raw),
        'zipSHA256': _sha(raw) if raw else '',
        'zipMD5': hashlib.md5(raw).hexdigest() if raw else '',
        'otaSize': candidate['otaSize'],
        'go': go,
        'checks': checks,
        'deviceIO': False,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--stock', type=Path, default=None, help='原厂 1.0.4.12 解压基线目录（可选，做强比对）')
    parser.add_argument('--json', action='store_true', help='只输出 JSON 报告')
    args = parser.parse_args(argv)
    try:
        candidate = load_candidate(args.candidate)
    except CandidateError as e:
        print('NO-GO: %s' % e, file=sys.stderr)
        return 2
    report = check(args.zip, candidate, args.stock)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print('候选: %s  (%s)' % (report['candidate'], report['zip']))
        for c in report['checks']:
            mark = 'PASS' if c['ok'] else 'FAIL'
            line = '  [%s] %s' % (mark, c['name'])
            if c['detail']:
                line += ' — %s' % c['detail']
            print(line)
        print('ZIP MD5: %s（手机下载源应答用，无需比对）' % report['zipMD5'])
        print('GO：可以进入手机端向导' if report['go'] else 'NO-GO：不要刷，先修正上述 FAIL 项')
    return 0 if report['go'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
