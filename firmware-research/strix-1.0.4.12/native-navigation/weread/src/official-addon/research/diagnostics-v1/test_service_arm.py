"""Execute the diagnostic AP file/queue/timer path with explicit native mocks."""
from pathlib import Path
source=(Path(__file__).resolve().parents[1]/'navigation-runtime-v1/test_service_arm.py').read_text().split("slot=call('tn_slot_create',APP)")[0]
def replace(before,after):
 global source
 assert source.count(before)==1,(before,source.count(before))
 source=source.replace(before,after)
replace("'stock_vm_event','stock_message']","'stock_vm_event','stock_message','td_gettid']")
replace("assert 32<=count<=512","assert count==24")
replace("elif n=='stream_tick':ret(now)","elif n=='stream_tick':ret(now)\n elif n=='td_gettid':ret(thread_id)")
replace("assert r(0)==15 and r(3)==0;b=bytes(u.mem_read(r(1),r(2)));assert b[:5]==bytes([8,1,16,6,26]) and b[5]<128 and len(b)==6+b[5]\n  j=json.loads(b[6:]);assert j['cmd']=='turbo_nav_v1';ack=bytes.fromhex(j['payload']['data']);assert len(ack)==32 and ack[:5]==b'TNA1\\1' and zlib.crc32(ack[:28])==struct.unpack_from('<I',ack,28)[0];replies.append(ack);ret()",
 "assert r(0)==15 and r(3)==0;b=bytes(u.mem_read(r(1),r(2)));assert b[:5]==bytes([8,1,16,6,26]) and b[5]&128 and b[6]<128 and len(b)==7+(b[5]&127)+(b[6]<<7)\n  j=json.loads(b[7:]);assert j['cmd']=='turbo_diagnostics_v1';ack=bytes.fromhex(j['payload']['data']);assert len(ack)==128 and ack[:8]==b'TDG1\\1\\0\\x80\\0' and zlib.crc32(ack[:124])==struct.unpack_from('<I',ack,124)[0];replies.append(ack);ret()")
exec(compile(source,__file__,'exec'))
thread_id=42
slot=call('tn_slot_create',APP);assert slot;put(APP+0xdc+28,slot)
call('stream_register_shim');callback=word(0x19750d2c+0x18)
put(0x18617d48,700);put(0x18617d4c,900)
def packet(op=1,sid=1,seq=1,lease=3000):
 b=bytearray(b'TDQ1'+bytes([1,op,0,0])+struct.pack('<III',sid,seq,lease));b+=struct.pack('<I',zlib.crc32(b));return bytes(b)
def send(b):
 u.mem_write(WIRE,b);f=bytearray(336);struct.pack_into('<II',f,0,WIRE,len(b));name=b'turbo-diagnostics.tdg\0';f[8:8+len(name)]=name;f[329]=1;struct.pack_into('<I',f,332,len(b));u.mem_write(FILE,bytes(f))
 before=queued;alloc_before=len(alloc);reply_before=len(replies);call(callback,FILE)
 assert len(alloc)==alloc_before and len(replies)==reply_before,'BT callback executed diagnostic UI/heap path'
 if queued>before:call(0x106eba90,0,QUEUE)
 return queued>before
assert not timers and len(objects)==1
for bad in [packet()[:-1],packet()+b'\0',packet(3),packet(sid=0),packet(lease=600001)]:
 assert not send(bad)
bond=False;send(packet());assert not timers and not replies;bond=True
fail_alloc=True;send(packet());assert not timers and not replies;fail_alloc=False
assert send(packet());assert len(timers)==1 and len(replies)==1
ack=replies[-1];assert struct.unpack_from('<3I',ack,32)==(16777216,700,900)
assert struct.unpack_from('<I',ack,24)[0]==7|(1<<10)|(1<<11)
assert not any(struct.unpack_from('<7I',ack,44)) # all unmeasured heap/free slots
assert len(objects)==1 and not tokens and not {'wake','sleep','native_state_1'}&set(calls)
tick(500);assert len(replies)==1;tick(500);assert len(replies)==2
send(packet(seq=2));tick(1000);assert len(replies)==3;tick(1000);assert not timers and not word(slot+28)
send(packet(sid=2));send(packet(2,sid=3,seq=2,lease=0));assert timers
send(packet(2,sid=2,seq=1,lease=0));assert timers
send(packet(2,sid=2,seq=2,lease=0));assert not timers
send(packet(sid=4));linked=False;tick(1000);assert not timers;linked=True
send(packet(sid=5));business=False;tick(1000);assert not timers;business=True
send(packet(sid=6));before=len(replies);thread_id=43;tick(1000);assert len(replies)==before;thread_id=42
call('td_slot_destroy',slot);assert not timers
call('tn_slot_destroy',slot);assert alloc.keys()==freed and not tokens
result={'passed':True,'deviceIO':False,'AP':hashlib.sha256(ap).hexdigest(),
 'checks':['malformed command rejected before UI queue','BT callback only copies into bounded stock queue',
 'paired binding','allocation failure','one-second telemetry','no unmeasured zeros marked valid',
 'fixed lease and replay rejection','session-bound stop','disconnect retirement','business interruption retirement',
 'owner-thread guard','no screen/awake/UI effects','no outstanding allocations after cleanup']}
(d/'diagnostics-service-arm.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
