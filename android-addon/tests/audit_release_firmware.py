"""Read-only audit of the exact, user-validated TAP1-TEST-01 release artifact."""
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

archive, stock = map(Path, sys.argv[1:])
digest = lambda b: hashlib.sha256(b).hexdigest()
raw = archive.read_bytes()
assert digest(raw) == '5ef21d8c18501d03fad6edee4fe039649cb567352e30dbd234081ecf97140afa'
with zipfile.ZipFile(archive) as z:
    assert len(z.namelist()) == len(set(z.namelist())) == 15
    assert z.testzip() is None
    members = {n: z.read(n) for n in z.namelist()}
    assert all(Path(n).name == n for n in members)
manifest = json.loads(members['OtaFileInfo.json'])
original = json.loads((stock / 'OtaFileInfo.json').read_bytes())
assert len(manifest) == len(original) == 14
unchanged = []
inherited_patterns = 0
for entry, before in zip(manifest, original):
    name = entry['Name']
    assert name == before['Name']
    data = members[name]
    assert len(data) == entry['Size']
    assert hashlib.md5(data).hexdigest() == entry['Md5']
    if name != 'nuttx_ap.bin':
        assert entry == before and data == (stock / name).read_bytes()
        unchanged.append(name)
    else:
        assert {k:v for k,v in entry.items() if k not in ('Size','Md5')} == {k:v for k,v in before.items() if k not in ('Size','Md5')}
        assert len(data) == 9590856
        assert digest(data) == '65e0a5312361ec785eb9ab1659badf182765f4054d4d95fef4c61ceb49dfa4b4'
        assert '显示TEST'.encode() in data
        # Only report category/member, never matching credential bytes.
        for rule in (rb'sk-(?:ws-|tinyfish-)?[A-Za-z0-9_.-]{18,}', rb'wrk-[A-Za-z0-9]{16,}', rb'-----BEGIN [A-Z ]*PRIVATE KEY-----', rb'wr_skey=[^;\s\x00]{8,}'):
            for match in re.finditer(rule, data):
                # Stock crypto libraries contain algorithm names and PEM header
                # literals. Allow only exact bytes already present in stock AP.
                assert match[0] in (stock / name).read_bytes(), 'new credential-like bytes in AP; stop publication'
                inherited_patterns += 1
assert len(unchanged) == 13
print(json.dumps(dict(candidate='TAP1-TEST-01', zipBytes=len(raw), zipSHA256=digest(raw),
    apBytes=len(members['nuttx_ap.bin']), apSHA256=digest(members['nuttx_ap.bin']),
    unchangedNonAPPayloads=unchanged, manifestValid=True, archiveValid=True,
    newCredentialPatternsFound=False, inheritedStockPatternMatches=inherited_patterns,
    validation={'date':'2026-09-27','phone':'Samsung Fold3','android':'15','host':'RayNeo AI 1.0.5 (201)',
                'addon':'GUARD-07','validatedChunks':279,'apCoverageBytes':9590856,'blocked':0,
                'userConfirmedSuccessfulFlashAndNormalOperation':True,
                'automaticPostBootCompletionVerified':False}), ensure_ascii=False, indent=2))
