"""Draft TAX1/TAR1 phone-to-native command codec; no Bluetooth I/O.

Caller must validate the original ZIP/manifest, show exact SHA256 for consent,
and send only to the selected paired device. Session/CRC are NOT authorization.
No retry helper: timeout requires status query and a user decision.
"""
import struct
import zlib
from .app_package import validate_app, name
from .app_wire import encode
from .contracts import integer

OPERATIONS = {'query': 1, 'install': 2, 'launch': 3, 'stop': 4, 'remove': 5}


def command(operation, request, *, session=0, document=None, app_id=None, version=0, slot=255):
    if operation not in OPERATIONS:
        raise ValueError('unknown app operation')
    integer(request, 1, 0xffffffff)
    integer(session, 0, 0xffffffff)
    integer(version, 0, 65535)
    integer(slot, 0, 255)
    wire = b''
    title = b''
    identity = b''
    if operation == 'query':
        if session or document is not None or app_id is not None or version or slot != 255:
            raise ValueError('query has no target or mutation fields')
    else:
        if not session:
            raise ValueError('query current device session before mutation')
        if operation == 'install':
            if document is None or app_id is not None or version or slot != 255:
                raise ValueError('install accepts one complete validated document')
            validate_app(document)
            wire = encode(document)
            app_id, version = document['id'], document['version']
            title = document['name'].encode()
        else:
            if document is not None or slot >= 4 or not version:
                raise ValueError('target slot, app ID and exact version required')
        name(app_id)
        identity = app_id.encode()
    result = bytearray(struct.pack('<4sBBBBIIHHI', b'TAX1', OPERATIONS[operation], slot,
                                  len(identity), len(title), request, session, version, len(wire), 0))
    result += identity+title+wire
    struct.pack_into('<I', result, 20, zlib.crc32(result))
    return bytes(result)


def reply(data):
    if not isinstance(data, bytes) or len(data) != 376 or data[:4] != b'TAR1':
        raise ValueError('invalid native reply size/magic')
    result, flags, slot, active, request, session, last, size = struct.unpack_from('<BBBBIIII', data, 4)
    if result > 13 or flags & ~3 or slot not in (0, 1, 2, 3, 255) or active not in (0, 1, 2, 3, 255) or not request or not session or size != 376:
        raise ValueError('invalid native reply fields')
    slots = []
    for i in range(4):
        raw = data[24+88*i:24+88*(i+1)]
        state, ilen, nlen, reserved, version, length, generation, checksum = struct.unpack_from('<BBBBHHII', raw)
        if state == 0:
            if any(raw):
                raise ValueError('nonempty absent slot')
            slots.append(None)
            continue
        if state not in (1, 3) or not 1 <= ilen <= 24 or not 1 <= nlen <= 48 or reserved or not version or not generation or length > 20480 or (state == 3 and length) or (state == 1 and length < 12):
            raise ValueError('invalid slot metadata')
        if any(raw[16+ilen:40]) or any(raw[40+nlen:]):
            raise ValueError('nonzero slot padding')
        app_id = raw[16:16+ilen].decode('ascii')
        title = raw[40:40+nlen].decode('utf-8')
        name(app_id)
        if any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in title):
            raise ValueError('invalid slot title')
        slots.append(dict(id=app_id, name=title, version=version, bytes=length,
                          generation=generation, crc32=checksum, tombstone=state == 3))
    return dict(result=result, duplicate=bool(flags & 1), needsQuery=bool(flags & 2),
                slot=None if slot == 255 else slot, activeSlot=None if active == 255 else active,
                request=request, session=session, lastRequest=last, slots=slots,
                physicalDisplayVerified=False)
