"""Execute candidate TNV1 ARM service, LVGL adapter and runtime; OS is mocked.
No device or flash I/O. Does not claim hardware visibility or tear-free scanout.
"""
import argparse,hashlib,json,struct,subprocess,zlib,base64
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_THUMB,UC_MODE_MCLASS,UC_HOOK_CODE
from unicorn.arm_const import *
p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('--phone-trace',type=Path);a=p.parse_args();d=a.candidate
root=Path(__file__).resolve().parents[3];fw=root/'firmware-inspection/StrixOS-1.0.4.12'
report=json.loads((d/'report.json').read_text());ap=(d/'payload/nuttx_ap.bin').read_bytes()
assert hashlib.sha256(ap).hexdigest()==report['candidateAP']
symbols={r.split()[0]:int(r.split()[2],16) for r in subprocess.check_output(['llvm-nm','--defined-only','--format=posix',str(d/'generated/menu8-experiment.elf')],text=True).splitlines() if len(r.split())>=3}
u=Uc(UC_ARCH_ARM,UC_MODE_THUMB|UC_MODE_MCLASS)
for low,n in [(0x10000000,0x1000000),(0x18000000,0x4000000),(0x20000000,0x400000),(0x100000,0x100000),(0x23c00000,0x100000)]:u.mem_map(low,n)
u.mem_write(0x10190000,ap)
for low,high,at in json.loads((fw/'symbols.json').read_text())['segments']:u.mem_write(low,ap[at:at+high-low])
STOP=0x10000100;SP=0x203f0000;APP=0x20001000;VM=0x20002000;PARENT=0x20003000;LAUNCHER=0x20004000;WIRE=0x20010000;MSG=0x20011000;FILE=0x20012000;QUEUE=0x20014000;DATA=0x20015000;EVENT=0x20016000
REGS=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3]
def word(p):return struct.unpack('<I',u.mem_read(p,4))[0]
def put(p,v):u.mem_write(p,struct.pack('<I',v))
def text(p):return bytes(u.mem_read(p,256)).split(b'\0')[0].decode()
def r(i):return u.reg_read(REGS[i])
def ret(v=0):u.reg_write(UC_ARM_REG_R0,v&0xffffffff);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
put(0x19a1f954,LAUNCHER);put(LAUNCHER+0x3c,VM);put(VM+0x10,APP);put(APP+4,PARENT)
put(0x18617b8c+0x124,0x18001000);put(0x18001000+12,0x1057dff1)
put(0x18001000,0);put(0x18001000+24,0);put(0x18002000+0x2a0,0)
u.mem_write(0x20005000,b'com.rayneo.liteos.launcher\0')
now=1000;bond=True;fold=False;business=True;linked=True;fail_alloc=False;fail_power=False
heap=0x20100000;objnext=0x20040000;timernext=0x20070000
alloc={};freed=set();objects={PARENT:{}};timers={};tokens=set();replies=[];labels={};calls=[];queued=0;events=0;forwarded=0
mocks={symbols[n]&~1:n for n in symbols if n.startswith(('stream_','tio_lv_','native_'))}
mocks.pop(symbols['stream_register_shim']&~1,None)
for n in ['memcpy','memset','memcmp','menu_font','menu_text_font','nav_label_static','nav_always_on','nav_release_always_on','nav_screen_on','nav_force_off','nav_top_app','nav_monitors','nav_link','nav_input','nav_bonded','nav_folded','nav_business_idle','nav_connection','nav_ensure_menu','nav_set_state','nav_stop_event','tdp_rnlink_send','stock_vm_event','stock_message']:mocks[symbols[n]&~1]=n
def hook(_u,addr,size,data):
 global heap,objnext,timernext,queued,events,forwarded
 if addr==STOP:u.emu_stop();return
 n=mocks.get(addr)
 if not n:return
 if n=='memcpy':u.mem_write(r(0),bytes(u.mem_read(r(1),r(2))));ret(r(0))
 elif n=='memset':u.mem_write(r(0),bytes([r(1)&255])*r(2));ret(r(0))
 elif n=='memcmp':ret(0 if u.mem_read(r(0),r(2))==u.mem_read(r(1),r(2)) else 1)
 elif n=='stream_memalign':
  if fail_alloc:ret();return
  heap=(heap+r(0)-1)&~(r(0)-1);v=heap;heap+=r(1)+64;assert heap<0x20300000;alloc[v]=r(1);ret(v)
 elif n=='stream_free':assert r(0) in alloc and r(0) not in freed;freed.add(r(0));ret()
 elif n=='stream_tick':ret(now)
 elif n=='stream_timer_create':v=timernext;timernext+=64;timers[v]=(r(0),r(2));put(v+12,r(2));ret(v)
 elif n=='stream_timer_delete':assert r(0) in timers;del timers[r(0)];ret()
 elif n=='stream_display_next':ret(0 if r(0) else 0x18002000)
 elif n=='stream_stride':assert r(1)==6;ret(r(0))
 elif n in ('tio_lv_obj_create_ex','stream_canvas_create','native_label_create'):
  assert r(0) in objects;v=objnext;objnext+=256;objects[v]={'parent':r(0)};ret(v)
 elif n=='tio_lv_obj_get_width':ret(540)
 elif n=='tio_lv_obj_get_height':ret(280)
 elif n=='stream_add_event':objects[r(0)]['cb']=r(1);objects[r(0)]['user']=r(3);ret(r(0))
 elif n=='stream_event_user':ret(VM if r(0)==EVENT else objects[r(0)]['user'])
 elif n=='stream_canvas_set_buffer':assert r(2)==r(3)==128;objects[r(0)]['buffer']=r(1);ret()
 elif n=='tio_lv_obj_delete':
  assert not word(0x18001000+24);keys={r(0)}|{k for k,v in objects.items() if v.get('parent')==r(0)}
  for k in keys:objects.pop(k,None);labels.pop(k,None)
  ret() # Parent-driven callback is separately exercised below.
 elif n=='nav_label_static':labels[r(0)]=text(r(1));ret()
 elif n=='menu_font':assert r(0) in (16,18,20,32);ret(0x20006000)
 elif n=='nav_top_app':ret(0x20005000)
 elif n in ('nav_monitors','nav_link','nav_input'):ret(0x20008000)
 elif n=='nav_bonded':ret(bond)
 elif n=='nav_folded':ret(fold)
 elif n=='nav_business_idle':ret(business)
 elif n=='nav_connection':assert r(0)==0x80;ret(linked)
 elif n=='nav_ensure_menu':ret(APP)
 elif n=='nav_set_state':assert r(0)==VM and r(1)==1;put(VM+0x1c,1);calls.append('native_state_1');ret()
 elif n=='nav_always_on':assert text(r(0))=='turbo_nav_v1';tokens.add(7) if not fail_power else None;ret(0 if fail_power else 7)
 elif n=='nav_release_always_on':assert text(r(0))=='turbo_nav_v1' and r(1) in tokens;tokens.remove(r(1));ret()
 elif n=='nav_screen_on':assert r(0)==1;calls.append('wake');ret()
 elif n=='nav_force_off':assert not tokens;calls.append('sleep');ret()
 elif n=='native_event_code':ret(0xe)
 elif n=='native_event_key':ret(word(EVENT))
 elif n=='nav_stop_event':events+=1;ret()
 elif n=='stock_vm_event':forwarded+=1;ret()
 elif n=='stock_message':forwarded+=1;ret()
 elif n=='stream_queue_send':
  assert r(0)==1;msg=bytearray(u.mem_read(r(1),24));at,count=struct.unpack_from('<II',msg,4);assert 32<=count<=512
  u.mem_write(DATA,bytes(u.mem_read(at,count)));struct.pack_into('<I',msg,4,DATA);u.mem_write(QUEUE,bytes(msg));queued+=1;ret()
 elif n=='tdp_rnlink_send':
  assert r(0)==15 and r(3)==0;b=bytes(u.mem_read(r(1),r(2)));assert b[:5]==bytes([8,1,16,6,26]) and b[5]<128 and len(b)==6+b[5]
  j=json.loads(b[6:]);assert j['cmd']=='turbo_nav_v1';ack=bytes.fromhex(j['payload']['data']);assert len(ack)==32 and ack[:5]==b'TNA1\1' and zlib.crc32(ack[:28])==struct.unpack_from('<I',ack,28)[0];replies.append(ack);ret()
 elif n in ('menu_text_font','native_align','native_text_color','stream_invalidate','native_report_activity','native_log') or n.startswith('tio_lv_obj_'):ret()
 else:raise AssertionError('unmocked '+n)
