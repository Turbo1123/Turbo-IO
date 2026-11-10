"""Independent byte-level audit for the TAP1 candidate; read-only, never authorizes a device.

Run inside the built snapshot tree after build-tap1.sh step 3 (menu8_native_profile.py
must sit next to this file; the shared venv provides capstone):
  python audit-tap1-candidate.py <candidate-folder> [--out audit.json]
The candidate folder is $OUT/official-addon/research/candidate; the baseline tree is
located relative to it, so the audit never depends on the caller's working directory.
"""
import argparse,hashlib,json,struct,subprocess,zipfile
from pathlib import Path
import capstone
import menu10_profile as native_menu  # mirrors build-tap1.sh: nav_* aliases, vm_event, 12-item springs

BASE=0x10190000
CAPACITY=0x9f0000
AP_SHA='53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988'
HOOKS=[('show',0x1079a784,4),('hide',0x1079a7b8,4),('destroy',0x10799660,4),
       ('wheel',0x1079a310,6),('event',0x1079a890,4),('message',0x106eba90,4),
       ('dc_text',0x108567c8,4)]  # dc_text is the TAP1 addition; TCE1 lives in editor_native.c
ALLOC_AT=0x1079fe2c
CTOR_AT=0x1079fe3c
SHIM_AT=0x106d9d1a
PINNED_SOURCES=['focus-v1/focus_menu.c','focus-v1/focus_menu_native.c',
                'music-runtime-v1/menu10.c','navigation-runtime-v1/nav_view.c']
FORBIDDEN_SUBSTRINGS=('didi-v1','app-runtime-v1','dashboard-v1')

def sha(b):return hashlib.sha256(b).hexdigest()

