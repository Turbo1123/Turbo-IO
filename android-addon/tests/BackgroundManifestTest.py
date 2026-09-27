import pathlib,sys,struct,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from background_manifest import patch,SERVICE,PERMISSION,OTA_SERVICE
from tts_manifest import patch as tts
class Test(unittest.TestCase):
 def test_exact_additions(self):
  p=pathlib.Path(__file__).resolve().parents[1]/'build/host-105/AndroidManifest.xml'
  if not p.exists():self.skipTest('no pinned APK')
  old=tts(p.read_bytes());new=patch(p.read_bytes());self.assertEqual(patch(new),new)
  def chunks(b):
   out=[];i=8
   while i<len(b):n=struct.unpack_from('<I',b,i+4)[0];out.append(b[i:i+n]);i+=n
   return out
  a=chunks(old);b=chunks(new);i=0;extra=[]
  for c in b:
   if struct.unpack_from('<H',c)[0]==1:self.assertEqual(struct.unpack_from('<H',a[i])[0],1);i+=1
   elif i<len(a) and a[i]==c:i+=1
   else:extra.append(c)
  self.assertEqual(i,len(a));self.assertEqual(len(extra),6)
  self.assertIn(SERVICE.encode('utf-16le') if SERVICE.encode() not in new else SERVICE.encode(),new)
  # service android:exported=false, foregroundServiceType=media|location|device|mic
  service=extra[2];self.assertEqual(struct.unpack_from('<H',service,28)[0],3)
  values=[struct.unpack_from('<BBI',service,36+j*20+14) for j in range(3)]
  self.assertTrue(any(t==18 and v==0 for _,t,v in values));self.assertTrue(any(t==17 and v==154 for _,t,v in values))
  ota=extra[4];values=[struct.unpack_from('<BBI',ota,36+j*20+14) for j in range(3)]
  self.assertTrue(any(t==18 and v==0 for _,t,v in values));self.assertTrue(any(t==17 and v==16 for _,t,v in values))
if __name__=='__main__':unittest.main()