u.hook_add(UC_HOOK_CODE,hook)
def call(name,*args):
 u.reg_write(UC_ARM_REG_SP,SP);u.reg_write(UC_ARM_REG_LR,STOP|1)
 for reg,v in zip(REGS,args):u.reg_write(reg,v)
 u.emu_start((symbols[name] if isinstance(name,str) else name)|1,STOP,count=15000000)
 assert u.reg_read(UC_ARM_REG_PC)==STOP and u.reg_read(UC_ARM_REG_SP)==SP
 return u.reg_read(UC_ARM_REG_R0)
def tick(dt):
 global now
 now+=dt
 for timer,(cb,ctx) in list(timers.items()):call(cb,timer)
slot=call('tn_slot_create',APP);assert slot;put(APP+0xdc+28,slot)
call('stream_register_shim');callback=word(0x19750d2c+0x18)
def packet(op,sid,seq,mode=0):
 road='测试路'.encode();turn='前方右转'.encode()
 payload=bytes([3,3,mode,0])+struct.pack('<IIIHHHBB',80,1200,600,90,100,900,len(road),len(turn))+road+turn+struct.pack('<HHHHHH',100,900,100,500,900,500) if op in (1,2) else bytes([mode]) if op==5 else b''
 b=bytearray(b'TNV1'+bytes([1,op,0,0])+struct.pack('<IIIIII',sid,seq,len(payload),0,0,0)+payload);struct.pack_into('<I',b,20,zlib.crc32(b));return bytes(b)
