"""Execute linked TWR1 service + LVGL adapter against mocked platform ABI."""
from pathlib import Path
source=(Path(__file__).resolve().parents[1]/'navigation-runtime-v1/test_service_arm.py').read_text().split("slot=call('tn_slot_create',APP)")[0]
def replace(a,b):
 global source
 assert a in source,a;source=source.replace(a,b)
replace('assert r(2)==r(3)==128','assert r(2)==64 and r(3)==88')
replace('(16,18,20,32)','(14,16,18,20,32)')
# A newly created object's requested size has not necessarily been laid out.
# Only the pre-existing launcher surface has trustworthy coordinates here.
replace("elif n=='tio_lv_obj_get_width':ret(540)","elif n=='tio_lv_obj_get_width':ret(540 if r(0)==PARENT else 1)")
replace("elif n=='tio_lv_obj_get_height':ret(280)","elif n=='tio_lv_obj_get_height':ret(280 if r(0)==PARENT else 1)")
replace("'turbo_nav_v1'","'turbo_read_v1'")
replace("assert b[:5]==bytes([8,1,16,6,26]) and b[5]<128 and len(b)==6+b[5]", "assert b[:5]==bytes([8,1,16,6,26]) and b[5]&128 and len(b)==7+(b[5]&127)+(b[6]<<7)")
replace('json.loads(b[6:])','json.loads(b[7:])')
replace("len(ack)==32 and ack[:5]==b'TNA1\\1' and zlib.crc32(ack[:28])==struct.unpack_from('<I',ack,28)[0]", "len(ack)==48 and ack[:5]==b'WRA1\\1' and zlib.crc32(ack[:44])==struct.unpack_from('<I',ack,44)[0]")
replace("elif n=='nav_set_state':assert r(0)==VM and r(1)==1;put(VM+0x1c,1);calls.append('native_state_1');ret()", "elif n=='nav_set_state':\n  assert r(0)==VM and r(1)==1;put(VM+0x1c,1);calls.append('native_state_1');u.reg_write(UC_ARM_REG_R0,reader);u.reg_write(UC_ARM_REG_PC,symbols['wr_slot_hidden']|1)")
# Delete descendants recursively, not just one generation of cards/canvases.
replace("keys={r(0)}|{k for k,v in objects.items() if v.get('parent')==r(0)}", "keys={r(0)}\n  for _ in range(5):keys|={k for k,v in objects.items() if v.get('parent') in keys}")
exec(compile(source,__file__,'exec'))
slot=call('tn_slot_create',APP);put(APP+0xdc+28,slot)
reader=call('wr_slot_create',APP);put(slot+28,reader)
call('stream_register_shim');callback=word(0x19750d2c+0x18)
def packet(op,seq,data=b'',rev=0,offset=0,sid=10):
 b=bytearray(b'TWR1'+bytes([1,op,0,0])+struct.pack('<IIIIII',sid,seq,rev,offset,len(data),0)+data);struct.pack_into('<I',b,28,zlib.crc32(b));return bytes(b)
def send(b,result=0):
 global now
 now+=150;u.mem_write(WIRE,b);f=bytearray(336);struct.pack_into('<II',f,0,WIRE,len(b));name=b'turbo-reader.twr\0';f[8:8+len(name)]=name;f[329]=1;struct.pack_into('<I',f,332,len(b));u.mem_write(FILE,bytes(f));before=queued;call(callback,FILE);assert queued==before+1;u.mem_write(WIRE,bytes(len(b)));before=len(replies);call(0x106eba90,0,QUEUE);assert len(replies)==before+1 and replies[-1][6]==result,(result,replies[-1])
seq=0
def cmd(op,data=b'',rev=0,offset=0,result=0):
 global seq
 seq+=1;send(packet(op,seq,data,rev,offset),result)
def body(data,rev):
 cmd(2,struct.pack('<II',len(data),zlib.crc32(data)),rev)
 for offset in range(0,len(data),480):cmd(3,data[offset:offset+480],rev,offset)
 cmd(4,rev=rev)
