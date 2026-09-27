"""Offline, exact-input TAP1 derivative: rename one menu label only.

Does not flash, send, authorize or modify the validated source candidate.
Existing executable bytes, addresses, heap requirements and other payloads stay
identical. The old 13-byte UTF-8 literal becomes a NUL-padded 13-byte literal.
"""
import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "official-addon/build/app-ap-20260926-spacefix-c"
ZIP_NAME = "StrixOS-1.0.4.12-TurboAppSDK-TAP1-CANDIDATE-NOT-APPROVED.zip"
SOURCE_ZIP_SHA = "c6cbe09e07769b2d3a704215708a44b5b6c8a3886238e17b60de392814939e53"
SOURCE_AP_SHA = "e578daeae22ac425f06cc66f7f636b8d2eb6bf9cc174ae605b500181bcdfff62"
BASE = 0x10190000
LABEL_AT = 0x91B5E3
NAMES_AT = 0x10AAC4B4 - BASE  # names[14], verified in source candidate ELF
OLD = "显示测试".encode() + b"\0"
NEW = ("显示TEST".encode() + b"\0").ljust(len(OLD), b"\0")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(out):
    assert not out.exists(), "Refuse to overwrite any artifact"
    source_zip = SOURCE / ZIP_NAME
    assert sha(source_zip.read_bytes()) == SOURCE_ZIP_SHA
    with zipfile.ZipFile(source_zip) as z:
        infos = z.infolist()
        assert len(infos) == 15 and len({i.filename for i in infos}) == 15
        assert z.testzip() is None
        members = {i.filename: z.read(i) for i in infos}
    before = members["nuttx_ap.bin"]
    assert sha(before) == SOURCE_AP_SHA and len(before) == 9590856
    assert before.count(OLD) == 1 and before[LABEL_AT:LABEL_AT + len(OLD)] == OLD
    pointers = struct.unpack_from("<14I", before, NAMES_AT)
    assert pointers[7] == BASE + LABEL_AT
    # No other menu entry may point into the overwritten allocation.
    assert all(not (BASE + LABEL_AT <= p < BASE + LABEL_AT + len(OLD))
               for i, p in enumerate(pointers) if i != 7)
    after = before[:LABEL_AT] + NEW + before[LABEL_AT + len(OLD):]
    assert len(after) == len(before) <= 9600000
    assert after[:LABEL_AT] == before[:LABEL_AT]
    assert after[LABEL_AT + len(OLD):] == before[LABEL_AT + len(OLD):]
    assert after[LABEL_AT:].split(b"\0", 1)[0].decode() == "显示TEST"
    assert after[:16] == before[:16] and after[-8:] == before[-8:]
    members["nuttx_ap.bin"] = after
    manifest = json.loads(members["OtaFileInfo.json"])
    assert len(manifest) == 14
    for row in manifest:
        if row["Name"] == "nuttx_ap.bin":
            row["Size"] = len(after)
            row["Md5"] = hashlib.md5(after).hexdigest()
    members["OtaFileInfo.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    stock_dir = ROOT / "firmware-inspection/StrixOS-1.0.4.12"
    stock_manifest = json.loads((stock_dir / "OtaFileInfo.json").read_bytes())
    assert [r["Name"] for r in manifest] == [r["Name"] for r in stock_manifest]
    for row, stock in zip(manifest, stock_manifest):
        data = members[row["Name"]]
        assert row["Size"] == len(data) and row["Md5"] == hashlib.md5(data).hexdigest()
        if row["Name"] == "nuttx_ap.bin":
            assert {k: v for k, v in row.items() if k not in ("Size", "Md5")} == {
                k: v for k, v in stock.items() if k not in ("Size", "Md5")}
        else:
            assert row == stock and data == (stock_dir / row["Name"]).read_bytes()
    out.mkdir(parents=True, mode=0o700)
    payload = out / "payload"
    payload.mkdir(mode=0o700)
    for name, data in members.items():
        assert Path(name).name == name
        (payload / name).write_bytes(data)
    archive = out / "StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip"
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as z:
        for info in infos:
            z.writestr(info, members[info.filename])
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None and len(z.infolist()) == 15
        assert all(z.read(n) == b for n, b in members.items())
    report = dict(candidate="TAP1-TEST-01", sourceZIP=SOURCE_ZIP_SHA,
                  sourceAP=SOURCE_AP_SHA, label="显示TEST", labelOffset=hex(LABEL_AT),
                  labelPointerIndex=7, apBytes=len(after), apSHA256=sha(after),
                  apMD5=hashlib.md5(after).hexdigest(), zipBytes=archive.stat().st_size,
                  zipSHA256=sha(archive.read_bytes()),
                  manifestSHA256=sha(members["OtaFileInfo.json"]),
                  changedByteOffsets=[hex(i) for i in range(LABEL_AT, LABEL_AT + len(OLD))
                                      if before[i] != after[i]],
                  unchangedNonAPPayloads=13, executableBytesUnchanged=True,
                  deviceIO=False, flashed=False, hardwareValidated=False)
    (out / "marker-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    build(parser.parse_args().out.resolve())
