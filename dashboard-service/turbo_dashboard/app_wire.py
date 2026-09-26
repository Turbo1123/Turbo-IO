"""TAP1 draft native bytecode: bounded records, no executable instructions."""
import struct
from .app_package import validate_app


def encode(doc):
    import base64
    validate_app(doc)
    pages = {p['id']: i for i, p in enumerate(doc['pages'])}
    count = sum(len(p['components']) for p in doc['pages'])
    body = bytearray(); first = 0
    for page in doc['pages']:
        body.extend(struct.pack('<HH', first, len(page['components']))); first += len(page['components'])
    for page in doc['pages']:
        for c in page['components']:
            kind = {'text': 1, 'button': 2, 'progress': 3, 'image': 4, 'frame': 5}[c['kind']]
            font, action, target, param = c.get('font', 0), 0, 0, c.get('value', 0)
            data = c.get('text', '').encode()
            if kind == 2:
                act = c['action']; action = {'page': 1, 'emit': 2, 'exit': 3}[act['type']]
                target = pages[act['target']] if action == 1 else 0
            if kind == 4:
                data = base64.b64decode(doc['assets'][c['asset']]['pixels'])
            body.extend(struct.pack('<BBBBHHHHHH', kind, font, action, target, c['x'], c['y'], c['w'], c['h'], param, len(data)))
            body.extend(data)
    wire = b'TAP1'+struct.pack('<BBHI', len(pages), pages[doc['entry']], count, 12+len(body))+body
    if len(wire) > 20480:
        raise ValueError('Native package exceeds 20 KiB')
    return wire
