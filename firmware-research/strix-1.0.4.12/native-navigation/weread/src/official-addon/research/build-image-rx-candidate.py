"""Hash-pinned OFFLINE Image RX successor candidate builder. Never flashes or contacts devices.

Output is an untested experimental OTA candidate, not a proven bootable release.
The author-approved PNG is embedded. A fresh build is not device authorization.
"""
import argparse, hashlib, json, os, shutil, struct, subprocess, zipfile
from pathlib import Path
import capstone
import menu8_native_profile as native_menu

ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'official-addon/research'
AP_SHA='53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988'
PNG_SHA='738169867ec0ca778cd6ce14e803aaa508bf16f8e169d1081db3e622d571db24'
BASE=0x10190000
CAPACITY=0x9f0000
HOOKS=[('show',0x1079a784,4),('hide',0x1079a7b8,4),
       ('destroy',0x10799660,4),('wheel',0x1079a310,6),('event',0x1079a890,4),
       ('message',0x106eba90,4)]
ALIASES={
 'stock_ctor':'rayneo::app::launcher::AppListView::AppListView',
 'native_adjusted_delta':'rayneo::app::launcher::AppListView::adjustedRawWheelDelta',
 'native_unregister_wheel':'rayneo::app::launcher::AppListView::unregisterRawWheelListener',
 'native_settled':'rayneo::app::launcher::AppListView::isRawWheelSlideSettled',
 'native_wake_overlay':'rayneo::app::launcher::isLauncherEncoderWakeOverlayVisible',
 'native_report_activity':'lv_rayneo_display_report_activity',
 'native_has_flag':'lv_obj_has_flag','native_event_code':'lv_event_get_code',
 'native_event_key':'lv_event_get_key','native_label_create':'lv_label_create',
 'native_label_text':'lv_label_set_text','native_text_color':'lv_obj_set_style_text_color',
 'native_align':'lv_obj_align','native_log':'logger_log',
 'stream_memalign':'memalign','stream_free':'free','stream_tick':'os_get_tick_count',
 'stream_timer_create':'lv_timer_create','stream_timer_delete':'lv_timer_delete',
 'stream_timer_next':'lv_timer_get_next',
 'stream_event_user':'lv_event_get_user_data','stream_add_event':'lv_obj_add_event_cb',
 'stream_canvas_create':'lv_canvas_create','stream_canvas_set_buffer':'lv_canvas_set_buffer',
 'stream_stride':'lv_draw_buf_width_to_stride','stream_display_next':'lv_display_get_next',
 'stream_invalidate':'lv_obj_invalidate','stream_queue_send':'message_processor_send',
 'memcpy':'memcpy','memset':'memset','memcmp':'memcmp','td_gettid':'gettid'}
def digest(b,alg='sha256'):return hashlib.new(alg,b).hexdigest()
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,capture_output=True,**kw).stdout
def put(p,data):
    with p.open('xb') as f:f.write(data.encode() if isinstance(data,str) else data)
    p.chmod(0o600)
def branch(site,target,link=False):
    delta=(target&~1)-(site+4)
    assert delta%2==0 and -(1<<24)<=delta<(1<<24),'Branch out of range'
    bits=delta&0x1ffffff;s=(bits>>24)&1;i1=(bits>>23)&1;i2=(bits>>22)&1
    j1=1^(i1^s);j2=1^(i2^s)
    return struct.pack('<HH',0xf000|(s<<10)|((bits>>12)&0x3ff),
      (0xd000 if link else 0x9000)|(j1<<13)|(j2<<11)|((bits>>1)&0x7ff))