# Invalid OPEN does not allocate/open a page.
send(packet(1,1,b'bad'),1);assert len(objects)==1 and not tokens
cmd(1);assert call('wr_slot_visible',reader) and tokens=={7}
wakes=calls.count('wake');send(packet(1,seq));assert calls.count('wake')==wakes
shelf=bytearray(64+4*5824);struct.pack_into('<IIII',shelf,0,1,0,8,4)
for i in range(4):
 at=64+i*5824;title=f'Book {i+1}'.encode();shelf[at:at+len(title)]=title;struct.pack_into('<I',shelf,at+160,i+1);shelf[at+192:at+5824]=bytes([60+i])*5632
body(bytes(shelf),1);tick(50);assert any('Book 1' in s for s in labels.values())
before=len([r for r in replies if r[5]==2])
for _ in range(20):call('wr_slot_wheel',reader,1);tick(10)
call('wr_slot_wheel',reader,600);tick(200);put(EVENT,0x3a);call('m8_hook_vm_event',EVENT);tick(50)
assert len([r for r in replies if r[5]==2])==before,'motion must not become a click'
tick(200);call('m8_hook_vm_event',EVENT);tick(1000);assert replies[-1][5]==2 and struct.unpack_from('<I',replies[-1],24)[0]==2
book=bytearray(256+8*128);struct.pack_into('<IIIIIIII',book,0,2,0,80,8,0,480,1,2);book[64:68]=b'Book'
for i in range(8):book[256+i*128:260+i*128]=b'four'
body(bytes(book),2);put(0x18001000+24,1);tick(50);assert not any(s=='four' for s in labels.values());put(0x18001000+24,0);tick(50);assert 'four' in labels.values()
tick(500);cmd(7);assert struct.unpack_from('<I',replies[-1],32)[0]>=1
for _ in range(8):tick(500)
assert any(r[5]==3 for r in replies),'missing window request'
# Long press reader -> bookshelf request, long press shelf -> closes.
put(EVENT,0x3b);call('m8_hook_vm_event',EVENT);tick(1100);assert replies[-1][5]==1
body(bytes(shelf),3);tick(50);put(EVENT,0x3b);call('m8_hook_vm_event',EVENT);assert not tokens;tick(100);assert len(objects)==1
cmd(7,result=4)
# Fresh control and parent deletion with DMA busy defer backing release.
assert call('wr_slot_open',reader);tick(100);assert replies[-1][5]==1
rootobj=next(k for k,v in objects.items() if 'cb' in v);put(0x18001000+24,1);before=len(freed);call(objects[rootobj]['cb'],rootobj);objects={PARENT:{}};tick(100);assert len(freed)==before and not tokens
put(0x18001000+24,0);tick(100);call('wr_slot_destroy',reader);put(slot+28,0);call('tn_slot_destroy',slot);tick(100)
assert not timers and alloc.keys()==freed and not tokens
result={'passed':True,'AP':report['candidateAP'],'deviceIO':False,'deepCopy':True,'nativeFocusHide':True,'fourCovers':True,'readWindow':True,'pagingUplink':True,'invalidOpenNoUI':True,'busyRendererDeferral':True,'parentDeleteNoDoubleFree':True,'noHeapLeaks':True,'physicalDisplayVerified':False}
if a.phone_trace:
 trace=json.loads(a.phone_trace.read_text());assert trace['syntheticOnly']
 slot=call('tn_slot_create',APP);put(APP+0xdc+28,slot)
 reader=call('wr_slot_create',APP);put(slot+28,reader)
 for encoded in trace['packets']:
  send(base64.b64decode(encoded,validate=True));tick(50)
 assert not tokens;tick(100)
 call('wr_slot_destroy',reader);put(slot+28,0);call('tn_slot_destroy',slot);tick(100)
 assert not timers and alloc.keys()==freed and not tokens
 result.update(phoneTracePackets=len(trace['packets']),phoneTraceSHA256=hashlib.sha256(a.phone_trace.read_bytes()).hexdigest())
(d/'reader-service-arm.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
