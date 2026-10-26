"""Sanitize an already-decrypted, pinned stock bundle. No decryption or signing.

Never operates on a device or in place. Rejects unknown/encrypted/modified code.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import zipfile

APP_PIN='fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e'
UUID='410defdbf93739eaacf2f616abff9d0b'
SIGN_DIRS={'_CodeSignature','SC_Info','_MASReceipt','__MACOSX'}
SIGN_FILES={'embedded.mobileprovision','iTunesMetadata.plist','iTunesArtwork','iTunesArtwork@2x','CodeResources','.DS_Store'}
SIGN_KEYS={'SignerIdentity','DTTeamIdentifier','ApplicationIdentifier','TeamIdentifier','com.apple.developer.team-identifier','application-identifier','ProvisionedDevices','provisioningProfiles','SigningIdentity'}

def sha(data):return hashlib.sha256(data).hexdigest()
def file_sha(p):
    digest=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()

def macho(b):
    if b[:4]!=bytes.fromhex('cffaedfe'):return None
    assert len(b)>=32 and struct.unpack_from('<I',b,4)[0]==0x100000c
    count,size=struct.unpack_from('<II',b,16);assert count<1024 and 32+size<=len(b)
    at=32;signature=None;uuid=None;first=len(b);normalized=[];deps=[];sections=[]
    for _ in range(count):
        cmd,n=struct.unpack_from('<II',b,at);assert n>=8 and n%8==0 and at+n<=32+size
        raw=bytearray(b[at:at+n])
        if cmd==0x1d:
            assert n==16 and signature is None
            signature=struct.unpack_from('<II',raw,8)
            assert signature[0]+signature[1]<=len(b)
        else:
            if cmd==0x1b:assert n==24;uuid=bytes(raw[8:24]).hex()
            if cmd in (0x21,0x2c):assert struct.unpack_from('<I',raw,16)[0]==0,'Encrypted input rejected; this is not a decryption tool'
            if cmd==0x19:
                assert n>=72
                seg=bytes(raw[8:24]).rstrip(b'\0');ns=struct.unpack_from('<I',raw,64)[0]
                assert 72+ns*80<=n
                for j in range(ns):
                    p=72+j*80;length=struct.unpack_from('<Q',raw,p+40)[0];off=struct.unpack_from('<I',raw,p+48)[0]
                    if off and length:
                        # Zero-fill sections have no on-disk content.
                        flags=struct.unpack_from('<I',raw,p+64)[0]&0xff
                        if flags not in (1,0xc,0x12):
                            assert off+length<=len(b);first=min(first,off);sections.append((off,length))
                if seg==b'__LINKEDIT':raw[32:40]=bytes(8);raw[48:56]=bytes(8)
            if cmd in (0xc,0x80000018,0x8000001f,0x80000023):
                pos=struct.unpack_from('<I',raw,8)[0];assert 24<=pos<n
                name=bytes(raw[pos:]).split(b'\0')[0]
                assert not re.search(rb'TurboIO|frida|substrate|ellekit|/var/jb/',name,re.I),'Injected input rejected'
                deps.append(name)
            normalized.append(bytes(raw))
        at+=n
    assert at==32+size
    return dict(signature=signature,uuid=uuid,first=first,commands=normalized,deps=deps,sections=sections,
                header=b[:16]+b[24:32],fileType=struct.unpack_from('<I',b,12)[0])

def executable_unchanged(before,after):
    a,b=macho(before),macho(after)
    assert a and b and b['signature'] is None
    for key in ('uuid','commands','deps','header','sections'):assert a[key]==b[key],key
    for at,n in a['sections']:assert before[at:at+n]==after[at:at+n]
    end=a['signature'][0] if a['signature'] else len(before)
    common=min(end,len(after));assert before[a['first']:common]==after[a['first']:common]
    if len(after)<end:assert not any(before[len(after):end])
    if len(after)>end:assert not any(after[end:])

def stripped_path(relative):
    return any(p in SIGN_DIRS or p.startswith('._') for p in relative.parts) or relative.name in SIGN_FILES or relative.suffix.lower() in ('.mobileprovision','.p12','.pfx')

def private_markers(profile):
    if not profile:return []
    p=subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True)
    assert p.returncode==0,'Cannot inspect local privacy reference'
    info=plistlib.loads(p.stdout);values=set(info.get('TeamIdentifier',[]))|set(info.get('ProvisionedDevices',[]))
    values.update(str(x) for x in info.get('DeveloperName',[]) if isinstance(info.get('DeveloperName'),list))
    e=info.get('Entitlements',{})
    if e.get('com.apple.developer.team-identifier'):values.add(e['com.apple.developer.team-identifier'])
    return [s.encode() for s in values if isinstance(s,str) and len(s)>=8]

def main():
    assert __debug__,'Do not disable verification with python -O'
    p=argparse.ArgumentParser();p.add_argument('--app',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--private-profile',type=Path);p.add_argument('--decrypted-runner',type=Path);a=p.parse_args()
    source=a.app.resolve();out=a.out.resolve()
    assert source.is_dir() and source.name=='Runner.app' and not out.exists()
    assert out!=source and source not in out.parents
    info=plistlib.loads((source/'Info.plist').read_bytes())
    assert (info['CFBundleIdentifier'],info['CFBundleShortVersionString'],info['CFBundleVersion'])==('com.rayneo.venus.pub','1.0.7','230')
    assert not any(k.startswith(('TIO','TurboIO')) for k in info)
    assert file_sha(source/'Frameworks/App.framework/App')==APP_PIN
    main_input=(a.decrypted_runner if a.decrypted_runner else source/'Runner').read_bytes()
    assert sha(main_input)=='c416d939c90745b170027171844e3275faf5e502306746176375dee5837aadcf','Unknown decrypted Runner'
    assert macho(main_input)['uuid']==UUID
    if a.decrypted_runner:
        # Accept an EXISTING decrypted file, never decrypt or patch encryption here.
        encrypted=(source/'Runner').read_bytes();assert len(encrypted)==len(main_input)
        pos=32;crypt=None
        for _ in range(struct.unpack_from('<I',encrypted,16)[0]):
            cmd,n=struct.unpack_from('<II',encrypted,pos)
            if cmd==0x2c:
                offset,length,ident=struct.unpack_from('<III',encrypted,pos+8)
                assert ident==1;crypt=(offset,offset+length,pos+16,pos+20)
            pos+=n
        assert crypt
        lo,hi,c,d=crypt
        assert encrypted[:c]==main_input[:c] and encrypted[d:lo]==main_input[d:lo] and encrypted[hi:]==main_input[hi:]
    original={};images=[]
    for f in source.rglob('*'):
        assert not f.is_symlink(),'Review symlink before exporting'
        if not f.is_file():continue
        rel=f.relative_to(source);assert not any(n.startswith(('TurboIO','TIOAMap','TIOWeRead','TurboMusic')) for n in rel.parts),'Private addition rejected'
        data=f.read_bytes();original[str(rel)]=sha(data)
        assert data[:4] not in (bytes.fromhex('cafebabe'),bytes.fromhex('bebafeca'),bytes.fromhex('cafebabf'),bytes.fromhex('bfbafeca')),'Fat Mach-O requires separate review'
        m=macho(main_input if str(rel)=='Runner' else data)
        if m:images.append(rel)
    markers=private_markers(a.private_profile)
    out.mkdir(parents=True,mode=0o700);(out/'Payload').mkdir()
    target=out/'Payload/Runner.app'
    subprocess.run(['cp','-cR',str(source),str(target)],check=True)
    if a.decrypted_runner:(target/'Runner').write_bytes(main_input)
    removed=[]
    # Exact targets only inside the new derivative. Original source is never edited.
    for f in sorted(target.rglob('*'),key=lambda x:len(x.parts),reverse=True):
        rel=f.relative_to(target)
        if stripped_path(rel):
            if f.is_file():f.unlink();removed.append(str(rel))
            elif f.is_dir():f.rmdir()
    stripped=0
    for rel in images:
        before=main_input if str(rel)=='Runner' else (source/rel).read_bytes();m=macho(before)
        if m['signature']:
            result=subprocess.run(['codesign','--remove-signature',str(target/rel)],capture_output=True)
            assert result.returncode==0,'Signature removal failed: '+str(rel)
            stripped+=1
        executable_unchanged(before,(target/rel).read_bytes())
    changed_plists=[]
    for f in target.rglob('*.plist'):
        try:value=plistlib.loads(f.read_bytes())
        except Exception:continue
        if isinstance(value,dict) and any(k in value for k in SIGN_KEYS):
            value={k:v for k,v in value.items() if k not in SIGN_KEYS}
            f.write_bytes(plistlib.dumps(value,fmt=plistlib.FMT_BINARY));changed_plists.append(str(f.relative_to(target)))
    preserved=0
    for f in target.rglob('*'):
        if not f.is_file():continue
        rel=f.relative_to(target);assert not stripped_path(rel)
        data=f.read_bytes()
        assert (b'PRIVATE '+b'KEY-----') not in data
        assert not any(s in data for s in markers),'Personal signing reference found: '+str(rel)
        if rel not in images and str(rel) not in changed_plists:assert sha(data)==original[str(rel)];preserved+=1
    assert plistlib.loads((target/'Info.plist').read_bytes())['CFBundleShortVersionString']=='1.0.7'
    print(json.dumps({'machOImages':len(images),'signaturesRemoved':stripped,'preservedResources':preserved,'removedMetadataFiles':len(removed)}),flush=True)
    archive=out/'RayNeo_AI_1.0.7_230_decrypted_unsigned_original.ipa'
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for f in sorted(target.rglob('*')):
            if f.is_file():
                name='Payload/Runner.app/'+str(f.relative_to(target));zi=zipfile.ZipInfo(name,(2026,10,19,0,0,0))
                zi.compress_type=zipfile.ZIP_DEFLATED;zi.create_system=3
                zi.external_attr=(0o100755 if f.relative_to(target) in images else 0o100644)<<16
                z.writestr(zi,f.read_bytes(),compresslevel=6)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names))
        for name in names:
            rel=Path(name).relative_to('Payload/Runner.app');assert not stripped_path(rel)
            assert sha(z.read(name))==file_sha(target/rel)
    for name,digest in original.items():assert file_sha(source/name)==digest,'Source was modified'
    report={'version':'1.0.7','build':'230','bundleID':'com.rayneo.venus.pub','architectures':['arm64'],
        'alreadyDecryptedInput':True,'encryptedMachOImages':0,'machOImages':len(images),
        'codeSignaturesRemaining':0,'machOCodeAndDependenciesPreserved':True,'sourcePreserved':True,
        'signaturesRemoved':stripped,'signatureAndStoreMetadataFilesRemoved':len(removed),
        'signingMetadataPlistsCleaned':len(changed_plists),'otherResourcesPreserved':preserved,
        'privateSigningReferenceChecked':bool(markers),'personalSigningReferenceMatches':0,
        'containsTurboIO':False,'developerSigned':False,'directlyInstallable':False,
        'appFrameworkSHA256':file_sha(target/'Frameworks/App.framework/App'),
        'runnerSHA256':file_sha(target/'Runner'),'runnerUUID':UUID,
        'archive':{'name':archive.name,'bytes':archive.stat().st_size,'sha256':file_sha(archive)},
        'zipCRCVerified':True,'archiveMembersVerified':len(names),
        'scope':'Original stock app functionality; already decrypted, code signing/store metadata removed. Not App Store byte-identical; not an app data backup. Vendor rights unchanged.'}
    (out/'audit.json').write_text(json.dumps(report,indent=2)+'\n')
    (out/'SHA256SUMS').write_text(report['archive']['sha256']+'  '+archive.name+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
