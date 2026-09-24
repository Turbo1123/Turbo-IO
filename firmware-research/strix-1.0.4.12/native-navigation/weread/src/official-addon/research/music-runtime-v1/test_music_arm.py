"""Run linked TMU1 ARM code; reuse only the independently mocked native ABI.
No device access. Tests real file hook, deep-copy UI dispatch and lifecycle.
"""
from pathlib import Path
source=(Path(__file__).resolve().parents[1]/'navigation-runtime-v1/test_service_arm.py').read_text().split("slot=call('tn_slot_create',APP)")[0]
def replace(a,b):
 global source
 assert a in source,a
 source=source.replace(a,b)
replace("'stock_vm_event','stock_message']","'stock_vm_event','stock_message','menu_opa']")
replace("assert r(2)==r(3)==128","assert r(2)==r(3)==144")
replace("(16,18,20,32)","(14,16,18,20,24,32)")
replace("'turbo_nav_v1'","'turbo_music_v1'")
replace("32<=count<=512","32<=count<=4096")
replace("ack[:5]==b'TNA1\\1'","ack[:5]==b'TMA1\\1'")
replace("elif n in ('menu_text_font'","elif n in ('menu_opa','menu_text_font'")
replace("count=15000000","count=30000000")
replace("elif n=='menu_font':assert r(0) in (14,16,18,20,24,32);ret(0x20006000)","elif n=='menu_font':assert r(0) in (14,16,18,20,24,32);ret(0x20006000+r(0))")
replace("elif n in ('menu_opa','menu_text_font'", "elif n=='menu_text_font':objects[r(0)]['font']=r(1)-0x20006000;ret()\n elif n=='menu_opa':objects[r(0)]['opacity']=r(1);ret()\n elif n=='native_align':objects[r(0)]['xy']=(r(2),r(3));ret()\n elif n=='tio_lv_obj_set_size':objects[r(0)]['wh']=(r(1),r(2));ret()\n elif n in ('menu_opa','menu_text_font'")
replace("elif n=='native_align':objects", "elif n in ('native_align','tio_lv_obj_align'):objects")
replace("elif n=='nav_set_state':assert r(0)==VM and r(1)==1;put(VM+0x1c,1);calls.append('native_state_1');ret()", "elif n=='nav_set_state':\n  assert r(0)==VM and r(1)==1;put(VM+0x1c,1);calls.append('native_state_1')\n  # Native focus transition synchronously hides the old launcher/menu view.\n  # Tail-call the actual linked music lifecycle hook, retaining caller LR.\n  u.reg_write(UC_ARM_REG_R0,music);u.reg_write(UC_ARM_REG_PC,symbols['tm_slot_hidden']|1)")
exec(compile(source,__file__,'exec'))
slot=call('tn_slot_create',APP);assert slot;put(APP+0xdc+28,slot)
music=call('tm_slot_create',APP);assert music;put(slot+24,music)
call('stream_register_shim');callback=word(0x19750d2c+0x18)
def packet(op,seq,data=b'',offset=0,final=0,gen=1,sid=10):
 b=bytearray(b'TMU1'+bytes([1,op,final,0])+struct.pack('<IIIIII',sid,gen,seq,len(data),0,offset)+data);struct.pack_into('<I',b,24,zlib.crc32(b));return bytes(b)
def send(b,expected=0):
 global now
 now+=150;u.mem_write(WIRE,b);f=bytearray(336);struct.pack_into('<II',f,0,WIRE,len(b));name=b'turbo-music.tmu\0';f[8:8+len(name)]=name;f[329]=1;struct.pack_into('<I',f,332,len(b));u.mem_write(FILE,bytes(f));before=len(replies);call(callback,FILE);call(0x106eba90,0,QUEUE);assert len(replies)==before+1 and replies[-1][6]==expected,(replies[-1] if replies else 'no reply',expected)
