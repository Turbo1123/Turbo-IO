"""Exact-artifact adapter: STQ type 42 -> 43, ftype 41 -> 42. No requantization.

Refuses other files, existing destinations or any unexpected tensor layout.
The original is preserved. This is NOT a generic GGUF repair tool.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
from inspect_gguf import inspect

ORIGINAL_SHA = "cc497fe8f033b52b3b8b00a7669e9661435432f9d4cd43f7ed24400c01507a93"
ORIGINAL_SIZE = 461860800


def prepare(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists() or source.resolve() == destination.resolve():
        raise ValueError("destination must be new; original is never overwritten")
    raw = source.read_bytes()
    if len(raw) != ORIGINAL_SIZE or hashlib.sha256(raw).hexdigest() != ORIGINAL_SHA:
        raise ValueError("not the pinned Tencent original")
    info = inspect(source)
    if info["tensor_types"] != {0: 129, 14: 1, 42: 224}:
        raise ValueError("unexpected tensor types")
    rows = info["tensors"]
    expected = 0
    for r in rows:
        if r["offset"] != expected:
            raise ValueError("non-contiguous tensor data")
        elements = math.prod(r["shape"])
        if r["type"] == 0:
            length = elements * 4
        else:
            if r["shape"][0] % 256:
                raise ValueError("unexpected quantization block")
            length = elements // 256 * (210 if r["type"] == 14 else 42)
        expected += (length + 31) // 32 * 32
    if info["data_start"] + expected != len(raw):
        raise ValueError("unexpected payload size")
    ftype = info["metadata_offsets"]["general.file_type"]
    if ftype["type"] != 4 or info["metadata"]["general.file_type"] != 41:
        raise ValueError("unexpected file type metadata")
    edited = bytearray(raw)
    edits = [(ftype["offset"], 41, 42)]
    edits += [(r["type_header_offset"], 42, 43) for r in rows if r["type"] == 42]
    for offset, old, new in edits:
        if struct.unpack_from("<I", edited, offset)[0] != old:
            raise ValueError("unexpected header field")
        struct.pack_into("<I", edited, offset, new)
    start = info["data_start"]
    if raw[start:] != edited[start:]:
        raise ValueError("payload changed")
    with destination.open("xb") as output:
        output.write(edited)
    result = dict(original_sha256=ORIGINAL_SHA, adapted_sha256=hashlib.sha256(edited).hexdigest(),
                  size=len(edited), header_fields_changed=len(edits), payload_unchanged=True,
                  payload_sha256=hashlib.sha256(raw[start:]).hexdigest(), data_start=start,
                  kernel_commit="1e411d8f5a1e23525fa3265dfb4bd76265465397")
    return result


if __name__ == "__main__":
    print(json.dumps(prepare(sys.argv[1], sys.argv[2]), indent=2))
