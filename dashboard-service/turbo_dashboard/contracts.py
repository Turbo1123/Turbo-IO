"""Mirror of TCE1 phone/firmware limits. The phone remains the final wire gate."""
import base64
import copy
import hashlib
import json
import re
import unicodedata
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA = json.loads(Path(__file__).with_name("card.schema.json").read_text())
VALIDATOR = Draft202012Validator(SCHEMA)
DATA_FIELDS = {"text": {"text"}, "progress": {"value"}, "barChart": {"points"},
               "lineChart": {"points"}, "image": {"pixels"}}


class Fault(Exception):
    def __init__(self, code, message, status=422):
        self.code, self.message, self.status = code, message, status


def canonical(value):
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    except (TypeError, ValueError, UnicodeError):
        raise Fault("invalid_json", "Only finite JSON values and valid UTF-8 are supported") from None


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def exact(obj, keys):
    if not isinstance(obj, dict) or set(obj) != set(keys):
        raise Fault("fields", "Unexpected or missing fields")


def integer(v, low=0, high=2**31-1):
    if type(v) is not int or not low <= v <= high:
        raise Fault("integer", "Integer value outside allowed range")
    return v


def validate(doc):
    if len(canonical(doc)) > 6000:
        raise Fault("document_limit", "Card JSON exceeds 6000 UTF-8 bytes")
    error = next(VALIDATOR.iter_errors(doc), None)
    if error:
        # Never echo arbitrary supplied values in logs/errors.
        raise Fault("schema", "CardDocument does not match the v1 schema")
    integer(doc['schema'], 1, 1)
    if len(doc["name"].encode()) > 60:
        raise Fault("name_limit", "Card name exceeds 60 UTF-8 bytes")
    seen = set()
    pixels = images = charts = 0
    wire = 8
    for c in doc["components"]:
        if c["id"] in seen:
            raise Fault("duplicate_component", "Component IDs must be unique")
        seen.add(c["id"])
        for k in ("x", "y", "w", "h"):
            integer(c[k])  # jsonschema permits integral floats; phone does not need them.
        x, y, w, h, kind = (c[k] for k in ("x", "y", "w", "h", "kind"))
        if x+w > 250 or y+h > 188:
            raise Fault("bounds", "Component extends beyond the 6px safe area")
        wire += 10
        if kind == "text":
            integer(c["font"])
            if len(c["text"].encode()) > 96 or any(unicodedata.category(ch) == "Cc" for ch in c["text"]):
                raise Fault("text_limit", "Text exceeds 96 UTF-8 bytes or contains controls")
            if h < c["font"] + 4 or w < 16:
                raise Fault("text_bounds", "Text requires height >= font + 4 and width >= 16")
            wire += len(c["text"].encode())
        if kind in ("icon", "image"):
            images += 1
            pixels += w*h
            wire += w*h//8
            if w != h:
                raise Fault("image_size", "Icons/images must be square")
            if kind == "icon":
                integer(c["icon"], 0, 15)
            else:
                try:
                    b = base64.b64decode(c["pixels"], validate=True)
                except ValueError:
                    raise Fault("image_data", "Invalid base64 image") from None
                if len(b) != w*h//8 or base64.b64encode(b).decode() != c["pixels"]:
                    raise Fault("image_data", "Image length/canonical base64 mismatch")
        if kind == "progress":
            integer(c["value"], 0, 100)
        if kind in ("barChart", "lineChart"):
            charts += 1
            pixels += ((w+3)//4)*4*h
            wire += len(c["points"])
            for value in c["points"]:
                integer(value, 0, 100)
    if images > 4 or charts > 2 or pixels > 32768 or wire > 2048:
        raise Fault("resource_budget", "Card exceeds component/pixel/wire budget")
    return {"valid": True, "wireBytes": wire, "pixelBytes": pixels,
            "physicalVerified": False, "requiresFirmware": "TCE1"}


def layout_hash(doc):
    layout = copy.deepcopy(doc)
    for c in layout["components"]:
        for field in DATA_FIELDS.get(c["kind"], set()):
            c.pop(field, None)
    return digest(layout)


def patch_data(doc, updates):
    if not isinstance(updates, dict) or not 1 <= len(updates) <= 12:
        raise Fault("updates", "Expected 1–12 component updates")
    result = copy.deepcopy(doc)
    items = {c["id"]: c for c in result["components"]}
    for ident, values in updates.items():
        c = items.get(ident)
        if c is None or not isinstance(values, dict) or not values or not set(values) <= DATA_FIELDS.get(c["kind"], set()):
            raise Fault("data_only", "Unknown component or non-data property; use a layout revision instead")
        c.update(values)
    validate(result)
    return result


def text(ident, value, x, y, w, font=18):
    return dict(id=ident, kind="text", x=x, y=y, w=w, h=font+4, text=value, font=font, align="left")


TEMPLATES = [
    {"schema": 1, "id": "turbo_ui_card_metrics", "name": "服务监控 · 示例",
     "components": [text("title", "服务监控 示例", 12, 8, 232, 20),
                    text("cpu_label", "CPU 25%", 12, 50, 224),
                    dict(id="cpu_bar", kind="progress", x=12, y=80, w=224, h=8, value=25),
                    text("ram_label", "RAM 50%", 12, 106, 224),
                    dict(id="ram_bar", kind="progress", x=12, y=136, w=224, h=8, value=50),
                    text("updated", "示例 · 未连接数据源", 12, 164, 224, 14)]},
    {"schema": 1, "id": "turbo_ui_card_reading", "name": "今日阅读 · 示例",
     "components": [dict(id="book", kind="icon", x=12, y=12, w=32, h=32, icon=8),
                    text("title", "今日阅读 示例", 54, 16, 184),
                    text("minutes", "30 / 60 分钟", 12, 68, 224, 24),
                    dict(id="progress", kind="progress", x=12, y=124, w=224, h=8, value=50),
                    text("note", "数据由你的后端提供", 12, 158, 224, 16)]},
]
for template in TEMPLATES:
    validate(template)
