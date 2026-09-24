"""Execute linked NEW display/page ARM code with mocked LVGL/OS/RNLink.
Loads pristine AP and module into emulator memory only. No device or OTA IO.
"""
import argparse, base64, hashlib, json, struct, subprocess, zlib
from pathlib import Path
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3, UC_ARM_REG_SP, UC_ARM_REG_LR, UC_ARM_REG_PC
p=argparse.ArgumentParser();p.add_argument('link',type=Path);p.add_argument('--candidate',action='store_true');p.add_argument('--phone-trace',type=Path);a=p.parse_args();d=a.link
root=Path(__file__).resolve().parents[3];fw=root/'firmware-inspection/StrixOS-1.0.4.12'
ap=(fw/'nuttx_ap.bin').read_bytes();assert hashlib.sha256(ap).hexdigest()=='53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988'
if a.candidate:
 report=json.loads((d/'report.json').read_text());assert report['displayProfile']['protocol']=='TDP1'
 ap=(d/'payload/nuttx_ap.bin').read_bytes();assert hashlib.sha256(ap).hexdigest()==report['candidateAP']
 elf=d/'generated/menu8-experiment.elf';blob=d/'generated/module.bin'
else:
 elf=d/'display-native-LINK-ONLY.elf';report=json.loads((d/'link-receipt.json').read_text());assert hashlib.sha256(elf.read_bytes()).hexdigest()==report['elfSha256']
 blob=d/'emulator-module-NOT-FIRMWARE.bin'
animation=bool(report.get('animationProfile'));animation_frames=0
if not blob.exists():subprocess.run(['llvm-objcopy','-O','binary',str(elf),str(blob)],check=True)
symbols={}
for row in subprocess.check_output(['llvm-nm','--defined-only','--format=posix',str(elf)],text=True).splitlines():
 fields=row.split()
 if len(fields)>=3:symbols[fields[0]]=int(fields[2],16)
u=Uc(UC_ARCH_ARM,UC_MODE_THUMB|UC_MODE_MCLASS)
for low,n in [(0x10000000,0x1000000),(0x18000000,0x4000000),(0x20000000,0x300000),(0x100000,0x100000),(0x23c00000,0x100000)]:u.mem_map(low,n)
u.mem_write(0x10190000,ap)
for low,high,at in json.loads((fw/'symbols.json').read_text())['segments']:u.mem_write(low,ap[at:at+high-low])
if a.candidate:assert bytes(u.mem_read(symbols['__module_start'],len(blob.read_bytes())))==blob.read_bytes()
else:u.mem_write(symbols['__module_start'],blob.read_bytes())
REGS=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3]
STOP=0x10000100;SP=0x202f0000;PARENT=0x20001000;APP=0x20020000;OWNER=APP+0xec;WIRE=0x20010000;PAGE=0x20030000;TIMER=0x20080000
FILE=0x20012000;QUEUE=0x20014000;QUEUED_DATA=0x20015000;queued=0;forwarded=0
now=1000;timer=False;freed=0;bound=0;last_reply=None;replies=0;objects={PARENT:{}};next_object=0x20090000
def word(p):return struct.unpack('<I',u.mem_read(p,4))[0]
def put(p,v):u.mem_write(p,struct.pack('<I',v))
put(0x18617b8c+0x124,0x18001000);put(0x18001000+12,0x1057dff1)
put(0x18001000,0);put(0x18001000+24,0);put(0x18002000+0x2a0,0)
def r(i):return u.reg_read(REGS[i])
def ret(v=0):u.reg_write(UC_ARM_REG_R0,v&0xffffffff);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
def cstring(p):
 b=bytes(u.mem_read(p,128));return b.split(b'\0',1)[0].decode()
def parse_reply(data):
 assert data[:5]==bytes([8,1,16,6,26]);n=(data[5]&127)|(data[6]<<7);assert len(data)==7+n
 j=json.loads(data[7:]);assert j['cmd']=='turbo_display_v1' and j['payload']['value']==j['payload']['mode']==0
 b=bytes.fromhex(j['payload']['data']);assert len(b)==40 and b[:5]==b'TDR1\1'
 assert zlib.crc32(b[:36])==struct.unpack_from('<I',b,36)[0]
 return dict(result=b[5],sid=struct.unpack_from('<I',b,8)[0],request=struct.unpack_from('<I',b,12)[0],revision=struct.unpack_from('<I',b,16)[0])
