"""Read-only, bounded GGUF metadata/tensor inventory; never edits the model."""
import collections
import json
import pathlib
import struct
import sys


def inspect(path):
    with open(path, "rb") as f:
        def scalar(fmt):
            n = struct.calcsize(fmt)
            raw = f.read(n)
            if len(raw) != n:
                raise ValueError("truncated GGUF")
            return struct.unpack(fmt, raw)[0]

        def string():
            n = scalar("<Q")
            if n > 1048576:
                raise ValueError("oversized string")
            raw = f.read(n)
            if len(raw) != n:
                raise ValueError("truncated string")
            return raw.decode("utf-8", errors="replace")

        formats = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i", 6: "<f", 7: "<?", 10: "<Q", 11: "<q", 12: "<d"}

        def value(kind, depth=0):
            if depth > 2:
                raise ValueError("nested array")
            if kind == 8:
                return string()
            if kind == 9:
                element, count = scalar("<I"), scalar("<Q")
                if count > 1000000:
                    raise ValueError("oversized array")
                for _ in range(count):
                    value(element, depth + 1)
                return {"array_count": count, "element_type": element}
            return scalar(formats[kind])

        if f.read(4) != b"GGUF" or scalar("<I") != 3:
            raise ValueError("expected GGUF v3")
        tensors, count = scalar("<Q"), scalar("<Q")
        if tensors > 10000 or count > 10000:
            raise ValueError("oversized header")
        metadata = {}
        metadata_offsets = {}
        for _ in range(count):
            key = string()
            kind = scalar("<I")
            metadata_offsets[key] = {"type": kind, "offset": f.tell()}
            metadata[key] = value(kind)
        rows = []
        for _ in range(tensors):
            name, dimensions = string(), scalar("<I")
            if dimensions > 4:
                raise ValueError("invalid tensor dimensions")
            shape = [scalar("<Q") for _ in range(dimensions)]
            kind_offset = f.tell()
            kind, offset = scalar("<I"), scalar("<Q")
            rows.append(dict(name=name, shape=shape, type=kind, offset=offset, type_header_offset=kind_offset))
        alignment = metadata.get("general.alignment", 32)
        data_start = ((f.tell() + alignment - 1) // alignment) * alignment
        return dict(file=pathlib.Path(path).name, metadata=metadata, metadata_offsets=metadata_offsets, data_start=data_start, tensor_types=dict(collections.Counter(r["type"] for r in rows)), tensors=rows)


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1]), ensure_ascii=False, indent=2))
