"""Private preparation derivative. Preserve every audited member except two URL strings.

Requires the ordinary package's existing allowlist audit first. Never signs,
installs, alters firmware, reads credentials or starts an OTA operation.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import zipfile

ORIGINAL = '78214ba0e1057871315da1cee17d860415c8b913521e59afc2748e45ead64c6c'
PATCHED = '851e0c59babc656e4eb4f47e00f3947605c3ddba530eeef4b65e7942e2898541'
NATIVE = 'lib/arm64-v8a/libapp.so'
MARKER = 'assets/turboio/official-ota-preparation.txt'
VALUE = b'ANDROID-105-OFFICIAL-OTA-PREPARE-01\n'
SLOTS = [(0x86e1f5, b'/xrlauncherapi/v1/signApi/gray/upgrade', b'http://127.0.0.1:18794/g/xxxxxxxA78p2M'),
         (0xd95b8, b'/xrlauncherhwapi/v1/signApi/gray/upgrade', b'http://127.0.0.1:18794/g/xxxxxxxxxxCCXhB')]
root = pathlib.Path(__file__).resolve().parent
arguments = sys.argv[1:]
guarded = arguments and arguments[0] == '--guarded'
if guarded:
    arguments = arguments[1:]
    MARKER = 'assets/turboio/official-ota-guarded.txt'
    VALUE = b'ANDROID-105-OFFICIAL-OTA-GUARD-02\n'
original, base, patched_lib, out = map(pathlib.Path, arguments)
if out.exists() or out.resolve() in {p.resolve() for p in (original, base, patched_lib)}:
    raise SystemExit('Refuse to overwrite an existing artifact or an input')
subprocess.run([sys.executable, str(root/'verify_apk.py'), str(original), str(base), '--public-assets'], check=True)
new = patched_lib.read_bytes()
with zipfile.ZipFile(base) as z:
    before = z.read(NATIVE)
    assert hashlib.sha256(before).hexdigest() == ORIGINAL
    assert hashlib.sha256(new).hexdigest() == PATCHED
    expected = bytearray(before)
    for offset, old, replacement in SLOTS:
        assert len(old) == len(replacement) and before[offset:offset+len(old)] == old
        assert before[offset-1] == 128+len(old)*2
        expected[offset:offset+len(old)] = replacement
    assert bytes(expected) == new  # exact whole-file allowlist, no instruction changes
    assert not any(n in z.namelist() for n in ('assets/turboio/official-ota-guarded.txt', 'assets/turboio/official-ota-preparation.txt'))
    with zipfile.ZipFile(out, 'x') as dest:
        for info in z.infolist():
            dest.writestr(info, new if info.filename == NATIVE else z.read(info))
        dest.writestr(MARKER, VALUE)
with zipfile.ZipFile(base) as z, zipfile.ZipFile(out) as d:
    assert d.testzip() is None
    assert set(d.namelist()) == set(z.namelist()) | {MARKER}
    assert d.read(MARKER) == VALUE
    assert [name for name in z.namelist() if z.read(name) != d.read(name)] == [NATIVE]
report = {'profile':'OFFICIAL-OTA-GUARD-02' if guarded else 'OFFICIAL-OTA-PREPARE-01', 'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),
          'modifiedLibrary':NATIVE, 'librarySHA256':PATCHED, 'changesOnlyTwoSerializedURLs':True,
          'marker':MARKER, 'upgradeSendingEnabled':False, 'oneTimeAuthorizationAvailable':bool(guarded), 'installed':False, 'deviceValidated':False}
out.with_suffix('.audit.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
