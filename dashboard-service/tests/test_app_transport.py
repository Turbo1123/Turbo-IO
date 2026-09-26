import struct
import zlib
import pytest
from turbo_dashboard.app_transport import command, reply
from turbo_dashboard.app_package import validate_app
from turbo_dashboard.contracts import Fault
from test_app_package import example


def test_commands_are_bounded_and_bound_to_identity():
    doc = example()
    payload = command('install', 2, session=7392, document=doc)
    assert len(payload) <= 20576
    assert payload[:4] == b'TAX1'
    checksum, = struct.unpack_from('<I', payload, 20)
    zeroed = bytearray(payload)
    zeroed[20:24] = bytes(4)
    assert zlib.crc32(zeroed) == checksum
    for op in ['launch', 'stop', 'remove']:
        wire = command(op, 3, session=7392, app_id=doc['id'], version=doc['version'], slot=0)
        assert doc['id'].encode() in wire and len(wire) <= 48
        for kwargs in [dict(session=0), dict(slot=4), dict(app_id='../other'), dict(version=0)]:
            values = dict(session=7392, app_id=doc['id'], version=doc['version'], slot=0)
            values.update(kwargs)
            with pytest.raises((ValueError, Fault)):
                command(op, 3, **values)
    for kwargs in [dict(session=1), dict(app_id='tasks'), dict(document=doc), dict(version=1), dict(slot=0)]:
        with pytest.raises(ValueError):
            command('query', 1, **kwargs)
    for request in [0, -1, 0x100000000, True, 1.5, '1']:
        with pytest.raises(Fault):
            command('query', request)
    with pytest.raises(ValueError):
        command('flash', 1)


def test_native_reply_rejects_unbounded_or_ambiguous_fields():
    base = struct.pack('<4sBBBBIIII', b'TAR1', 0, 0, 255, 255, 1, 7392, 0, 376)+bytes(352)
    assert reply(base)['slots'] == [None]*4
    for packet in [b'', base[:-1], base+b'\0', b'XXXX'+base[4:]]:
        with pytest.raises(ValueError):
            reply(packet)
    for offset, value in [(4, 14), (5, 4), (6, 4), (7, 4), (24, 2), (25, 1)]:
        changed = bytearray(base);changed[offset] = value
        with pytest.raises(ValueError):
            reply(bytes(changed))


def test_package_title_matches_native_control_character_policy():
    for character in ['\x00', '\x1f', '\x7f', '\x80', '\x9f']:
        doc = example();doc['name'] = 'Task'+character
        with pytest.raises(Fault):
            validate_app(doc)