def build(out,wide=False,native_eight=False,display_runtime=False,navigation_runtime=False,animation_runtime=False,music_runtime=False):
    assert not music_runtime or animation_runtime, 'Music preserves all previous runtime features'
    assert not animation_runtime or navigation_runtime, 'Animation experiment preserves TDP1 and TNV1'
    assert not navigation_runtime or display_runtime, 'Navigation must retain TDP1'
    assert not display_runtime or (wide and native_eight), 'TDP requires N8W menu geometry'
    hooks=HOOKS+(native_menu.WRAPPERS if native_eight else [])
    aliases={**ALIASES,**(native_menu.ALIASES if native_eight else {})}
    if animation_runtime:aliases['stream_timer_period']='lv_timer_set_period'
    if display_runtime: aliases['tdp_rnlink_send']='rnlink_if_send_payload'
    assert not out.exists(),'Output must be new'
    firmware=ROOT/'firmware-inspection/StrixOS-1.0.4.12'
    ap=(firmware/'nuttx_ap.bin').read_bytes();assert digest(ap)==AP_SHA
    assert len(ap)==9466560 and ap[-8:]==bytes.fromhex('1d3457be00001930')
    partition=bytearray(116);partition[:2]=b'ap'
    struct.pack_into('<II',partition,104,0xc80,0x4f80)
    assert ap.find(partition)==0x2d9304,'AP partition descriptor changed'
    png=ROOT/'official-addon/build/turbo-photo-png-10412-20260921/turbo-photo-gray16-rgba-88x98.png'
    assert digest(png.read_bytes())==PNG_SHA
    manifest=json.loads((firmware/'OtaFileInfo.json').read_bytes())
    baseline=json.loads((firmware/'baseline.json').read_bytes())
    assert len(manifest)==14 and len({r['Name'] for r in manifest})==14
    originals={}
    for row in manifest:
        name=row['Name'];assert Path(name).name==name
        b=(firmware/name).read_bytes()
        assert len(b)==row['Size'] and digest(b,'md5')==row['Md5']
        assert digest(b)==next(r['sha256'] for r in baseline['files'] if r['name']==name)
        originals[name]=b
    syms=json.loads((firmware/'symbols.json').read_bytes())
    def locate(addr):
        for low,high,at in syms['segments']:
            if low<=addr<high:return at+addr-low
        assert BASE<=addr<BASE+len(ap)
        return addr-BASE
    def symbol(name,expected=None):
        matches=[e for e in syms['entries'] if e['name']==name and (expected is None or e['address']==expected)]
        addresses={e['address'] for e in matches}
        assert len(addresses)==1 and next(iter(addresses))&1,name
        for e in matches:
            p,a=struct.unpack_from('<II',ap,e['tableOffset']);assert a==e['address']
            at=locate(p);assert ap[at:at+len(name)+1]==name.encode()+b'\0'
        return next(iter(addresses))
    md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);md.detail=True
    entries={e['address']&~1 for e in syms['entries']}
    for name,addr,n in hooks:
        instructions=list(md.disasm(ap[addr-BASE:addr-BASE+n],addr))
        assert sum(i.size for i in instructions)==n
        assert not any(addr<e<addr+n for e in entries)
        for i in instructions:
            assert i.mnemonic in ('push','push.w','sub','mov','add','ldr.w','ldrb.w'),(name,i.mnemonic)
            assert 'pc' not in i.op_str and not i.mnemonic.startswith('b')
    assert ap[0x1079fe2c-BASE:0x1079fe2e-BASE]==bytes.fromhex('dc20')
    ctor_instruction=next(md.disasm(ap[0x1079fe3c-BASE:0x1079fe40-BASE],0x1079fe3c))
    assert ctor_instruction.mnemonic=='bl' and ctor_instruction.operands[0].imm==0x107994dc
    out.mkdir(parents=True,mode=0o700)
    generated=out/'generated'
    run(['node',SRC/'prepare-menu8-linkcheck.mjs',firmware,png,generated])
    assignments=(generated/'native-symbols.ld').read_text()
    resolved=[]
    for alias,name in aliases.items():
        if isinstance(name,tuple):
            name,expected=name;addr=symbol(name,expected)
        else:addr=symbol(name)
        assignments+=f'{alias} = 0x{addr:x};\n'
        resolved.append(dict(alias=alias,name=name,address=hex(addr)))
    assembly='.syntax unified\n.cpu cortex-m55\n.thumb\n.section .text.trampolines,"ax",%progbits\n'
    for name,addr,n in hooks:
        assembly+=f'.balign 2\n.global stock_{name}\n.type stock_{name},%function\n.thumb_func\nstock_{name}:\n'
        assembly+='.byte '+','.join(hex(x) for x in ap[addr-BASE:addr-BASE+n])+'\n'
        assembly+=f'b.w resume_{name}\n.size stock_{name},.-stock_{name}\n'
        assignments+=f'resume_{name} = 0x{(addr+n)|1:x};\n'
    # Keep both native registrations and every unrelated callback untouched.
    shim_at=0x106d9d1a
    assert ap[shim_at-BASE:shim_at-BASE+10]==bytes.fromhex('00241f48204b84610360')
    assert struct.unpack_from('<I',ap,0x106d9d9c-BASE)[0]==0x19750d2c
    assert struct.unpack_from('<I',ap,0x106d9da0-BASE)[0]==0x106d97f1
    assert struct.unpack_from('<I',ap,0x10799030-BASE)[0]==0x19a1f954
    assert struct.unpack_from('<I',ap,0x1057e18c-BASE)[0]==0x18617b8c
    assembly+='''
.balign 2
.global stream_register_shim
.type stream_register_shim,%function
.thumb_func
stream_register_shim:
  movs r4,#0
  ldr r0,=0x19750d2c
  ldr r3,=tio_hook_file
  str r3,[r0,#0x18]
  ldr r3,=0x106d97f1
  str r3,[r0]
  bx lr
.ltorg
'''
    if native_eight:
        for name in ['frame_start','frame_index']:
            assembly+=f'''\n.balign 2
.global m8_hook_{name}
.type m8_hook_{name},%function
.thumb_func
m8_hook_{name}:
  push {{r1,r2,r3,lr}}
  bl m8_impl_{name}
  pop {{r1,r2,r3,pc}}
'''
    put(generated/'trampolines.S',assembly)
    put(generated/'string.h','#include <stddef.h>\nvoid *memcpy(void *,const void *,size_t);\nvoid *memset(void *,int,size_t);\nint memcmp(const void *,const void *,size_t);\n')

    # Preserve all original build-info text and its header pointer. Move only
    # the terminal BUILD_INFO_MAGIC/base pair to the new physical end.
    footer_at=len(ap)-8; module_at=(footer_at+31)&~31;module_va=BASE+module_at
    script=assignments+f'''\nSECTIONS {{
      . = 0x{module_va:x};
      __module_start = .;
      .text : {{ *(.text .text.*) }}
      .rodata ALIGN({64 if animation_runtime else 4}) : {{ *(.rodata .rodata.*) }}
      .data : {{ *(.data .data.*) }}
      .bss : {{ *(.bss .bss.* COMMON) }}
      __module_end = .;
      /DISCARD/ : {{ *(.ARM.exidx* .ARM.extab* .comment .note* .llvm_addrsig) }}
    }}
    ASSERT(SIZEOF(.data) == 0, "Unexpected writable data")
    ASSERT(SIZEOF(.bss) == 0, "Unexpected BSS")
    ASSERT(__module_end < 0x{BASE+CAPACITY-8:x}, "AP partition capacity exceeded")
    '''
    put(generated/'link.ld',script)
    compiler=shutil.which('clang');linker=shutil.which('ld.lld');objcopy=shutil.which('llvm-objcopy');nm=shutil.which('llvm-nm')
    assert compiler and linker and objcopy and nm
    # Conservative Armv8-M Mainline subset: no M55 low-overhead loops/MVE in
    # extension code. All native calls here use integer/pointer arguments.
    flags=['--target=arm-none-eabi','-mcpu=cortex-m33','-mthumb','-mfloat-abi=hard','-mfpu=fpv5-sp-d16',
           '-ffreestanding','-fno-builtin','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-Os',
           '-Wall','-Wextra','-Werror','-I',str(SRC),'-I',str(generated)]
    if wide:flags+=['-DTIO_IMAGE_RX_WIDE=1']
    if display_runtime:flags+=['-DTIO_DISPLAY_RUNTIME=1','-DTDP_FREESTANDING']
    if animation_runtime:flags+=['-DTIO_ANIMATION_EXPERIMENT=1']
    if music_runtime:flags+=['-DTIO_MUSIC_RUNTIME=1','-DTD_DIAGNOSTICS_RUNTIME=1','-DTD_FREESTANDING=1','-DTD_STOCK_10412=1']
    objects=[]
    glue='navigation-runtime-v1/menu9' if navigation_runtime else 'menu8-native-carousel' if native_eight else 'menu8-stream-hooks'
    if music_runtime:glue='music-runtime-v1/menu10'
    units=([] if native_eight else ['menu8-sidecar'])+['menu8-renderer','menu8-native-lvgl','menu8-owner-layout',glue,'image-upload-test/image_test','image-upload-test/native_file_bridge','image-upload-test/render_idle','image-upload-test/native_page']
    if display_runtime:
        units=['menu8-renderer','menu8-native-lvgl',glue,'image-upload-test/render_idle']+[
            'display-runtime-v1/'+s for s in ['display_runtime','display_carrier','native_display_file','native_display_page']]
        if navigation_runtime:units+=['navigation-runtime-v1/'+s for s in ['nav_runtime','nav_visual','nav_view','nav_lvgl','nav_service']]
        if music_runtime:units+=['music-runtime-v1/music','music-runtime-v1/music_service']+['diagnostics-v1/'+s for s in ['diagnostics','command','native_light','diagnostics_service']]
    units+=['weread-v1/reader','weread-v1/reader_view','weread-v1/reader_service']
    animation_units=[]
    if animation_runtime:
        asset=SRC/'animation-runtime-v1/assets/encoded-v1/anime-idle-192x176-l8.bin'
        assert asset.stat().st_size==192*176*12
        assert digest(asset.read_bytes())=='f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d'
        put(generated/'animation-asset.S','.section .rodata.ta_asset,"a",%progbits\n.balign 64\n.global ta_asset\n.type ta_asset,%object\nta_asset:\n.incbin "'+str(asset)+'", 0, 33792\n.size ta_asset, .-ta_asset\n')
        units+=['animation-runtime-v1/animation']
        animation_units=[generated/'animation-asset.S']
    for source in [SRC/(s+'.c') for s in units]+([] if display_runtime else [generated/'photo-payload.c'])+[generated/'trampolines.S']+animation_units:
        obj=generated/(source.stem+'.o');run([compiler,*flags,'-c',source,'-o',obj]);objects.append(obj)
    elf=generated/'menu8-experiment.elf'
    run([linker,'-T',generated/'link.ld','--entry=m8_hook_ctor',*objects,'-o',elf])
    assert not run([nm,'-u',elf]).strip(),'Unresolved target symbols'
    symbol_map={}
    for line in run([nm,'--defined-only','--format=posix',elf]).decode().splitlines():
        parts=line.split()
        if len(parts)>=3:symbol_map[parts[0]]=int(parts[2],16)
    blobfile=generated/'module.bin';run([objcopy,'-O','binary',elf,blobfile]);blob=blobfile.read_bytes()
    assert symbol_map['__module_start']==module_va
    assert symbol_map['__module_end']-module_va==len(blob)
    patched=bytearray(ap[:footer_at]);patched.extend(b'\0'*(module_at-len(patched)));patched.extend(blob)
    patched.extend(b'\0'*((-len(patched))%4));patched.extend(ap[-8:])
    assert len(patched)<=CAPACITY
    changes=[]
    def replace(at,data,role):
        before=bytes(patched[at:at+len(data)]);patched[at:at+len(data)]=data
        changes.append(dict(offset=hex(at),length=len(data),before=before.hex(),after=data.hex(),role=role))
    replace(0x1079fe2c-BASE,bytes.fromhex('fc20'),'AppList allocation 220 to 252')
    for name,addr,n in hooks:
        target=symbol_map['m8_hook_'+name];encoded=branch(addr,target)
        i=next(md.disasm(encoded,addr));assert i.mnemonic=='b.w' and i.operands[0].imm==(target&~1)
        replace(addr-BASE,encoded+bytes.fromhex('00bf')*((n-4)//2),'Entry trampoline '+name)
        trampoline=symbol_map['stock_'+name]&~1
        off=trampoline-module_va
        assert blob[off:off+n]==ap[addr-BASE:addr-BASE+n]
        jump=next(md.disasm(blob[off+n:off+n+4],trampoline+n))
        assert jump.mnemonic=='b.w' and jump.operands[0].imm==addr+n
    if native_eight:
        for name,addr,n in native_menu.REPLACEMENTS:
            assert not any(addr<e<addr+n for e in entries)
            # Entire methods replaced: no execution of overwritten IT/prologue.
            encoded=branch(addr,symbol_map['m8_hook_'+name])
            replace(addr-BASE,encoded,'Native eight-slot method '+name)
        for addr,before,after,role in native_menu.PATCHES:
            assert ap[addr-BASE:addr-BASE+len(bytes.fromhex(before))]==bytes.fromhex(before)
            replace(addr-BASE,bytes.fromhex(after),role)
    data=branch(shim_at,symbol_map['stream_register_shim'],True)+bytes.fromhex('00bf')*3
    replace(shim_at-BASE,data,'Launcher NULL file callback becomes copied image receiver')
    target=symbol_map['m8_hook_ctor'];data=branch(0x1079fe3c,target,True)
    i=next(md.disasm(data,0x1079fe3c));assert i.mnemonic=='bl' and i.operands[0].imm==(target&~1)
    replace(0x1079fe3c-BASE,data,'Initialize tail after original constructor')
    allowed=set()
    for r in changes:allowed.update(range(int(r['offset'],16),int(r['offset'],16)+r['length']))
    assert all(ap[i]==patched[i] or i in allowed for i in range(footer_at))
    assert patched[:16]==ap[:16] and patched[-8:]==ap[-8:]
    build_at=struct.unpack_from('<I',ap,12)[0]-0x30190000
    assert bytes(patched[build_at:footer_at])==ap[build_at:footer_at]
    payload=out/'payload';payload.mkdir(mode=0o700)
    audit=[]
    for row in manifest:
        name=row['Name'];b=bytes(patched) if name=='nuttx_ap.bin' else originals[name]
        put(payload/name,b);row['Size']=len(b);row['Md5']=digest(b,'md5')
        audit.append(dict(name=name,bytes=len(b),sha256=digest(b),unchanged=b==originals[name]))
    assert sum(r['unchanged'] for r in audit)==13
    put(payload/'OtaFileInfo.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    archive=out/('StrixOS-1.0.4.12-'+('TurboWeRead-TWR1' if music_runtime else 'TurboAnimation-ANIM60' if animation_runtime else 'TurboNavigation-TNV1' if navigation_runtime else 'TurboDisplay-TDP1' if display_runtime else 'TurboImageRX-'+('N8W' if native_eight and wide else 'N8' if native_eight else 'R4W' if wide else 'R4'))+'-CANDIDATE-NOT-APPROVED.zip')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for name in ['OtaFileInfo.json']+list(originals):z.write(payload/name,name)
    archive.chmod(0o600)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert z.namelist()==['OtaFileInfo.json']+list(originals)
        for name in z.namelist():assert z.read(name)==(payload/name).read_bytes()
    report=dict(kind='image-rx-r4-experimental-ota',deviceIO=False,flashed=False,
      originalAP=AP_SHA,candidateAP=digest(patched),candidateAPBytes=len(patched),
      moduleOffset=hex(module_at),moduleVA=hex(module_va),moduleBytes=len(blob),
      extensionISA='Armv8-M Mainline Thumb, Cortex-M33 subset, hard-float ABI',
      apCapacity=hex(CAPACITY),changes=changes,footerRelocated=True,headerUnchanged=True,
      unchangedPayloads=13,payloads=audit,bindings=resolved,
      checks=dict(noUndefinedSymbols=True,trampolineReadback=True,branchTargets=True,
                  diffWhitelist=True,manifest=True,zipReadback=True),
      runtimeValidated=False,productionReady=False,readyToFlash=False,
      readyBlockers=['Independent ARM hook emulation and page lifecycle tests pending',
                    'Phone session setup and native display ACK integration pending',
                    'Native queue saturation budget and teardown review pending'],
      unresolved=['New image receiver, canvas ABI, timeout and native memory teardown not device-validated',
        'No TUI scene routing, PNG large-image decode or navigation UI in this minimal candidate',
        'Software/GPU idle graph follows pinned native fields; device faults remain unverified',
        'R3 boot/OTA success does not establish R4 runtime acceptance'],
      archive=dict(name=archive.name,bytes=archive.stat().st_size,sha256=digest(archive.read_bytes())))
    report['imageProfile']={'wide':wide,'width':512 if wide else 128,'height':128 if wide else 64,'version':2 if wide else 1}
    report['menuProfile']='native-eight-v1' if native_eight else 'virtual-eight-r4'
    report['sourceInputs']=[{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())}
      for p in sorted({SRC/(s+'.c') for s in units}|set(SRC.glob('*.h'))|set((SRC/'image-upload-test').glob('*.h'))|{Path(__file__),SRC/'menu8_native_profile.py',ROOT/'official-addon/ImageWireFormat.h'})]
    if native_eight:
        report['readyBlockers'].append('Native eight-slot integration, callbacks and UI allocation failure tests pending')
    if display_runtime:
        assert 'tio_native_page_open' not in symbol_map
        report['displayProfile']={'protocol':'TDP1','phoneBuild':'DISPLAY-PHONE-01','width':512,'height':128,
          'packetMax':512,'pixelChunkMax':472,'fileName':'turbo-display.tdp','replyBusiness':15,'replyPBType':6,
          'replyCommand':'turbo_display_v1','fullFrameDeadlineMs':30000,'leaseMs':120000}
        report['readyBlockers']=['Exact patched AP routing and native menu emulation pending',
          'Independent AP-only/manifest/archive audit pending','Phone OTA gate pins previous N8W, not this candidate',
          'Explicit flash authorization and live TDP Bluetooth/display acceptance pending']
        report['unresolved']=['New TDP runtime not boot-tested; rollback does not guarantee recovery',
          '139 tiny native file transfers may exceed the frame deadline; real throughput unverified',
          'UI_SUBMITTED is not physical display acknowledgement; actual LVGL/DMA remains unverified',
          'No real navigation feed or rotary/button event protocol in this candidate']
        report['sourceInputs'] += [{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())}
          for p in sorted((SRC/'display-runtime-v1').glob('*.h'))]
    if navigation_runtime:
        report['menuProfile']='native-nine-TDP1-and-TNV1'
        report['navigationProfile']={'protocol':'TNV1','packetMax':512,'sceneMax':328,'idleMs':60000,'fileName':'turbo-navigation.tnv','replyCommand':'turbo_nav_v1','menuIndex':8,'phoneAutoOpen':True}
        report['readyBlockers']=['Nine-slot and native navigation ARM integration tests pending','Phone TNV1 sender and OTA candidate pinning pending','Independent artifact audit pending','Explicit flash authorization pending']
        report['unresolved']=['New native navigation page and power behavior not device tested','Local mini map is route schematic, not map tiles','Only native launcher idle can auto-open; active stock tasks are not interrupted']
        report['sourceInputs'] += [{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())} for p in sorted((SRC/'navigation-runtime-v1').glob('*.h'))]+[{'path':str(SRC/'navigation-runtime-v1/menu9_profile.py'),'sha256':digest((SRC/'navigation-runtime-v1/menu9_profile.py').read_bytes())}]
    if animation_runtime:
        report['kind']='ANIM60-offline-experimental-candidate'
        report['animationProfile']={'width':192,'height':176,'format':'L8','sourceFrames':1,
          'sourcePoseFPS':0,'targetCanvasFPS':0,'durationMs':0,'pageTimeoutMs':60000,
          'benchmark':'Disabled: one static frame, one submission, no moving marker',
          'additionalPixelHeapBytes':0,'assetBytes':33792,'assetSHA256':digest(asset.read_bytes()[:33792]),
          'menu':'Turbo Display shows first pose; valid TDP upload replaces it; TNV1 retained'}
        report['sourceInputs'] += [{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())}
          for p in [SRC/'animation-runtime-v1/animation.h',asset]]
        report['readyBlockers']=['Animation native lifecycle and patched-ARM regression review pending',
          'Private phone OTA gate not pinned to ANIM60; do not bypass it',
          'Explicit flash authorization required']
        report['unresolved']=['Single-frame derivative not yet device tested',
          'Original 12-frame source preserved outside the linked AP payload',
          'Native render-idle and long-term thermal/power behavior need device validation']
    if music_runtime:
        report['kind']='TMU1-offline-experimental-candidate'
        report['menuProfile']='native-ten-TDP1-TNV1-TMU1'
        report['musicProfile']={'protocol':'TMU1','file':'turbo-music.tmu','packetMax':4096,'menuIndex':9,'cover':[144,144],'lyricsBytes':24576,'linesMax':192,'canvasFPS':30,'idleModes':[0,30,60],'replyCommand':'turbo_music_v1'}
        report['sourceInputs'] += [{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())} for p in sorted((SRC/'music-runtime-v1').glob('*.h'))]
        report['readyBlockers']=['Music/menu ARM and host tests pending','Matching phone package pending','Fresh flash authorization required']
        report['unresolved']=['New music page and native audio/controls not device validated','Background relaunch and transfer throughput require physical tests']
    report.update(kind='TWR1-offline-experimental-candidate',menuProfile='native-eleven-TDP1-TNV1-TMU1-TWR1')
    report['readerProfile']={'protocol':'TWR1','menuIndex':10,'banksBytes':49152,'cover':[64,88],'booksPerPage':4,'speedMaxCPM':480,'packetMax':512,'leaseMs':90000}
    report['sourceInputs'] += [{'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())} for p in sorted((SRC/'weread-v1').glob('*.[ch]'))]
    report['readyBlockers']=['Reader native lifecycle/menu/phone verification pending','Fresh explicit flash authorization required']
    put(out/'report.json',json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['candidateAP','candidateAPBytes','moduleVA','moduleBytes','unchangedPayloads','archive','unresolved']}))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--wide',action='store_true');p.add_argument('--native-eight',action='store_true');p.add_argument('--display-runtime',action='store_true');a=p.parse_args()
    build(a.output.resolve(),a.wide,a.native_eight,a.display_runtime)
