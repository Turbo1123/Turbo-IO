"""Private iPhone test: compile pinned portable receiver, no desktop renderer."""
from pathlib import Path
import concurrent.futures, hashlib, json, subprocess,sys
import os
H=Path(__file__).resolve().parent
D=Path(os.environ.get('TAR_DEPS_DIR',str(H/'build/deps'))).resolve()
U=D/'UxPlay'
HOST='--host' in sys.argv
PLATFORM='macosx' if HOST else 'iphoneos'
SDK=subprocess.check_output(['xcrun','--sdk',PLATFORM,'--show-sdk-path'],text=True).strip()
def run(args):
    p=subprocess.run(list(map(str,args)),capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr[-6000:])
    return p.stdout
def main():
    assert run(['git','-C',U,'rev-parse','HEAD']).strip()=='517cbb1240d9b9f69330c55b957cdd52b4175b2a'
    assert run(['git','-C',D/'libplist','rev-parse','HEAD']).strip()=='2117b8fdb6b4096455bd2041a63e59a028120136'
    out=D/('host-core' if HOST else 'core');out.mkdir(exist_ok=True)
    overlay=out/'overlay';overlay.mkdir(exist_ok=True)
    def patched(name, replacements):
        source=(U/'lib'/name).read_text()
        for old,new in replacements:
            assert old in source,name
            source=source.replace(old,new)
        target=overlay/name;target.parent.mkdir(exist_ok=True,parents=True);target.write_text(source)
        return target
    replacements={
      'dns_sd/dns_sd.c':[
        ('    /* Register the service */','    /* iOS: NSNetService publishes and reports permission/publication errors. */\n    return 0;\n    /* Register the service (unused in this private port). */'),
        ('        free(dnssd);\n    }\n}', '        dnssd->TXTRecordDeallocate(&dnssd->raop_record);\n        dnssd->TXTRecordDeallocate(&dnssd->airplay_record);\n        free(dnssd);\n    }\n}')],
      'raop_rtp_mirror.c':[
        ('int payload_size = byteutils_get_int(packet, 0);','int payload_size = byteutils_get_int(packet, 0);\n            if (payload_size < 0 || payload_size > 2*1024*1024) { conn_reset = true; break; }'),
        ('int nc_len = byteutils_get_int_be(payload_decrypted, nalu_size);','if (payload_size - nalu_size < 5) { valid_data=false; break; }\n                    int nc_len = byteutils_get_int_be(payload_decrypted, nalu_size);'),
        ('if (nc_len < 0 ||','if (nc_len <= 0 ||'),
        ('if (payload_size == 0) {','if (payload_size < 11) {'),
        ('if (!memcmp(payload + 4, hvc1, 4)) {','if (!memcmp(payload + 4, hvc1, 4)) { unsupported_codec=true; break; }\n                if (!memcmp(payload + 4, hvc1, 4)) {'),
        ('short sps_size = byteutils_get_short_be(payload,6);','short sps_size = byteutils_get_short_be(payload,6);\n                    if(sps_size<=0 || sps_size>payload_size-11){conn_reset=true;break;}'),
        ('short pps_size = byteutils_get_short_be(payload, sps_size + 9);','short pps_size = byteutils_get_short_be(payload, sps_size + 9);\n                    if(pps_size<=0 || pps_size>payload_size-sps_size-11){conn_reset=true;break;}')],
      'http_request.c':[
        ('    int complete;','    int complete;\n    size_t total_input;'),
        ('    int ret = llhttp_execute(&request->parser, data, datalen);','    if(datalen>2*1024*1024-request->total_input) return HPE_USER;\n    request->total_input+=datalen;\n    int ret = llhttp_execute(&request->parser, data, datalen);')],
      'raop.c':[
        ('        raop_stop_httpd(raop);','        if(raop->httpd) raop_stop_httpd(raop);'),
        ('        pairing_destroy(raop->pairing);','        if(raop->pairing) pairing_destroy(raop->pairing);'),
        ('        httpd_destroy(raop->httpd);','        if(raop->httpd) httpd_destroy(raop->httpd);')]
    }
    sources=list((D/'libplist/src').glob('*.c'))+list((D/'libplist/libcnary').glob('*.c'))
    sources+=list((U/'lib').glob('*.c'))+list((U/'lib/playfair').glob('*.c'))+list((U/'lib/llhttp').glob('*.c'))+[U/'lib/dns_sd/dns_sd.c']
    for name,changes in replacements.items():sources[sources.index(U/'lib'/name)]=patched(name,changes)
    flags=['xcrun','--sdk',PLATFORM,'clang','-arch','arm64','-isysroot',SDK,('-mmacosx-version-min=14.0' if HOST else '-miphoneos-version-min=16.0'),'-O2','-fvisibility=hidden','-fPIC','-Wno-deprecated-declarations',
           '-DPLIST_210','-DPLIST_230','-DPACKAGE_VERSION="2.6.0"','-DHAVE_STRNDUP','-DHAVE_GMTIME_R','-DHAVE_LOCALTIME_R','-DHAVE_TIMEGM','-DHAVE_STRPTIME','-DHAVE_MEMMEM','-DHAVE_TM_TM_GMTOFF','-DHAVE_TM_TM_ZONE','-DNOHOLD','-DOPENSSL_API_COMPAT=0x10101000L']
    for p in [D/'libplist/include',D/'libplist/src',D/'libplist/libcnary/include',U/'lib',U/'lib/playfair',U/'lib/llhttp',Path('/opt/homebrew/opt/openssl@3/include') if HOST else D/'openssl-3.5.4/include']:
        flags+=['-I',str(p)]
    def compile_one(src):
        obj=out/(hashlib.sha256(str(src).encode()).hexdigest()[:12]+'.o')
        run(flags+['-c',str(src),'-o',str(obj)])
        return obj
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: objects=list(pool.map(compile_one,sources))
    run(['xcrun','libtool','-static','-o',out/'libReceiver.a',*objects])
    (out/'build.json').write_text(json.dumps({'uxplay':'517cbb1240d9b9f69330c55b957cdd52b4175b2a','libplist':'2117b8fdb6b4096455bd2041a63e59a028120136','sources':len(sources),'sdk':SDK,'platform':PLATFORM+'-arm64','desktopRenderer':False},indent=2)+'\n')
    print('Built iOS receiver core:',len(sources),'translation units')
if __name__=='__main__':main()
