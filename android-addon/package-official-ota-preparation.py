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

ROUTES = (b'http://127.0.0.1:18794/g/xxxxxxxA78p2M', b'http://127.0.0.1:18794/g/xxxxxxxxxxCCXhB')
# original libapp.so SHA-256 -> (patched SHA-256, version tag, slot offsets)
PROFILES = {
    'e9ab4326681c0b53892550b04e03284b2bba2e30adcf22033b8e23e5b3bc66af':
        ('96cc9a9f4634a2321e06790d0f062cd36e6420ef69c6166eb5bab41608fb917e', '106', (0x885c9a, 0xe1ffc)),
    'a35159a82c0916f62ed6c4da271a40217300cc6678b29c54f2591d9fb592a45c':
        ('48ffd34352bf23eca928ad9c2f576347c4965a5af5ca05a35c1f1ed2ffc9fd50', '107', (0x88512e, 0xe1e48)),
}
NATIVE = 'lib/arm64-v8a/libapp.so'
MARKER = 'assets/turboio/official-ota-preparation.txt'
VALUE = 'ANDROID-{}-OFFICIAL-OTA-PREPARE-01\n'
root = pathlib.Path(__file__).resolve().parent
arguments = sys.argv[1:]
guarded = arguments and arguments[0] == '--guarded'
if guarded:
    arguments = arguments[1:]
    MARKER = 'assets/turboio/official-ota-guarded.txt'
    VALUE = 'ANDROID-{}-OFFICIAL-OTA-GUARD-02\n'
original, base, patched_lib, out = map(pathlib.Path, arguments)
if out.exists() or out.resolve() in {p.resolve() for p in (original, base, patched_lib)}:
    raise SystemExit('Refuse to overwrite an existing artifact or an input')
subprocess.run([sys.executable, str(root/'verify_apk.py'), str(original), str(base), '--public-assets'], check=True)
new = patched_lib.read_bytes()
with zipfile.ZipFile(base) as z:
    before = z.read(NATIVE)
    PATCHED, TAG, OFFSETS = PROFILES[hashlib.sha256(before).hexdigest()]
    VALUE = VALUE.format(TAG).encode()
    SLOTS = list(zip(OFFSETS, (b'/xrlauncherapi/v1/signApi/gray/upgrade', b'/xrlauncherhwapi/v1/signApi/gray/upgrade'), ROUTES))
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
