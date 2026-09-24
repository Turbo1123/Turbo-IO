"""Actual linked AP; renderer/layout/failure injection, no device I/O."""
from pathlib import Path
path=Path(__file__).with_name('test_reader_arm.py')
exec(compile(path.read_text().split('seq=0\n')[0],str(path),'exec'))

def cleanup():
 call('wr_slot_hidden',reader);put(0x18001000+24,0);tick(100)
 assert not tokens and len(objects)==1
 assert len(timers)==0

# Renderer busy BEFORE creation: accept intent, reserve input, retry on idle.
put(0x18001000+24,1)
assert call('wr_slot_open',reader)==1 and len(objects)==1
assert call('wr_slot_visible',reader)==1
tick(100);assert not labels
put(0x18001000+24,0);tick(100)
assert any('请在手机同步书架' in s for s in labels.values()) and tokens
assert any(r[5]==1 for r in replies)
cleanup()

# Renderer flips busy AFTER widgets are created, before first paint.
trigger=True
def inject(_u,addr,size,data):
 global trigger
 if trigger and addr==(symbols['nav_always_on']&~1):
  put(0x18001000+24,1);trigger=False
u.hook_add(UC_HOOK_CODE,inject)
assert call('wr_slot_open',reader)==1 and not labels and tokens
tick(100);assert not labels
put(0x18001000+24,0);tick(100)
assert any('请在手机同步书架' in s for s in labels.values())
cleanup()

# Phone OPEN can be queued while busy, then closes with explicit timeout.
put(0x18001000+24,1);send(packet(1,1,sid=20));tick(5100)
assert replies[-1][5:7]==bytes([4,3]),replies[-1]
assert struct.unpack_from('<I',replies[-1],24)[0]==9
assert not tokens and not call('wr_slot_visible',reader)
put(0x18001000+24,0);tick(100)
assert not timers and len(objects)==1

# Cancel while waiting must not open later after the renderer becomes idle.
put(0x18001000+24,1);assert call('wr_slot_open',reader)
put(EVENT,0x3b);call('m8_hook_vm_event',EVENT)
put(0x18001000+24,0);tick(100)
assert len(objects)==1 and not timers and not tokens

# Allocation and power failures cannot strand a page or permanent token.
fail_alloc=True;send(packet(1,1,sid=21),3);fail_alloc=False
fail_power=True;send(packet(1,1,sid=22),3)
assert struct.unpack_from('<I',replies[-1],24)[0]==8
fail_power=False;tick(100);assert len(objects)==1 and not timers

# Subsequent clean open still succeeds; destroy while renderer busy defers free.
send(packet(1,1,sid=23));assert tokens
put(0x18001000+24,1);before=len(freed)
call('wr_slot_destroy',reader);put(slot+28,0)
tick(100);assert not tokens and len(freed)==before+1 # slot only
put(0x18001000+24,0);tick(100);call('tn_slot_destroy',slot);tick(100)
assert not timers and alloc.keys()==freed and len(objects)==1
result={'passed':True,'AP':report['candidateAP'],'deviceIO':False,
 'nestedRootsBeforeLayout':True,'busyBeforeCreate':True,'busyBeforePaint':True,
 'openTimeoutMs':5000,'cancelWhileOpening':True,'powerFailureCleanup':True,
 'retryAfterFailure':True,'noHeapLeaks':True,'physicalDisplayVerified':False}
(d/'reader-open-lifecycle-arm.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