mocks={symbols[n]&~1:n for n in symbols if n.startswith(('stream_','tio_lv_','native_'))}
mocks.pop(symbols['stream_register_shim']&~1,None)
mocks[symbols['stock_message']&~1]='stock_message'
mocks[symbols['tdp_rnlink_send']&~1]='send';mocks[symbols['memcpy']&~1]='memcpy';mocks[symbols['memset']&~1]='memset';mocks[symbols['memcmp']&~1]='memcmp'
def hook(_u,addr,size,data):
 global now,timer,freed,bound,last_reply,replies,next_object,queued,forwarded,animation_frames
 if addr==STOP:u.emu_stop();return
 name=mocks.get(addr)
 if not name:return
 if name=='memcpy':u.mem_write(r(0),bytes(u.mem_read(r(1),r(2))));ret(r(0))
 elif name=='memset':u.mem_write(r(0),bytes([r(1)&255])*r(2));ret(r(0))
 elif name=='memcmp':ret(0 if u.mem_read(r(0),r(2))==u.mem_read(r(1),r(2)) else 1)
 elif name=='stream_memalign':assert r(0)==64 and r(1)<=(132000 if animation else 131264);ret(PAGE)
 elif name=='stream_free':assert r(0)==PAGE and not word(0x18001000+24) and not bound;freed+=1;ret()
 elif name=='stream_tick':ret(now)
 elif name=='stream_timer_create':assert not timer;timer=True;put(TIMER+8,r(0));put(TIMER+12,r(2));ret(TIMER)
 elif name=='stream_timer_next':ret(TIMER if timer and not r(0) else 0)
 elif name=='stream_timer_period':assert animation and timer and r(0)==TIMER and r(1)==100;ret()
 elif name=='stream_timer_delete':assert timer and r(0)==TIMER;timer=False;ret()
 elif name=='stream_display_next':ret(0 if r(0) else 0x18002000)
 elif name=='stream_stride':assert r(1)==6;ret(r(0))
 elif name in ('tio_lv_obj_create_ex','stream_canvas_create','native_label_create'):
  assert r(0) in objects;obj=next_object;next_object+=256;objects[obj]={'parent':r(0)};ret(obj)
 elif name=='tio_lv_obj_get_width':ret(540)
 elif name=='tio_lv_obj_get_height':ret(280)
 elif name=='stream_add_event':objects[r(0)]['callback']=r(1);objects[r(0)]['user']=r(3);ret(r(0))
 elif name=='stream_event_user':ret(objects[r(0)]['user'])
 elif name=='stream_queue_send':
  assert r(0)==1;message=bytearray(u.mem_read(r(1),24));at=struct.unpack_from('<I',message,4)[0];n=struct.unpack_from('<I',message,8)[0]
  assert 32<=n<=512 and message[20:24]==bytes(4)
  u.mem_write(QUEUED_DATA,bytes(u.mem_read(at,n)));struct.pack_into('<I',message,4,QUEUED_DATA);u.mem_write(QUEUE,bytes(message));queued+=1;ret()
 elif name=='stock_message':forwarded+=1;ret()
 elif name=='stream_canvas_set_buffer':
  assert r(0) in objects
  assert (r(2),r(3))==(512,128) or (animation and (r(2),r(3))==(192,176))
  if r(2)==192:animation_frames+=1
  bound=r(1);ret()
 elif name=='tio_lv_obj_delete':
  root_object=r(0);children={root_object}|{k for k,v in objects.items() if v.get('parent')==root_object}
  for key in children:del objects[key]
  bound=0;ret()
 elif name=='send':assert r(0)==15 and r(3)==0;last_reply=parse_reply(bytes(u.mem_read(r(1),r(2))));replies+=1;ret(0)
 elif name=='native_label_text':assert 'SID' in cstring(r(1)) or (animation and cstring(r(1)).startswith('Turbo Display'));ret()
 elif name in ('native_report_activity','native_log','stream_invalidate','native_text_color','native_align') or name.startswith('tio_lv_obj_'):ret()
 else:raise AssertionError('Unmocked native service '+name)
u.hook_add(UC_HOOK_CODE,hook)
def call(name,*args):
 u.reg_write(UC_ARM_REG_SP,SP);u.reg_write(UC_ARM_REG_LR,STOP|1)
 for reg,value in zip(REGS,args):u.reg_write(reg,value)
 u.emu_start((symbols[name] if isinstance(name,str) else name)|1,STOP,count=5000000)
 assert u.reg_read(UC_ARM_REG_PC)==STOP and u.reg_read(UC_ARM_REG_SP)==SP
 return u.reg_read(UC_ARM_REG_R0)
