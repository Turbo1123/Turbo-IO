"""Reproduce exact tested TVP2 from official ZIP. Never connects to a device."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
FLASH = 0x10190000


def sha(data, algorithm='sha256'):
    return hashlib.new(algorithm, data).hexdigest()


def run(arguments):
    r = subprocess.run([str(a) for a in arguments], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr)
    return r.stdout


def safe_zip(path, expected):
    assert sha(path.read_bytes()) == expected, 'Wrong input archive'
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        assert len(names) == len(set(names)) == 16
        assert all(n == Path(n).name and not n.startswith('.') for n in names)
        assert sum(i.file_size for i in z.infolist()) < 24_000_000
        assert all((i.external_attr >> 16) & 0o170000 != 0o120000 for i in z.infolist())
        assert z.testzip() is None
        files = {n: z.read(n) for n in names}
    rows = json.loads(files['OtaFileInfo.json'])
    assert isinstance(rows, list) and len(rows) == 15
    assert len({r['Name'] for r in rows}) == 15
    assert set(files) == {r['Name'] for r in rows} | {'OtaFileInfo.json'}
    for r in rows:
        b = files[r['Name']]
        assert len(b) == r['Size'] and sha(b, 'md5') == r['Md5']
    return files, rows


def audit(stock_path, candidate_path):
    spec = json.loads((HERE / 'build-inputs.json').read_text())
    stock, before = safe_zip(stock_path, spec['stockZIP'])
    files, after = safe_zip(candidate_path, spec['archive']['sha256'])
    ap = files['nuttx_ap.bin']
    base = stock['nuttx_ap.bin']
    assert len(ap) == spec['APBytes'] and sha(ap) == spec['APSHA256']
    assert len(ap) < 9_600_000
    assert [r['Name'] for r in before] == [r['Name'] for r in after]
    for old, new in zip(before, after):
        if old['Name'] == 'nuttx_ap.bin':
            assert {k:v for k,v in old.items() if k not in ('Size','Md5')} == {k:v for k,v in new.items() if k not in ('Size','Md5')}
        else:
            assert old == new and stock[old['Name']] == files[new['Name']]
    assert ap[:16] == base[:16] and ap[-8:] == base[-8:]
    for at in (0x408, 0x414, 0x574, 0x580, 0x58c, 0x598, 0x674):
        assert ap[at:at+12] == base[at:at+12]
    allowed = set()
    for e in spec['edits']:
        at = int(e['offset'], 16)
        a, b = bytes.fromhex(e['before']), bytes.fromhex(e['after'])
        assert len(a) == len(b) and base[at:at+len(a)] == a and ap[at:at+len(b)] == b
        assert not allowed.intersection(range(at, at+len(b)))
        allowed.update(range(at, at+len(b)))
    assert len(spec['edits']) == 40
    assert all(x == y or i in allowed for i, (x,y) in enumerate(zip(base[:-8],ap)))
    at = int(spec['moduleVA'], 16) - FLASH
    assert not any(ap[len(base)-8:at])
    assert sha(ap[at:at+spec['moduleBytes']]) == spec['moduleSHA256']
    assert not any(ap[at+spec['moduleBytes']:-8])
    return {'passed':True, 'baseline':'1.0.5.5','customChangedPayloads':['nuttx_ap.bin'],
        'unchangedNewStockPayloads':14,'manifestPayloads':15,'archiveEntries':16,
        'APBytes':len(ap),'APSHA256':sha(ap),'APMD5':sha(ap,'md5'),
        'archiveSHA256':sha(candidate_path.read_bytes()),'archiveMD5':sha(candidate_path.read_bytes(),'md5'),
        'whitelistedPatches':40,'startupDescriptorsPreserved':7,'deviceIO':False}


def build(stock_path, llvm, out):
    spec = json.loads((HERE / 'build-inputs.json').read_text())
    stock, rows = safe_zip(stock_path, spec['stockZIP'])
    assert sha(stock['nuttx_ap.bin']) == spec['stockAP']
    assert not out.exists(), 'Choose a fresh output directory'
    out.mkdir(parents=True)
    src = HERE / 'src'
    flags = ['--target=arm-none-eabi','-mcpu=cortex-m33','-mthumb','-mfloat-abi=hard',
        '-mfpu=fpv5-sp-d16','-ffreestanding','-fno-builtin',
        '-Os','-Wall','-Wextra','-Werror',
        '-I',str(src),'-I',str(src/'app-runtime-v1/arm-include'),'-I',str(HERE/'include'),
        '-include',str(src/'firmware_profile.h'),'-DTIO_IMAGE_RX_WIDE=1',
        '-DTIO_DISPLAY_RUNTIME=1','-DTDP_FREESTANDING','-DTIO_ANIMATION_EXPERIMENT=1',
        '-DTIO_MUSIC_RUNTIME=1','-DTD_DIAGNOSTICS_RUNTIME=1','-DTD_FREESTANDING=1',
        '-DTD_STOCK_10412=0','-DTD_STOCK_1055=1']
    objects = []
    animation = HERE/'assets/animation-frames.l8'
    assert sha(animation.read_bytes()) == 'f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d'
    asm = out/'animation-asset.S'
    asm.write_text('.section .rodata.ta_asset,"a",%progbits\n.balign 64\n.global ta_asset\n.type ta_asset,%object\nta_asset:\n.incbin "'+str(animation)+'", 0, 33792\n.size ta_asset, .-ta_asset\n')
    for i,row in enumerate(spec['sources']):
        p = asm if row['path']=='@generated-animation' else HERE/row['path']
        if row['sha256']:assert sha(p.read_bytes())==row['sha256'], 'Edited source: '+row['path']
        obj = out/(str(i)+'-'+p.stem+'.o')
        run([llvm/'clang',*flags,'-c',p,'-o',obj]);objects.append(obj)
    elf = out/'module.elf'
    run([llvm/'ld.lld','-T',HERE/'link.ld','--entry=m8_hook_ctor',*objects,'-o',elf])
    assert not run([llvm/'llvm-nm','-u',elf]).strip()
    run([llvm/'llvm-objcopy','-O','binary',elf,out/'module.bin'])
    module = (out/'module.bin').read_bytes()
    assert sha(module) == spec['moduleSHA256'], 'Toolchain/source differs from tested module; STOP'
    base = stock['nuttx_ap.bin']; at = int(spec['moduleVA'],16)-FLASH
    ap = bytearray(base[:-8]) + bytearray(at-(len(base)-8)) + module
    ap += bytearray((-len(ap))%4) + base[-8:]
    for e in spec['edits']:
        offset = int(e['offset'],16); old, new = bytes.fromhex(e['before']),bytes.fromhex(e['after'])
        assert ap[offset:offset+len(old)] == old
        ap[offset:offset+len(new)] = new
    assert len(ap) == spec['APBytes'] and sha(ap) == spec['APSHA256']
    stock['nuttx_ap.bin'] = bytes(ap)
    for row in rows:
        if row['Name'] == 'nuttx_ap.bin': row.update(Size=len(ap),Md5=sha(ap,'md5'))
    stock['OtaFileInfo.json'] = (json.dumps(rows,indent=2)+'\n').encode()
    archive = out/spec['archive']['name']
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,data in sorted(stock.items()):
            info = zipfile.ZipInfo(name,(2026,10,16,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=0o100600<<16;z.writestr(info,data,compresslevel=9)
    result = audit(stock_path,archive)
    (out/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--stock',type=Path,required=True)
    parser.add_argument('--audit',type=Path);parser.add_argument('--llvm-bin',type=Path);parser.add_argument('--out',type=Path)
    args = parser.parse_args()
    if args.audit: result = audit(args.stock,args.audit)
    else:
        assert args.llvm_bin and args.out
        result = build(args.stock.resolve(),args.llvm_bin.resolve(),args.out.resolve())
    print(json.dumps(result,indent=2))


if __name__ == '__main__':
    main()
