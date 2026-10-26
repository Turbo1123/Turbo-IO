"""Build GPL receiver SDK; never merges/signs a vendor app or touches a device."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tarfile,urllib.request
H=Path(__file__).resolve().parent
def run(a,**kw):subprocess.run(list(map(str,a)),check=True,**kw)
def main():
 p=argparse.ArgumentParser();p.add_argument('--deps',type=Path,default=H/'build/deps');p.add_argument('--prepare',action='store_true');args=p.parse_args();d=args.deps.resolve();d.mkdir(parents=True,exist_ok=True)
 lock=json.loads((H/'upstream.lock.json').read_text());sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
 if args.prepare:
  for key,name in (('uxplay','UxPlay'),('libplist','libplist')):
   if not (d/name).exists():run(['git','clone',lock[key]['repository'],d/name]);run(['git','-C',d/name,'checkout','--detach',lock[key]['commit']])
   assert subprocess.check_output(['git','-C',d/name,'rev-parse','HEAD'],text=True).strip()==lock[key]['commit']
  archive=d/'openssl.tar.gz'
  if not archive.exists():urllib.request.urlretrieve(lock['openssl']['url'],archive)
  assert hashlib.sha256(archive.read_bytes()).hexdigest()==lock['openssl']['sha256']
  if not (d/'openssl-3.5.4').exists():
   with tarfile.open(archive) as z:z.extractall(d,filter='data')
  openssl=d/'openssl-3.5.4'
  with (d/'openssl-ios.log').open('wb') as log:
   run(['./Configure','ios64-cross','no-shared','no-tests','no-apps','no-module','no-dso','-miphoneos-version-min=16.0','-isysroot',sdk],cwd=openssl,stdout=log,stderr=subprocess.STDOUT);run(['make','-j8','build_libs'],cwd=openssl,stdout=log,stderr=subprocess.STDOUT)
 assert (d/'openssl-3.5.4/libcrypto.a').exists(),'Run --prepare first (or supply pinned iOS dependencies)'
 env=dict(os.environ,TAR_DEPS_DIR=str(d));run(['python3',H/'build_core.py'],env=env)
 out=H/'build/sdk';out.mkdir(parents=True,exist_ok=True);objects=[]
 flags=['xcrun','--sdk','iphoneos','clang','-arch','arm64','-isysroot',sdk,'-miphoneos-version-min=16.0','-O2','-fobjc-arc','-fmodules','-fvisibility=hidden','-I',H,'-I',d/'UxPlay/lib','-I',d/'libplist/include']
 for i,n in enumerate(('TAR2Module.m','airplay-v1/Receiver.m','airplay-v1/AnnexB.c','airplay-hd-v1/FrameEncoder.m','airplay-hd-v1/HDLink.m','video-player-v1/player.c')):
  obj=out/(str(i)+'.o');run([*flags,'-c',H/n,'-o',obj]);objects.append(obj)
 run(['xcrun','libtool','-static','-o',out/'libTurboAirPlay.a',*objects,d/'core/libReceiver.a',d/'openssl-3.5.4/libcrypto.a'])
 # Link smoke only, not a distributable/signed vendor integration.
 run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-isysroot',sdk,'-miphoneos-version-min=16.0','-dynamiclib','-Wl,-all_load',out/'libTurboAirPlay.a','-framework','Foundation','-framework','UIKit','-framework','CoreVideo','-framework','CoreMedia','-framework','VideoToolbox','-framework','Accelerate','-o',out/'link-smoke.dylib'])
 (out/'build-report.json').write_text(json.dumps({'passed':True,'platform':'iOS-arm64','minimumOS':'16.0','signed':False,'hostMerged':False,'hardwareTested':False},indent=2)+'\n');print('GPL receiver SDK compiled and link-smoke passed; no device I/O')
if __name__=='__main__':main()
