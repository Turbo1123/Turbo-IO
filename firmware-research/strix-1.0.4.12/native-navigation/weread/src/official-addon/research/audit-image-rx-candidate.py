"""Independent exact-payload and hook audit; read-only, never authorizes a device."""
import argparse,hashlib,json,struct,subprocess,zipfile
from pathlib import Path
import capstone
ROOT=Path(__file__).resolve().parents[2]
BASE=0x10190000
ORIGINAL='53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988'
def sha(b):return hashlib.sha256(b).hexdigest()
def audit(folder):
 folder=Path(folder);report=json.loads((folder/'report.json').read_text())
 assert report['kind'] in ('image-rx-r4-experimental-ota','ANIM60-offline-experimental-candidate','TMU1-offline-experimental-candidate')
 music=report['kind']=='TMU1-offline-experimental-candidate'
 animation=report['kind']=='ANIM60-offline-experimental-candidate' or music
 if animation:
  profile=report['animationProfile']
  assert (profile['width'],profile['height'],profile['sourceFrames'],profile['targetCanvasFPS'])==(192,176,1,0)
 native_eight=report.get('menuProfile')=='native-eight-v1'
 native_nine=report.get('menuProfile')=='native-nine-TDP1-and-TNV1'
 native_ten=report.get('menuProfile')=='native-ten-TDP1-TNV1-TMU1'
 assert native_ten==music
 native_carousel=native_eight or native_nine or native_ten
 baseline=ROOT/'firmware-inspection/StrixOS-1.0.4.12'
 old=(baseline/'nuttx_ap.bin').read_bytes();assert sha(old)==ORIGINAL
 new=(folder/'payload/nuttx_ap.bin').read_bytes();assert sha(new)==report['candidateAP']
 display=bool(report.get('displayProfile'))
 if display:
  arm=json.loads((folder/'arm-integration.json').read_text())
  assert arm['apSHA256']==sha(new) and arm['candidateAPExecuted']
  assert all(arm[k] for k in ['registeredFileCallback','deepCopyThenLauncherDispatch','foreignMessageForwarded','noPageReply','frameMatched','busyRetirementDeferred','freedOnce'])
 else:
  arm=json.loads((folder/'image-rx-arm.json').read_text())
  assert arm['apSHA256']==sha(new) and len(arm['scenarios'])==4
  assert arm['scenarios'][0]['lateRXRejected'] and arm['scenarios'][0]['parentDeleteBeforeIdle']
 if native_eight:
  menu=json.loads((folder/'menu8-native-arm.json').read_text())
  assert menu['apSHA256']==sha(new) and menu['realWheelMath'] and len(menu['scenarios'])==19
  assert all(s['passed'] and s['nativeWheelIndex7'] and s['smallDeltaStable'] and s['eighthNeverLaunchesDND'] and s['tailCanary'] for s in menu['scenarios'])
 if native_nine:
  menu=json.loads((folder/'menu9-native-arm.json').read_text());service=json.loads((folder/'navigation-service-arm.json').read_text())
  assert menu['apSHA256']==sha(new) and len(menu['scenarios'])==31 and menu['realWheelMath']
  assert all(s['passed'] and s['nativeWheelIndex8'] and s['ninthMenuDistinct'] and s['originalArrayPointersPreserved'] and s['tailCanary'] for s in menu['scenarios'])
  assert service['passed'] and service['AP']==sha(new) and service['noHeapLeaks']
 if native_ten:
  menu=json.loads((folder/'menu10-native-arm.json').read_text())
  assert menu['apSHA256']==sha(new) and len(menu['scenarios'])==44 and menu['realWheelMath']
  assert all(s['passed'] and s['nativeWheelIndex9'] and s['tenthMenuDistinct'] and s['originalArrayPointersPreserved'] and s['tailCanary'] and s['destroyNoDoubleFree'] for s in menu['scenarios'])
  service=json.loads((folder/'navigation-service-arm.json').read_text())
  assert service['passed'] and service['AP']==sha(new) and service['noHeapLeaks']
  service=json.loads((folder/'music-service-arm.json').read_text())
  assert service['AP']==sha(new) and all(service[k] for k in ['passed','noHeapLeaks','fiveLyricRows','currentAlwaysMiddle','seekAndEdgePadding','menuResumeUplink','coverAndLyrics','fixedScreenDeadline','physicalExitDoesNotReopen','busyDMADeferred','duplicateOpenDoesNotWake','controls'])
 assert len(new)<=0x9f0000 and new[:16]==old[:16] and new[-8:]==old[-8:]
 assert report['moduleOffset']=='0x9072c0' and report['moduleVA']=='0x10a972c0'
 module_at=int(report['moduleOffset'],16)
 blob=(folder/'generated/module.bin').read_bytes()
 assert new[module_at:module_at+len(blob)]==blob
 assert new[len(old)-8:module_at]==bytes(module_at-(len(old)-8))
 assert new[module_at+len(blob):-8]==bytes(len(new)-8-module_at-len(blob))
 syms={}
 for line in subprocess.check_output(['llvm-nm','--defined-only','--format=posix',str(folder/'generated/menu8-experiment.elf')],text=True).splitlines():
  p=line.split()
  if len(p)>=3:syms[p[0]]=int(p[2],16)
 assert not subprocess.check_output(['llvm-nm','-u',str(folder/'generated/menu8-experiment.elf')]).strip()
 if animation:
  start=syms['ta_asset']-BASE;size=192*176
  assert start%64==0 and len(new[start:start+size])==size
  original_asset=ROOT/'official-addon/research/animation-runtime-v1/assets/encoded-v1/anime-idle-192x176-l8.bin'
  assert sha(original_asset.read_bytes())=='f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d'
  assert new[start:start+size]==original_asset.read_bytes()[:size]
  assert sha(new[start:start+size])==profile['assetSHA256']
  assert arm['animationSubmissionsInEmulatedSecond']==0 and arm['initialStillSubmission'] and arm['embeddedAssetReadback']
 md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);md.detail=True
 allowed=set();patches=[]
 def branch(at,target,n,kind):
  encoded=new[at-BASE:at-BASE+n];inst=next(md.disasm(encoded,at))
  assert inst.mnemonic==kind and inst.size==4 and inst.operands[0].imm==(syms[target]&~1)
  assert encoded[4:]==b'\x00\xbf'*((n-4)//2)
  allowed.update(range(at-BASE,at-BASE+n));patches.append({'address':hex(at),'bytes':n,'target':target})
 wrappers=[('show',0x1079a784,4),('hide',0x1079a7b8,4),('destroy',0x10799660,4),('wheel',0x1079a310,6),('event',0x1079a890,4),('message',0x106eba90,4)]
 if native_carousel:wrappers += [('names',0x10799dec,4),('dots',0x107998b8,4),('delete_dots',0x10799896,4),('lottie',0x10799c58,4),('app_id',0x10799838,4),('refresh_label',0x10799c1a,4)]
 if native_nine or native_ten:wrappers += [('vm_event',0x107a1dd0,4)]
 for name,at,n in wrappers:
  branch(at,'m8_hook_'+name,n,'b.w')
  trampoline=(syms['stock_'+name]&~1)-BASE
  assert new[trampoline:trampoline+n]==old[at-BASE:at-BASE+n]
  i=next(md.disasm(new[trampoline+n:trampoline+n+4],BASE+trampoline+n))
  assert i.mnemonic=='b.w' and i.operands[0].imm==at+n
 if native_carousel:
  for name,at in [('frame_start',0x1079911a),('frame_index',0x10799130),('label_frame',0x1079a01c),('label_index',0x1079a484),('indicator',0x10799a44),('frame',0x10799d38)]:
   branch(at,'m8_hook_'+name,4,'b.w')
  bounds=[(0x1079a2b8,'f1ee087a','f1ee0c7a'),(0x107992f0,'efeece40','efeeee40'),(0x10799328,'efeece40','efeeee40'),(0x10799d90,'d129','ef29'),(0x10799d94,'d121','ef21')]
  if native_nine or native_ten:
   branch(0x10799d6e,'m8_hook_render_slide',4,'b.w')
   bounds=[(0x1079a2b8,'f1ee087a','f2ee007a'),(0x107992f0,'efeece40',struct.pack('<f',8.4666667).hex()),(0x10799328,'efeece40',struct.pack('<f',8.4666667).hex())]
   if native_ten:bounds=[(0x1079a2b8,'f1ee087a','f2ee027a'),(0x107992f0,'efeece40',struct.pack('<f',9.4666667).hex()),(0x10799328,'efeece40',struct.pack('<f',9.4666667).hex())]
  for at,before,after in bounds:
   before,after=bytes.fromhex(before),bytes.fromhex(after)
   assert old[at-BASE:at-BASE+len(before)]==before and new[at-BASE:at-BASE+len(after)]==after
   allowed.update(range(at-BASE,at-BASE+len(after)));patches.append({'address':hex(at),'bytes':len(after),'kind':'native-eight boundary'})
 branch(0x1079fe3c,'m8_hook_ctor',4,'bl')
 branch(0x106d9d1a,'stream_register_shim',10,'bl')
 assert old[0x1079fe2c-BASE:0x1079fe2e-BASE]==bytes.fromhex('dc20')
 assert new[0x1079fe2c-BASE:0x1079fe2e-BASE]==bytes.fromhex('fc20')
 allowed.update(range(0x1079fe2c-BASE,0x1079fe2e-BASE))
 changed=[i for i in range(len(old)-8) if old[i]!=new[i]]
 assert set(changed)<=allowed
 orig_manifest=json.loads((baseline/'OtaFileInfo.json').read_text())
 rows=json.loads((folder/'payload/OtaFileInfo.json').read_text())
 assert len(rows)==14 and len({r['Name'] for r in rows})==14
 identities=[]
 for before,after in zip(orig_manifest,rows):
  assert before['Name']==after['Name'] and set(before)==set(after)
  name=after['Name'];assert Path(name).name==name
  b=(folder/'payload'/name).read_bytes();o=(baseline/name).read_bytes()
  assert len(b)==after['Size'] and hashlib.md5(b).hexdigest()==after['Md5']
  if name!='nuttx_ap.bin':assert o==b and before==after
  else:assert all(before[k]==after[k] for k in before if k not in ['Size','Md5'])
  identities.append({'name':name,'unchanged':o==b,'sha256':sha(b),'md5':after['Md5'],'bytes':len(b)})
 archive=folder/report['archive']['name'];assert sha(archive.read_bytes())==report['archive']['sha256']
 with zipfile.ZipFile(archive) as z:
  expected=['OtaFileInfo.json']+[r['Name'] for r in rows]
  assert z.namelist()==expected and z.testzip() is None
  for n in expected:assert z.read(n)==(folder/'payload'/n).read_bytes()
 assert sum(r['unchanged'] for r in identities)==13
 return {'audit':'AP-only TDP1' if display else 'AP-only Image RX R4','menuProfile':report.get('menuProfile'),'passed':True,'deviceIO':False,
  'candidateAP':sha(new),'archiveSHA256':sha(archive.read_bytes()),'apGrowthBytes':len(new)-len(old),
  'modifiedExistingBytes':len(changed),'patches':patches,'unchangedPayloads':13,'payloads':identities,
  'readyToFlash':False,'reason':'This audit verifies bytes, not phone delivery or full runtime acceptance.'}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('--out',type=Path);a=p.parse_args()
 r=audit(a.candidate)
 if a.out:
  with a.out.open('x') as f:json.dump(r,f,indent=2)
 print(json.dumps({k:v for k,v in r.items() if k not in ['patches','payloads']}))
