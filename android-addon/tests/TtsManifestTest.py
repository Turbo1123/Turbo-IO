import pathlib
import struct
import sys
import unittest
import zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from tts_manifest import patch, ACTION

class ManifestTest(unittest.TestCase):
    def test_pinned_manifest(self):
        apk=pathlib.Path(__file__).resolve().parents[1]/'build/host-105/AndroidManifest.xml'
        if not apk.exists(): self.skipTest('Pinned host has not been decoded')
        original=apk.read_bytes()
        changed=patch(original)
        self.assertNotEqual(changed,original)
        self.assertEqual(patch(changed),changed)
        def chunks(data):
            at=8; out=[]
            while at<len(data):
                n=struct.unpack_from('<I',data,at+4)[0];out.append(data[at:at+n]);at+=n
            return out
        before=chunks(original);after=chunks(changed)
        self.assertEqual(len(after),len(before)+4)
        # Every non-string-pool original chunk is identical and ordered. Only
        # the intent/action start/end four-node block is new.
        j=0;added=[]
        for c in after:
            if struct.unpack_from('<H',c)[0]==1:
                self.assertEqual(struct.unpack_from('<H',before[j])[0],1);j+=1
            elif j<len(before) and c==before[j]:j+=1
            else:added.append(c)
        self.assertEqual(j,len(before));self.assertEqual(len(added),4)
        self.assertTrue(ACTION.encode() in changed or ACTION.encode('utf-16le') in changed)
        with self.assertRaises((ValueError,struct.error)):patch(b'not XML')

if __name__=='__main__':unittest.main()