state=bytearray(208);struct.pack_into('<II',state,0,0,90000);state[8]=1;state[9]=1;title='音乐校验7392'.encode();state[16:16+len(title)]=title
# Phone starts from home without a pre-opened waiting page. OPEN must not
# acknowledge success while active=0 after its native setState/hide callback.
send(packet(1,1,state,sid=9));assert replies[-1][7]&3==3,'OPEN lost session during native focus transition'
send(packet(2,2,state,sid=9));assert replies[-1][7]&1
send(packet(5,3,sid=9));tick(100);assert not call('tm_slot_visible',music)
# Menu -> uplink while no audio selected. Paired, foreground safety enforced.
assert call('tm_slot_open',music)==1;assert tokens=={7};tick(100);assert replies[-1][5]==1 and struct.unpack_from('<I',replies[-1],20)[0]
send(packet(1,1,state));tick(33);assert '音乐校验7392' in labels.values();assert tokens=={7}
first_wakes=calls.count('wake');send(packet(1,1,state));assert calls.count('wake')==first_wakes,'duplicate OPEN wakes again'
cover=bytes((x%256 for x in range(144*144)));seq=2
for at in range(0,len(cover),4064):
 data=cover[at:at+4064];send(packet(3,seq,data,at,int(at+len(data)==len(cover))));seq+=1
lyric=b''.join(struct.pack('<IH',i*5000,5)+f'line{i}'.encode() for i in range(7))
send(packet(4,seq,lyric,final=1));seq+=1;tick(33)
rows=sorted((k for k in labels if objects[k]['xy'][0]==166),key=lambda k:objects[k]['xy'][1]);assert len(rows)==5
assert [objects[k]['xy'][1] for k in rows]==[10,42,74,106,138]
assert [objects[k]['font'] for k in rows]==[18,20,24,20,18]
assert [objects[k]['opacity'] for k in rows]==[85,150,255,150,85]
for pos,expected in [(15000,['line1','line2','line3','line4','line5']),(30000,['line4','line5','line6','','']),(0,['','','line0','line1','line2'])]:
 struct.pack_into('<I',state,0,pos);state[8]=0;send(packet(2,seq,state));seq+=1;tick(33)
 assert [labels[k] for k in rows]==expected,([labels[k] for k in rows],expected)
state[8]=1
# CLOCK traffic must not extend the screen deadline.
for i in range(12):
 tick(2500);struct.pack_into('<I',state,0,i*2500);send(packet(2,seq,state));seq+=1
assert not tokens and 'sleep' in calls
put(EVENT,0x3a);call('m8_hook_vm_event',EVENT);assert tokens=={7};tick(1100);assert replies[-1][5]==1
put(EVENT,0x3a);call('m8_hook_vm_event',EVENT);tick(1100);assert replies[-1][5]==3 # SET_PAUSED
call('tm_slot_wheel',music,30);tick(1100);assert replies[-1][5]==4
put(EVENT,0x3b);call('m8_hook_vm_event',EVENT);assert not tokens;tick(100);assert not call('tm_slot_visible',music)
# Existing session CLOCK cannot resurrect a physically closed page.
send(packet(2,seq,state),4);seq+=1;assert not call('tm_slot_visible',music)
# Refuse auto-open over existing tasks; then retry a fresh sequence.
business=False;send(packet(1,seq,state,gen=2),3);seq+=1;business=True
send(packet(1,seq,state,gen=2));seq+=1
# Retire with DMA busy: no pixel backing freed before graph idle.
put(0x18001000+24,1);before=len(freed);call('tm_slot_hidden',music);tick(100);assert len(freed)==before and call('tm_slot_visible',music)
put(0x18001000+24,0);tick(100);assert not call('tm_slot_visible',music)
call('tm_slot_destroy',music);put(slot+24,0);tick(100);call('tn_slot_destroy',slot)
assert not timers and alloc.keys()==freed and not tokens
result={'passed':True,'AP':hashlib.sha256(ap).hexdigest(),'deviceIO':False,'noHeapLeaks':True,'nativeFocusHidePreservesOpeningSession':True,'menuResumeUplink':True,'coverAndLyrics':True,'fiveLyricRows':True,'currentAlwaysMiddle':True,'seekAndEdgePadding':True,'fixedScreenDeadline':True,'physicalExitDoesNotReopen':True,'busyDMADeferred':True,'duplicateOpenDoesNotWake':True,'controls':True}
(d/'music-service-arm.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
