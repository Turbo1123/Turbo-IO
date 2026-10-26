#!/usr/bin/env python3
"""One explicit existing-bond experiment; no pairing, unbinding or raw logging.

Requires Python 3.11+; BLE dependencies are imported only for a live run.
See README.md for the narrow evidence boundary and identity prerequisite.
"""
import argparse
import asyncio
import binascii
import hashlib
import hmac
import json
import re
import secrets
import sys
from pathlib import Path

SERVICE = '0000b81d-0000-1000-8000-00805f9b34fb'
RX = '7db3e235-3608-41f3-a03c-955fcbd2ea4b'
TX = 'ea8b70d5-2bd3-49ab-9c31-9c38b2c3c4f9'
PAIRED = 'ea8b60c5-2bd3-49ab-9c31-9d38b1c5c5f9'
SALT = bytes.fromhex('0712c8ad27744195de5fa1ea6d025fb8')


def crc(data):
    return binascii.crc_hqx(data, 0)


def tlv(tag, value):
    return bytes([tag]) + len(value).to_bytes(2, 'big') + value


def untlv(data):
    fields = []
    while data:
        if len(data) < 3:
            raise ValueError('truncated TLV')
        size = int.from_bytes(data[1:3], 'big')
        if size > len(data) - 3:
            raise ValueError('truncated TLV')
        fields.append((data[0], data[3:3 + size]))
        data = data[3 + size:]
    return fields


def container(payload, tag):
    outer = untlv(payload)
    if len(outer) != 1 or outer[0][0] != tag:
        raise ValueError('unexpected container')
    fields = untlv(outer[0][1])
    if len(dict(fields)) != len(fields):
        raise ValueError('duplicate fields')
    return dict(fields)


def frame(seq, bid, payload):
    body = seq.to_bytes(2, 'big') + bytes([0, bid]) + payload
    return b'\xaa\x55' + len(body).to_bytes(2, 'big') + body + crc(body).to_bytes(2, 'big')


class Frames:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        if len(self.buffer) + len(data) > 131082:
            raise ValueError('receive buffer limit')
        self.buffer.extend(data)
        packets = []
        while len(self.buffer) >= 4:
            if self.buffer[:2] != b'\xaa\x55':
                raise ValueError('frame synchronization')
            size = int.from_bytes(self.buffer[2:4], 'big') + 6
            if size < 10:
                raise ValueError('frame length')
            if len(self.buffer) < size:
                break
            raw = bytes(self.buffer[:size])
            del self.buffer[:size]
            if crc(raw[4:-2]) != int.from_bytes(raw[-2:], 'big'):
                raise ValueError('frame CRC')
            # A deliberately narrow experiment, not a general transport decoder.
            if raw[6] != 0:
                raise ValueError('unsupported frame metadata')
            packets.append((raw[7], raw[8:-2]))
        return packets


def version_request(phone):
    if len(phone) != 6:
        raise ValueError('identity length')
    # Preserve the profile used in the original successful macOS experiment.
    fields = [(16, b'\x01'), (17, phone), (18, b'RayNeo Mac Probe'),
              (19, b'\x01'), (22, b'iPhone'), (23, b'iPhone'), (27, b'\x02')]
    return tlv(17, b''.join(tlv(tag, value) for tag, value in fields))


def validate_version(payload, peer):
    fields = container(payload, 17)
    if fields.get(16) not in (b'\x01', b'\x02') or fields.get(17) != peer:
        raise ValueError('version or peer mismatch')
    if fields.get(26, b'') or 25 in fields:
        raise ValueError('account/key authentication not supported')


def proof(random, phone, peer):
    if (len(random), len(phone), len(peer)) != (4, 6, 6):
        raise ValueError('authentication input length')
    return hashlib.sha256(random + phone + peer + SALT).digest()


def verify_peer(payload, phone, peer):
    fields = container(payload, 25)
    expected = proof(fields.get(16, b''), phone, peer)
    if not hmac.compare_digest(expected, fields.get(17, b'')):
        raise ValueError('peer proof mismatch')


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def envelope(body):
    data = json.dumps(body, separators=(',', ':')).encode()
    return b'\x08\x01\x10\x01\x1a' + varint(len(data)) + data + b'\x22\x00'


def status(payload):
    fields, offset = {}, 0
    def read_varint():
        nonlocal offset
        value = 0
        for shift in range(0, 70, 7):
            if offset >= len(payload):
                raise ValueError('truncated varint')
            byte = payload[offset]
            offset += 1
            if shift == 63 and byte > 1:
                raise ValueError('varint overflow')
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError('varint overflow')
    while offset < len(payload):
        key = read_varint()
        field, wire = key >> 3, key & 7
        if field == 0 or field in fields:
            raise ValueError('invalid envelope field')
        if wire == 0:
            fields[field] = read_varint()
        elif wire in (1, 2, 5):
            size = read_varint() if wire == 2 else (8 if wire == 1 else 4)
            if size > len(payload) - offset:
                raise ValueError('truncated envelope')
            fields[field] = payload[offset:offset + size]
            offset += size
        else:
            raise ValueError('unsupported envelope')
    if fields.get(1) != 1 or fields.get(2) != 1 or not isinstance(fields.get(3), bytes):
        raise ValueError('not general status')
    body = json.loads(fields[3])
    general = body.get('generalStatus') if isinstance(body, dict) else None
    battery = general.get('battery') if isinstance(general, dict) else None
    if type(battery) is not int or not 0 <= battery <= 100:
        raise ValueError('missing valid battery')
    return battery