def audit(folder):
 folder=Path(folder).resolve();root=folder.parents[2]
 report=json.loads((folder/'report.json').read_text())
 assert report['kind']=='TAP1-developer-runtime-experimental-candidate','unexpected kind'
 assert report['menuProfile']=='native-twelve-TAP1','unexpected menu profile'
 assert report['focusProfile']['menuIndex']==11,'unexpected focus slot'
 fw=root/'firmware-inspection/StrixOS-1.0.4.12'
 old=(fw/'nuttx_ap.bin').read_bytes();assert sha(old)==AP_SHA==report['originalAP']
 new=(folder/'payload/nuttx_ap.bin').read_bytes()
 assert sha(new)==report['candidateAP'] and len(new)==report['candidateAPBytes']
 assert len(new)<=CAPACITY and len(new)<=10_000_000
 assert new[:16]==old[:16] and new[-8:]==old[-8:]
 footer=len(old)-8;module_at=(footer+31)&~31
 assert module_at==int(report['moduleOffset'],16)==0x9072c0
 assert BASE+module_at==int(report['moduleVA'],16)
 blob=(folder/'generated/module.bin').read_bytes();assert len(blob)==report['moduleBytes']
 assert new[module_at:module_at+len(blob)]==blob
 assert new[footer:module_at]==bytes(module_at-footer)
 assert new[module_at+len(blob):len(new)-8]==bytes(len(new)-8-module_at-len(blob))
 build_at=struct.unpack_from('<I',old,12)[0]-0x30190000
 assert new[build_at:footer]==old[build_at:footer]
 allowed=set();roles=set()
 for r in report['changes']:
  at=int(r['offset'],16);n=r['length']
  assert r['before']==old[at:at+n].hex() and r['after']==new[at:at+n].hex()
  allowed.update(range(at,at+n));roles.add(r['role'])
 changed=[i for i in range(footer) if old[i]!=new[i]]
 assert set(changed)<=allowed
 expected_roles={'AppList allocation 220 to 252',
  'Launcher NULL file callback becomes copied image receiver',
  'Initialize tail after original constructor'}
 expected_roles|={'Entry trampoline '+n for n,_,_ in HOOKS+native_menu.WRAPPERS}
 expected_roles|={'Native eight-slot method '+n for n,_,_ in native_menu.REPLACEMENTS}
 expected_roles|={role for _,_,_,role in native_menu.PATCHES}
 assert roles==expected_roles,(roles^expected_roles)
 elf=folder/'generated/menu8-experiment.elf'
 assert not subprocess.check_output(['llvm-nm','-u',elf]).strip(),'undefined symbols'
 syms={}
 for line in subprocess.check_output(['llvm-nm','--defined-only','--format=posix',elf],text=True).splitlines():
  p=line.split()
  if len(p)>=3:syms[p[0]]=int(p[2],16)
 assert syms['__module_start']==BASE+module_at and syms['__module_end']-syms['__module_start']==len(blob)
 md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);md.detail=True
 for name,at,n in HOOKS+native_menu.WRAPPERS:
  entry=new[at-BASE:at-BASE+n]
  inst=next(md.disasm(entry[:4],at))
  assert inst.mnemonic=='b.w' and inst.operands[0].imm==(syms['m8_hook_'+name]&~1)
  assert entry[4:]==b'\x00\xbf'*((n-4)//2)
  tramp=(syms['stock_'+name]&~1)-BASE  # file offset into the flat AP image
  assert new[tramp:tramp+n]==old[at-BASE:at-BASE+n]
  back=next(md.disasm(new[tramp+n:tramp+n+4],(syms['stock_'+name]&~1)+n))
  assert back.mnemonic=='b.w' and back.operands[0].imm==at+n
 for name,at,n in native_menu.REPLACEMENTS:
  inst=next(md.disasm(new[at-BASE:at-BASE+4],at))
  assert inst.mnemonic=='b.w' and inst.operands[0].imm==(syms['m8_hook_'+name]&~1)
 for at,before,after in [(p[0],p[1],p[2]) for p in native_menu.PATCHES]:
  assert old[at-BASE:at-BASE+len(bytes.fromhex(before))]==bytes.fromhex(before)
  assert new[at-BASE:at-BASE+len(bytes.fromhex(after))]==bytes.fromhex(after)
 inst=next(md.disasm(new[CTOR_AT-BASE:CTOR_AT-BASE+4],CTOR_AT))
 assert inst.mnemonic=='bl' and inst.operands[0].imm==(syms['m8_hook_ctor']&~1)
 assert old[ALLOC_AT-BASE:ALLOC_AT-BASE+2]==bytes.fromhex('dc20')
 assert new[ALLOC_AT-BASE:ALLOC_AT-BASE+2]==bytes.fromhex('fc20')
 manifest=json.loads((folder/'payload/OtaFileInfo.json').read_text())
 assert len(manifest)==14 and len({r['Name'] for r in manifest})==14
 unchanged=0
 for row in manifest:
  name=row['Name'];assert Path(name).name==name
  b=(folder/'payload'/name).read_bytes();o=(fw/name).read_bytes()
  # Md5 is the stock OTA manifest protocol field (device-side format), not a
  # security primitive; SHA-256 of every payload is recorded in the audit result.
  assert len(b)==row['Size'] and hashlib.md5(b).hexdigest()==row['Md5']
  if name!='nuttx_ap.bin':assert b==o
  unchanged+=b==o
 assert unchanged==13==report['unchangedPayloads']
 archive=folder/report['archive']['name']
 assert sha(archive.read_bytes())==report['archive']['sha256']
 with zipfile.ZipFile(archive) as z:
  expected=['OtaFileInfo.json']+[r['Name'] for r in manifest]
  assert z.namelist()==expected and z.testzip() is None
  for n in expected:assert z.read(n)==(folder/'payload'/n).read_bytes()
 inputs={i['path']:i['sha256'] for i in report['sourceInputs']}
 for banned in FORBIDDEN_SUBSTRINGS:
  assert not any(banned in p for p in inputs),'removed module leaked into build: '+banned
 for rel in PINNED_SOURCES:
  key='official-addon/research/'+rel
  assert key in inputs,'missing pinned source '+key
  assert sha((root/key).read_bytes())==inputs[key],'source drifted from pinned snapshot: '+key
 assert all(report['checks'].values())
 return {'audit':'AP-only TAP1 (twelve menu, no didi/app-runtime/dashboard-v1)',
  'kind':report['kind'],'menuProfile':report['menuProfile'],'passed':True,'deviceIO':False,
  'candidateAP':sha(new),'archiveSHA256':sha(archive.read_bytes()),
  'apGrowthBytes':len(new)-len(old),'modifiedExistingBytes':len(changed),
  'patchRoles':sorted(roles),'pinnedSources':PINNED_SOURCES,'unchangedPayloads':13,
  'readyToFlash':False,
  'reason':'Bytes, branches, manifest, archive and pinned sources verified; runtime still needs cloud-Mac ARM emulation plus on-device acceptance.'}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('--out',type=Path)
 a=p.parse_args();r=audit(a.candidate)
 if a.out:
  with a.out.open('x') as f:json.dump(r,f,indent=2)
 print(json.dumps({k:v for k,v in r.items() if k!='patchRoles'}))
