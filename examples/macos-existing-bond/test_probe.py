import asyncio
import unittest
from unittest.mock import AsyncMock
import probe as p

PHONE = bytes.fromhex('102030405060')
PEER = bytes.fromhex('a0b0c0d0e0f0')


class ProtocolTests(unittest.TestCase):
    def test_crc_and_fragmented_frame(self):
        self.assertEqual(p.crc(b'123456789'), 0x31c3)
        raw = p.frame(1, 16, b'abc')
        stream = p.Frames()
        self.assertEqual(stream.feed(raw[:5]), [])
        self.assertEqual(stream.feed(raw[5:] + raw), [(16, b'abc'), (16, b'abc')])

    def test_corrupt_crc_and_unsupported_metadata_rejected(self):
        raw = p.frame(1, 16, b'abc')
        with self.assertRaises(ValueError):
            p.Frames().feed(raw[:-1] + bytes([raw[-1] ^ 1]))
        body = b'\x00\x01\x01\x10abc'
        flagged = b'\xaa\x55' + len(body).to_bytes(2, 'big') + body + p.crc(body).to_bytes(2, 'big')
        with self.assertRaises(ValueError):
            p.Frames().feed(flagged)

    def test_version_and_identity(self):
        request = dict(p.untlv(p.untlv(p.version_request(PHONE))[0][1]))
        self.assertEqual(request[17], PHONE)
        self.assertEqual(request[27], b'\x02')
        for version in (1, 2):
            p.validate_version(p.tlv(17, p.tlv(16, bytes([version])) + p.tlv(17, PEER)), PEER)

    def test_version_rejects_missing_unknown_wrong_peer_and_account_branch(self):
        good = p.tlv(16, b'\x02') + p.tlv(17, PEER)
        for fields in (p.tlv(17, PEER), p.tlv(16, b'\x03') + p.tlv(17, PEER),
                       p.tlv(16, b'\x02') + p.tlv(17, PHONE),
                       good + p.tlv(16, b'\x02'), good + p.tlv(26, b'account'),
                       good + p.tlv(25, b'')):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                p.validate_version(p.tlv(17, fields), PEER)

    def test_peer_proof(self):
        random = bytes([1, 2, 3, 4])
        reply = p.tlv(25, p.tlv(16, random) + p.tlv(17, p.proof(random, PHONE, PEER)))
        p.verify_peer(reply, PHONE, PEER)
        with self.assertRaises(ValueError):
            p.verify_peer(reply, PEER, PHONE)
        with self.assertRaises(ValueError):
            p.untlv(b'\x10\x00\x02\x01')

    def test_status_requires_valid_battery(self):
        self.assertEqual(p.status(p.envelope({'generalStatus': {'battery': 73}})), 73)
        for body in ({}, {'generalStatus': {}}, {'generalStatus': {'battery': True}},
                     {'generalStatus': {'battery': 101}}):
            with self.assertRaises(ValueError):
                p.status(p.envelope(body))
        with self.assertRaises(ValueError):
            p.status(b'\x1a\xff\xff')


class SessionTests(unittest.IsolatedAsyncioTestCase):
    async def test_session_sends_only_version_auth_status_once(self):
        queue = asyncio.Queue()
        sent = []
        async def send(seq, bid, payload):
            sent.append((seq, bid, payload))
            if seq == 1:
                queue.put_nowait((16, p.tlv(17, p.tlv(16, b'\x02') + p.tlv(17, PEER))))
            elif seq == 2:
                r = bytes([5, 6, 7, 8])
                queue.put_nowait((16, p.tlv(25, p.tlv(16, r) + p.tlv(17, p.proof(r, PHONE, PEER)))))
            elif seq == 3:
                queue.put_nowait((15, p.envelope({'generalStatus': {'battery': 73}})))
        battery = await p.exchange(send, queue, PHONE, PEER, sleep=AsyncMock())
        self.assertEqual(battery, 73)
        self.assertEqual([(s, b) for s, b, _ in sent], [(1, 16), (2, 16), (3, 15)])
        self.assertEqual([p.untlv(x[2])[0][0] for x in sent[:2]], [17, 24])

    async def test_bad_proof_never_sends_status(self):
        queue = asyncio.Queue()
        sent = []
        async def send(seq, bid, payload):
            sent.append(seq)
            if seq == 1:
                queue.put_nowait((16, p.tlv(17, p.tlv(16, b'\x02') + p.tlv(17, PEER))))
            else:
                queue.put_nowait((16, p.tlv(25, p.tlv(16, bytes(4)) + p.tlv(17, bytes(32)))))
        with self.assertRaises(ValueError):
            await p.exchange(send, queue, PHONE, PEER, sleep=AsyncMock())
        self.assertEqual(sent, [1, 2])

    async def test_receive_failure_never_retries(self):
        queue = asyncio.Queue()
        queue.put_nowait(ValueError('receive failure'))
        send = AsyncMock()
        with self.assertRaises(ValueError):
            await p.exchange(send, queue, PHONE, PEER, sleep=AsyncMock())
        self.assertEqual(send.await_count, 1)

    async def test_version_rejection_never_sends_auth(self):
        queue = asyncio.Queue()
        sent = []
        async def send(seq, bid, payload):
            sent.append(seq)
            queue.put_nowait((16, p.tlv(17, p.tlv(16, b'\x03') + p.tlv(17, PEER))))
        with self.assertRaises(ValueError):
            await p.exchange(send, queue, PHONE, PEER, sleep=AsyncMock())
        self.assertEqual(sent, [1])


if __name__ == '__main__':
    unittest.main()