def send(op,sid,seq,expected=0,mode=0,corrupt=False):
 global now
 now+=150;b=bytearray(packet(op,sid,seq,mode))
 if corrupt:b[-1]^=1
 u.mem_write(WIRE,bytes(b));f=bytearray(336);struct.pack_into('<II',f,0,WIRE,len(b));f[8:29]=b'turbo-navigation.tnv\0';f[329]=1;struct.pack_into('<I',f,332,len(b));u.mem_write(FILE,bytes(f))
 before=queued;call(callback,FILE);assert queued==before+1;u.mem_write(WIRE,bytes(len(b)));before=len(replies)
 call(0x106eba90,0,QUEUE)
 if expected is None:assert len(replies)==before;return
 assert len(replies)==before+1;ack=replies[-1];assert ack[5]==expected and struct.unpack_from('<II',ack,8)==(sid,seq),(ack,expected)
send(1,10,1,1,corrupt=True);assert len(objects)==1 and not tokens
bond=False;send(1,10,2,None);bond=True
business=False;send(1,10,3,3);business=True
send(1,10,4);assert tokens=={7} and len(objects)==9 and 'native_state_1' in calls and '80 m' in labels.values(),labels
beforealloc=len(alloc);send(2,10,5);assert len(alloc)==beforealloc
send(2,10,5);send(2,10,4,4)
tick(61000);assert not tokens and calls[-1]=='sleep'
put(EVENT,0x3a);call('m8_hook_vm_event',EVENT);assert tokens=={7} and events==1
send(2,10,6,mode=1);tick(20000);send(3,10,7);tick(20000);send(3,10,8);tick(25000);assert tokens=={7}
linked=False;tick(1000);assert not tokens;linked=True
send(2,10,9);put(EVENT,0x3b);call('m8_hook_vm_event',EVENT);assert not tokens and events==2
tick(200);assert len(objects)==1;send(2,10,10,6);send(1,10,11,4)
send(1,11,1);put(0x18001000+24,1);call('tn_slot_hidden',slot);assert not tokens and len(objects)==9
tick(200);assert len(objects)==9;put(0x18001000+24,0);tick(200);assert len(objects)==1
send(1,12,1);business=False;tick(1100);business=True;assert not tokens and len(objects)==1
fail_alloc=True;send(1,13,1,5);fail_alloc=False
fail_power=True;assert not call('tn_slot_open',slot);tick(200);assert len(objects)==1;fail_power=False
assert call('tn_slot_open',slot);assert tokens=={7};send(1,14,1);send(4,14,2);tick(200);assert not tokens and len(objects)==1
# External parent deletion callback before timer reclamation.
send(1,15,1);rootobj=next(k for k,v in objects.items() if 'cb' in v);call(objects[rootobj]['cb'],rootobj);objects={PARENT:{}};tick(200);assert not tokens
call('tn_slot_destroy',slot);tick(200);assert not timers and len(freed)==len(alloc)
result={'passed':True,'AP':report['candidateAP'],'scope':'linked ARM service plus LVGL adapter; OS/native state transition mocked','deviceIO':False,'receivedViaRegisteredFile':True,'UIThreadDeepCopy':True,'doubleBufferedView':True,'firstStartAutoMenuTransition':True,'nativePowerTokenReleased':True,'buttonWakeAndExit':True,'staleLatePacketsRejected':True,'busyDeferredFree':True,'parentDeleteCallback':True,'noHeapLeaks':True,'replyCount':len(replies),'physicalDisplayVerified':False}
if a.phone_trace:
 trace=json.loads(a.phone_trace.read_text());assert trace['syntheticOnly'];slot=call('tn_slot_create',APP);put(APP+0xdc+28,slot)
 for encoded in trace['packets']:
  now+=150;b=base64.b64decode(encoded,validate=True);u.mem_write(WIRE,b);f=bytearray(336);struct.pack_into('<II',f,0,WIRE,len(b));f[8:29]=b'turbo-navigation.tnv\0';f[329]=1;struct.pack_into('<I',f,332,len(b));u.mem_write(FILE,bytes(f));before=len(replies);call(callback,FILE);call(0x106eba90,0,QUEUE);assert len(replies)==before+1 and replies[-1][5]==0
 assert not tokens;tick(200);call('tn_slot_destroy',slot);tick(200);assert not timers and len(freed)==len(alloc)
 result.update(phoneTracePackets=len(trace['packets']),phoneTraceSHA256=hashlib.sha256(a.phone_trace.read_bytes()).hexdigest())
(d/'navigation-service-arm.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
