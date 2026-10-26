"""Offline pinned ZIP/manifest/frame gates. No phone, signing or glasses access."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile
import importlib.util

HERE=Path(__file__).resolve().parent
FW=HERE.parents[1]/'firmware-research/strix-1.0.5.5'

def run(args):
    r=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=120)
    if r.returncode:raise RuntimeError(r.stdout+r.stderr)
    return r.stdout+r.stderr

def main():
    p=argparse.ArgumentParser();p.add_argument('--firmware',type=Path,required=True);p.add_argument('--stock',type=Path,required=True);a=p.parse_args()
    spec=importlib.util.spec_from_file_location('firmware_build',FW/'build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.audit(a.stock,a.firmware)
    tests={}
    with tempfile.TemporaryDirectory(prefix='tmig1-offline-') as d:
        root=Path(d)
        for name,archive in (('candidate',a.firmware),('stock',a.stock)):
            target=root/name;target.mkdir()
            with zipfile.ZipFile(archive) as z:
                for n in z.namelist():
                    assert n==Path(n).name
                    (target/n).write_bytes(z.read(n))
        specs={
            'archive':(['ExperimentalOTATests.m','ExperimentalOTA.m'],[a.firmware,a.stock]),
            'directory':(['ExperimentalOTADirectoryTests.m','ExperimentalOTA.m'],[root/'candidate',root/'stock']),
            'flash':(['ExperimentalOTAFlashTests.m','ExperimentalOTA.m','ExperimentalOTAFlash.m','ExperimentalOTAGuard.m'],[root/'candidate',root/'stock']),
            'feed':(['ExperimentalOTAFeedTests.m','ExperimentalOTA.m','ExperimentalOTAFlash.m','ExperimentalOTAGuard.m','ExperimentalOTAFeed.m'],[a.firmware])}
        for name,(sources,args) in specs.items():
            flags=['-DTIO_OTA_FEED_ARMING_ENABLED=1'] if name=='feed' else []
            run(['xcrun','clang','-fobjc-arc','-fmodules','-Wno-deprecated-declarations','-framework','Foundation','-lz','-I',HERE,*flags,*[HERE/n for n in sources],'-o',root/name.replace('directory','directory-test')])
            binary=root/name.replace('directory','directory-test')
            # Directory fixture shares no executable name with candidate/stock.
            output=run([binary,*args]);tests[name]={'passed':True}
            print(name+': PASS')
    print(json.dumps({'passed':True,'tests':tests,'deviceIO':False}))

if __name__=='__main__':main()
