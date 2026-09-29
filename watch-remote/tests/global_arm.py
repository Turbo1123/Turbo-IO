"""Execute the actual linked TGR1 ARM module with modeled OS/input/transport.
Not a device or radio test. Existing stock handler ownership is independently checked.
"""
import argparse,json,hashlib,struct,subprocess,zlib
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_THUMB,UC_MODE_MCLASS,UC_HOOK_CODE
from unicorn.arm_const import *
p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);a=p.parse_args();folder=a.candidate
b=(folder/'payload/nuttx_ap.bin').read_bytes();sha=hashlib.sha256(b).hexdigest()
assert json.loads((folder/'report.json').read_text())['candidateAP']==sha
syms={x[0]:int(x[2],16) for l in subprocess.check_output(['llvm-nm','--defined-only','--format=posix',str(folder/'generated/menu8-experiment.elf')],text=True).splitlines() if len(x:=l.split())>=3}
STOP=0x10000100;SP=0x203f0000;MSG=0x20001000;DATA=0x20002000;TOP=0x20003000;DRIVER=0x20004000;TIMER=0x20005000
REG=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3];checks=[]
def check(v,label):
 assert v,label
 checks.append(label)
def packet(op=0,seq=0,sid=0,tick=0,client=99):
 raw=bytearray(b'TGR1'+bytes([1,op,0,0])+struct.pack('<IIIII',123,sid,seq,tick,client));raw+=struct.pack('<I',zlib.crc32(raw));return b'\x08\x01\x10\x7f\x1a\x44TGR:'+raw.hex().encode()
class Run:
 def __init__(self):
  self.u=Uc(UC_ARCH_ARM,UC_MODE_THUMB|UC_MODE_MCLASS)
  for st,size in [(0x10000000,0x1000000),(0x18000000,0x4000000),(0x20000000,0x400000),(0x100000,0x100000)]:self.u.mem_map(st,size)
  self.u.mem_write(0x10190000,b);self.timer=None;self.now=1000;self.events=[];self.replies=[];self.heap=0x20100000;self.alloc={};self.ota=0;self.paired=True;self.folded=False;self.screen=True;self.intercept=False;self.keydev=True;self.encdev=True;self.fail=False;self.stock=0;self.nonce=7392
  self.u.mem_write(TOP,b'com.rayneo.liteos.launcher\0');self.u.hook_add(UC_HOOK_CODE,self.hook)
  self.mocks={syms[n]&~1:n for n in ['memcpy','memset','strcmp','stream_tick','stream_memalign','stream_free','stream_timer_next','stream_timer_create','nav_monitors','nav_input','nav_link','fm_system','tgr_ota_status','nav_bonded','nav_folded','nav_connection','nav_top_app','focus_screen_on','nav_screen_on','native_report_activity','tgr_indev_next','tgr_indev_type','tgr_indev_group','tgr_indev_driver','tgr_intercept','tgr_group_send','tgr_raw_wheel','tgr_sim_wheel','tdp_rnlink_send','tap_random','stock_message']}
 def word(self,p):return struct.unpack('<I',self.u.mem_read(p,4))[0]
 def put(self,p,v):self.u.mem_write(p,struct.pack('<I',v))
 def ret(self,v=0):self.u.reg_write(REG[0],v);self.u.reg_write(UC_ARM_REG_PC,self.u.reg_read(UC_ARM_REG_LR))
 def hook(self,u,addr,size,_):
  if addr==STOP:u.emu_stop();return
  n=self.mocks.get(addr)
  if not n:return
  r=[u.reg_read(x) for x in REG]
  if n=='memcpy':u.mem_write(r[0],bytes(u.mem_read(r[1],r[2])));self.ret(r[0])
  elif n=='memset':u.mem_write(r[0],bytes([r[1]&255])*r[2]);self.ret(r[0])
  elif n=='strcmp':self.ret(int(bytes(u.mem_read(r[0],80)).split(b'\0')[0]!=bytes(u.mem_read(r[1],80)).split(b'\0')[0]))
  elif n=='stream_tick':self.ret(self.now)
  elif n=='stream_memalign':
   if self.fail:self.ret();return
   start=self.heap;self.heap+=r[1]+128;self.alloc[start]=r[1];u.mem_write(start-16,b'\xa5'*16);u.mem_write(start+r[1],b'\xa5'*16);self.ret(start)
  elif n=='stream_free':assert r[0] in self.alloc;self.alloc.pop(r[0]);self.ret()
  elif n=='stream_timer_next':self.ret(TIMER if self.timer and not r[0] else 0)
  elif n=='stream_timer_create':assert r[1]==1000;self.timer=(r[0],r[2]);self.put(TIMER+8,r[0]);self.put(TIMER+12,r[2]);self.ret(TIMER)
  elif n in ('nav_monitors','nav_input','nav_link','fm_system'):self.ret(0x20008000)
  elif n=='tgr_ota_status':self.ret(self.ota)
  elif n in ('nav_bonded','nav_connection'):self.ret(int(self.paired))
  elif n=='nav_folded':self.ret(int(self.folded))
  elif n=='nav_top_app':self.ret(TOP)
  elif n=='focus_screen_on':self.ret(int(self.screen))
  elif n=='nav_screen_on':assert r[0]==1;self.events.append(('wake',));self.screen=True;self.ret()
  elif n=='native_report_activity':self.events.append(('activity',));self.ret()
  elif n=='tgr_indev_next':
   devices=([0x20009000] if self.keydev else [])+([0x20009100] if self.encdev else []);self.ret(devices[0] if not r[0] and devices else devices[devices.index(r[0])+1] if r[0] in devices and devices.index(r[0])+1<len(devices) else 0)
  elif n=='tgr_indev_type':self.ret(2 if r[0]==0x20009000 else 4)
  elif n=='tgr_indev_group':assert r[0]==0x20009000;self.ret(0x20009200)
  elif n=='tgr_indev_driver':assert r[0]==0x20009100;self.ret(DRIVER)
  elif n=='tgr_intercept':
   fields=struct.unpack('<7I',u.mem_read(r[0],28));assert fields[:4]==(0,0,14,0) and fields[5:]==(0,0);self.events.append(('intercept',self.word(fields[4])));self.ret(int(self.intercept))
  elif n=='tgr_group_send':assert r[0]==0x20009200 and r[1] in (0x3a,0x3b);self.events.append(('key',r[1]));self.ret()
  elif n=='tgr_raw_wheel':self.events.append(('raw',*struct.unpack('<iiQ',u.mem_read(r[0],16))));self.ret()
  elif n=='tgr_sim_wheel':self.events.append(('detent',struct.unpack('<i',struct.pack('<I',r[0]))[0]));self.ret()
  elif n=='tap_random':self.ret(self.nonce)
  elif n=='tdp_rnlink_send':
   assert r[0]==15 and r[2]==74 and r[3]==0;wire=bytes(u.mem_read(r[1],r[2]));assert wire[:10]==b'\x08\x01\x10\x7f\x1a\x44TGA:';raw=bytes.fromhex(wire[10:].decode());assert zlib.crc32(raw[:28])==struct.unpack_from('<I',raw,28)[0];self.replies.append(raw);self.ret()
  elif n=='stock_message':self.stock+=1;assert self.word(r[1])==1;self.ret()
 def call(self,name,*args):
  for reg,value in zip(REG,args):self.u.reg_write(reg,value)
  self.u.reg_write(UC_ARM_REG_SP,SP);self.u.reg_write(UC_ARM_REG_LR,STOP|1);self.u.emu_start(syms[name]|1,STOP,count=200000)
  check(self.u.reg_read(UC_ARM_REG_PC)==STOP,'bounded ARM execution '+name)
  for st,size in self.alloc.items():assert self.u.mem_read(st-16,16)==b'\xa5'*16 and self.u.mem_read(st+size,16)==b'\xa5'*16
 def send(self,wire,stock=False):
  self.u.mem_write(DATA,wire);msg=struct.pack('<5IB3x',1,DATA,len(wire),0,0,1);self.u.mem_write(MSG,msg)
  self.call('m8_hook_message' if stock else 'tgr_native_message',*( [0x20007000,MSG] if stock else [MSG]))
  check(bytes(self.u.mem_read(MSG,24))==msg and bytes(self.u.mem_read(DATA,len(wire)))==wire,'borrowed native ownership unchanged')
  return self.replies[-1][5] if self.replies else None