async def exchange(send, queue, phone, peer, sleep=asyncio.sleep):
    async def receive(bid, tag=None):
        async with asyncio.timeout(12):
            while True:
                item = await queue.get()
                if isinstance(item, Exception):
                    raise item
                business, payload = item
                if business == bid and (tag is None or payload[:1] == bytes([tag])):
                    return payload
    await send(1, 16, version_request(phone))
    validate_version(await receive(16, 17), peer)
    random = secrets.token_bytes(4)
    await send(2, 16, tlv(24, tlv(16, random) + tlv(17, proof(random, phone, peer))))
    verify_peer(await receive(16, 25), phone, peer)
    print('peer proof verified; status not yet confirmed')
    await sleep(5)
    while not queue.empty():
        item = queue.get_nowait()
        if isinstance(item, Exception):
            raise item
    await send(3, 15, envelope({'cmd': 'request_general_status',
                              'payload': {'data': '', 'mode': 0, 'value': 0}}))
    async with asyncio.timeout(12):
        while True:
            payload = await receive(15)
            try:
                return status(payload)
            except (ValueError, TypeError):
                continue  # Other launcher messages do not prove status readiness.


def load_config(path):
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict) or set(data) != {'name', 'phone_identifier', 'peer_identifier'}:
        raise ValueError('config keys')
    if not isinstance(data['name'], str) or not 1 <= len(data['name']) <= 248:
        raise ValueError('device name')
    for key in ('phone_identifier', 'peer_identifier'):
        if not isinstance(data[key], str) or not re.fullmatch('[0-9a-fA-F]{12}', data[key]):
            raise ValueError('identifier format')
    return data['name'], bytes.fromhex(data['phone_identifier']), bytes.fromhex(data['peer_identifier'])


async def run(config):
    from bleak import BleakClient, BleakScanner
    from bleak.backends.device import BLEDevice
    from CoreBluetooth import CBUUID
    name, phone, peer = config
    async with BleakScanner() as scanner:
        await asyncio.sleep(10)
        devices = list(scanner.discovered_devices)
        # Bleak 3.0.2 private API: retain the same live CoreBluetooth manager.
        manager = scanner._backend._manager
        connected = manager.central_manager.retrieveConnectedPeripheralsWithServices_([CBUUID.UUIDWithString_(SERVICE)])
        known = {d.address for d in devices}
        for peripheral in connected:
            address = str(peripheral.identifier().UUIDString())
            if address not in known:
                devices.append(BLEDevice(address, peripheral.name(), (peripheral, manager)))
                known.add(address)
    targets = [d for d in devices if (d.name or '').casefold() == name.casefold()]
    if len(targets) != 1:
        raise ValueError('expected exactly one matching device')
    async with BleakClient(targets[0], timeout=15) as client:
        descriptor = bytes(await client.read_gatt_char(PAIRED))
        if len(descriptor) != 20 or descriptor[:6] != peer:
            raise ValueError('paired descriptor mismatch')
        queue, stream = asyncio.Queue(maxsize=128), Frames()
        failure = None
        def receive(_, data):
            nonlocal failure
            if failure is not None:
                return
            try:
                for packet in stream.feed(data):
                    queue.put_nowait(packet)
            except (ValueError, asyncio.QueueFull):
                failure = ValueError('receive framing or capacity failure')
                while not queue.empty():
                    queue.get_nowait()
                queue.put_nowait(failure)
        await client.start_notify(RX, receive)
        await asyncio.sleep(3)
        async def send(seq, bid, payload):
            if failure is not None:
                raise failure
            characteristic = client.services.get_characteristic(TX)
            if characteristic is None or 'write-without-response' not in characteristic.properties:
                raise ValueError('required write characteristic unavailable')
            maximum = characteristic.max_write_without_response_size
            if not 1 <= maximum <= 512:
                raise ValueError('invalid write capacity')
            raw = frame(seq, bid, payload)
            for offset in range(0, len(raw), maximum):
                await client.write_gatt_char(characteristic, raw[offset:offset + maximum], response=False)
                await asyncio.sleep(0.03)
        while not queue.empty():
            item = queue.get_nowait()
            if isinstance(item, Exception):
                raise item
        battery = await exchange(send, queue, phone, peer)
        print(f'general status received; battery={battery}%')
        print('experiment complete; closing BLE connection without changing binding')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, help='private JSON file; see README')
    parser.add_argument('--run', action='store_true', help='explicitly connect and send one auth attempt')
    args = parser.parse_args()
    if not args.run:
        parser.error('--run is required; no BLE operation performed')
    if sys.platform != 'darwin' or sys.version_info < (3, 11):
        parser.error('requires macOS and Python 3.11+')
    try:
        asyncio.run(asyncio.wait_for(run(load_config(args.config)), timeout=75))
    except KeyboardInterrupt:
        print('cancelled; no automatic retry', file=sys.stderr)
        return 130
    except Exception as error:
        # Backend errors may embed device identifiers; do not print their text.
        print(f'probe stopped ({type(error).__name__}); no automatic retry or unbinding', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
