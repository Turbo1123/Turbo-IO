"""Compile diagnostic objects and execute lightweight provider under ARM emulation.
Does not modify an AP image, package OTA, or access hardware.
"""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_THUMB,UC_MODE_MCLASS,UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_PC

HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
compiler=Path('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/clang')
tool=compiler.parent
def run(args):return subprocess.check_output([str(x) for x in args],text=True)
flags=['--target=arm-none-eabi','-mcpu=cortex-m33','-mthumb','-mfloat-abi=hard','-mfpu=fpv5-sp-d16',
       '-ffreestanding','-fno-builtin','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-Os',
       '-Wall','-Wextra','-Werror','-DTD_FREESTANDING=1','-DTD_STOCK_10412=1']
for name in ['diagnostics','native_light']:
    run([compiler,*flags,'-c',HERE/(name+'.c'),'-o',out/(name+'.o')])
elf=out/'diagnostics.elf'
run([tool/'ld.lld','-T',HERE/'test_link.ld',out/'diagnostics.o',out/'native_light.o','-o',elf])
assert not run([tool/'llvm-nm','-u',elf]).strip()
run([tool/'llvm-objcopy','-O','binary',elf,out/'diagnostics.bin'])
symbols={r.split()[0]:int(r.split()[2],16) for r in run([tool/'llvm-nm','--defined-only','--format=posix',elf]).splitlines() if len(r.split())>=3}
u=Uc(UC_ARCH_ARM,UC_MODE_THUMB|UC_MODE_MCLASS)
for start,size in [(0x10e00000,0x10000),(0x10000000,0x10000),(0x18600000,0x20000),(0x20000000,0x100000)]:u.mem_map(start,size)
u.mem_write(0x10e00000,(out/'diagnostics.bin').read_bytes())
STOP=0x10001000;STATE=0x20000100;owner=False
def hook(_u,addr,size,data):
    if addr==STOP:u.emu_stop();return
    if addr==(symbols['td_gettid']&~1):
        u.reg_write(UC_ARM_REG_R0,12 if owner else 13);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
    elif addr in [symbols[n]&~1 for n in ['memcpy','memset','memcmp']]:
        raise AssertionError('Unexpected library call for metric-only provider')
u.hook_add(UC_HOOK_CODE,hook)
def call():
    u.mem_write(0x20000000,struct.pack('<I',12))
    u.reg_write(UC_ARM_REG_R0,0x20000000);u.reg_write(UC_ARM_REG_R1,STATE)
    u.reg_write(UC_ARM_REG_SP,0x200ff000);u.reg_write(UC_ARM_REG_LR,STOP|1)
    u.emu_start(symbols['td_stock_light']|1,STOP,count=50000)
    assert u.reg_read(UC_ARM_REG_PC)==STOP
def word(p):return struct.unpack('<I',u.mem_read(p,4))[0]
def metrics(used,peak,allowed):
    global owner
    owner=allowed;u.mem_write(STATE,bytes(1664));u.mem_write(0x18617d48,struct.pack('<II',used,peak));call()
    # Seven header u32s + 20 metric u32s => valid at 108.
    return word(STATE+108),[word(STATE+28+i*4) for i in range(20)]
mask,v=metrics(100,200,False);assert mask==0 and not any(v)
mask,v=metrics(100,200,True);assert mask==7 and v[:3]==[16777216,100,200] and not any(v[3:])
for used,peak in [(201,200),(100,16777217),(0xffffffff,0xffffffff)]:
    mask,v=metrics(used,peak,True);assert mask==0 and not any(v)
result={'passed':True,'deviceIO':False,'firmwareModified':False,
        'checks':['ARM compile and link','no BSS or writable data','owner-context rejection',
                  'exact lightweight LVGL counter offsets','invalid counter fail-closed','unmeasured fields invalid'],
        'moduleBytes':(out/'diagnostics.bin').stat().st_size,
        'sourceSHA256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(HERE.iterdir()) if f.suffix in ['.c','.h','.ld']}}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