r=Run();check(r.send(packet(),True)==0 and r.stock==1,'real m8 wrapper preserves stock disposal');check(len(r.alloc)==1,'one bounded controller allocation')
for seq,op in enumerate([1,2,3,4],1):
 r.now+=500;r.events=[];check(r.send(packet(op,seq,7392,r.now),True)==0,'action accepted '+str(op))
 check(('detent',-1 if op==1 else 1) in r.events if op<3 else ('key',0x3a if op==3 else 0x3b) in r.events,'native action '+str(op))
 if op<3:check(('raw',600 if op==1 else -600,0,r.now*1000) in r.events,'native raw event ABI')
check(r.stock==5,'stock handler called exactly once per inbound message')
r.now+=500;r.events=[];check(r.send(packet(3,4,7392,r.now))==3 and not r.events,'duplicate cannot execute')
r.now+=500;r.screen=False;r.events=[];check(r.send(packet(3,5,7392,r.now))==1 and r.events==[('activity',),('wake',)],'offscreen wake only')
r.now+=500;r.intercept=True;r.events=[];check(r.send(packet(3,6,7392,r.now))==0 and ('key',0x3a) not in r.events,'global native interceptor wins')
for state in ['ota','folded','paired']:
 x=Run();x.send(packet());setattr(x,state,1 if state=='ota' else state=='folded');x.events=[];check(x.send(packet(3,1,7392,1000))==2 and not x.events,'blocked '+state)
for name in ['ota','mmitest','charger_box','unknown']:
 x=Run();x.u.mem_write(TOP,('com.rayneo.liteos.'+name+'\0').encode());check(x.send(packet())==2 and not x.events,'denied page '+name)
for name in ['recorder','prompter','aiSubtitle','conversationAssist','assistant','todo','notification']:
 x=Run();x.u.mem_write(TOP,('com.rayneo.liteos.'+name+'\0').encode());check(x.send(packet())==0,'supported native package '+name)
x=Run();x.fail=True;check(x.send(packet()) is None and not x.events,'allocation failure does not inject')
x=Run();x.send(packet());x.encdev=False;check(x.send(packet(2,1,7392,1000))==7,'missing encoder denied')
x=Run();x.send(packet());x.u.mem_write(DRIVER+6,b'\x01\x00');check(x.send(packet(2,1,7392,1000))==5,'pending native wheel not overwritten')
x=Run();x.send(packet());x.now=18000;check(x.send(packet(3,1,7392,18000))==4,'expired AP lease')
out={'passed':True,'AP':sha,'checks':checks,'physicalVerified':False,'radioVerified':False}
(folder/'global-remote-arm.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'passed':True,'checks':len(checks),'AP':sha}))