call('stream_register_shim');assert word(0x19750d2c)==0x106d97f1
file_callback=word(0x19750d2c+0x18);assert file_callback==(symbols['tio_hook_file']|1)
put(0x19a1f954,0x20021000);put(0x20021000+0x3c,0x20022000);put(0x20022000+0x10,APP)
assert call('tdp_native_open',PARENT,7392,OWNER)==PAGE and word(OWNER)==PAGE
assert last_reply==dict(result=0,sid=7392,request=0,revision=0)
if animation:
 assert animation_frames==1
 for _ in range(200):now+=5;call(word(TIMER+8),TIMER)
 assert animation_frames==1,'Still image must not repaint after its initial submission'
 # The image is resident in the AP, not filled by a phone upload.
 assert bytes(u.mem_read(bound,192*176))==bytes(u.mem_read(symbols['ta_asset'],192*176))
held=bytes(u.mem_read(bound,16))
request=0
def raw_packet(raw):
 assert len(raw)<=512;u.mem_write(WIRE,raw)
 file=bytearray(336);struct.pack_into('<II',file,0,WIRE,len(raw));file[8:26]=b'turbo-display.tdp\0';file[329]=1;struct.pack_into('<I',file,332,len(raw));u.mem_write(FILE,bytes(file))
 before=queued;call(file_callback,FILE);assert queued==before+1
 u.mem_write(WIRE,bytes(len(raw))) # original callback buffer can disappear
 before=replies;call(0x106eba90 if a.candidate else 'm8_hook_message',0,QUEUE);assert replies==before+1
 assert last_reply['request']==struct.unpack_from('<I',raw,12)[0]
 return last_reply['result']
def packet(op,payload=b'',base=0):
 global request,now
 request+=1;now+=120
 h=b'TDP1'+bytes([1,op,0,0])+struct.pack('<IIIIII',0 if op==1 else 7392,request,base,base+int(op>=5 or op==2),len(payload),zlib.crc32(payload))
 return raw_packet(h+payload)
assert packet(1)==0
frame=bytes([153])*65536
assert packet(5,struct.pack('<III',1,65536,zlib.crc32(frame)))==9
for at in range(0,len(frame),472):assert packet(6,struct.pack('<II',1,at)+frame[at:at+472])==9
assert bytes(u.mem_read(bound,16))==held
assert packet(7,struct.pack('<I',1))==1
assert bytes(u.mem_read(bound,len(frame)))==frame and last_reply['revision']==1
put(0x18001000+24,1);call('tdp_native_retire',PAGE);assert not word(OWNER)
call(word(TIMER+8),TIMER);assert not freed and timer
put(0x18001000+24,0);now+=200;call(word(TIMER+8),TIMER)
assert freed==1 and not timer and set(objects)=={PARENT}
# No-page negative reply follows the same registered file + Launcher dispatcher.
assert packet(1)==5 and last_reply['sid']==0
# Foreign messages still follow the stock handler, no reinterpretation.
put(QUEUE,0x1234);before=forwarded;call(0x106eba90 if a.candidate else 'm8_hook_message',0,QUEUE);assert forwarded==before+1
result={'scope':'NEW linked ARM protocol/page; native LVGL/OS/RNLink MOCKS','deviceIO':False,
        'apSHA256':hashlib.sha256(ap).hexdigest(),'candidateAPExecuted':a.candidate,
        'registeredFileCallback':True,'deepCopyThenLauncherDispatch':True,'foreignMessageForwarded':True,'noPageReply':True,
        'SID':7392,'replyCount':replies,'fullFrameBytes':len(frame),'chunkBytesMax':472,
        'frameMatched':True,'busyRetirementDeferred':True,'freedOnce':True}
if animation:result.update(animationTargetFPS=0,animationSubmissionsInEmulatedSecond=0,initialStillSubmission=True,embeddedAssetReadback=True,physicalFPSMeasured=False)
if a.phone_trace:
 trace=json.loads(a.phone_trace.read_text());assert trace['syntheticOnly'] and trace['sid']==7392
 assert len(trace['packets'])==145
 assert call('tdp_native_open',PARENT,7392,OWNER)==PAGE
 expected_frame=base64.b64decode(trace['frame'],validate=True);assert len(expected_frame)==65536
 for entry in trace['packets']:
  now+=120;raw=base64.b64decode(entry['packet'],validate=True)
  expected={1:0,2:1,3:2,4:3,5:9,6:9,7:1}[raw[5]]
  assert raw_packet(raw)==expected
  if raw[5]==7:assert bytes(u.mem_read(bound,65536))==expected_frame
 assert last_reply['sid']==0 and last_reply['revision']==2
 now+=120;call(word(TIMER+8),TIMER);assert freed==2 and not timer and not word(OWNER)
 result.update(phoneCoordinatorTracePackets=145,phoneCoordinatorFrameMatched=True,
   phoneCoordinatorTraceSHA256=hashlib.sha256(a.phone_trace.read_bytes()).hexdigest())
(d/'arm-integration.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
