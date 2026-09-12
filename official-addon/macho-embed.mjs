// Private copy preparation, not DRM decryption or code signing.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';

export function inspectMachO(bytes) {
  if(bytes.length<32||bytes.readUInt32LE(0)!==0xfeedfacf||bytes.readUInt32LE(4)!==0x100000c)throw Error('Expected thin arm64 Mach-O');
  const count=bytes.readUInt32LE(16),size=bytes.readUInt32LE(20),end=32+size;
  if(count>1024||end>bytes.length)throw Error('Invalid Mach-O header bounds');
  let p=32,uuid=null,encrypted=false,firstContent=bytes.length,installName=null;
  const dependencies=[];
  for(let i=0;i<count;i++) {
    if(p+8>end)throw Error('Truncated load command');
    const cmd=bytes.readUInt32LE(p),n=bytes.readUInt32LE(p+4);
    if(n<8||n%8||p+n>end)throw Error('Invalid load command length');
    if(cmd===0x1b){if(n!==24)throw Error('Invalid UUID');uuid=bytes.subarray(p+8,p+24).toString('hex');}
    if(cmd===0x21||cmd===0x2c){if(n<20)throw Error('Invalid encryption command');encrypted ||= bytes.readUInt32LE(p+16)!==0;}
    if(cmd===0x19){
      if(n<72)throw Error('Invalid segment');const sections=bytes.readUInt32LE(p+64);
      if(72+sections*80>n)throw Error('Truncated sections');
      for(let j=0;j<sections;j++){const at=p+72+j*80,off=bytes.readUInt32LE(at+48),length=Number(bytes.readBigUInt64LE(at+40));if(off&&length)firstContent=Math.min(firstContent,off);}
    }
    if([0xc,0xd,0x80000018,0x8000001f,0x80000023].includes(cmd)){
      if(n<24)throw Error('Invalid dylib command');const at=bytes.readUInt32LE(p+8),zero=bytes.indexOf(0,p+at);
      if(at<24||at>=n||zero<p+at||zero>=p+n)throw Error('Invalid dylib name');const name=bytes.toString('utf8',p+at,zero);if(cmd===0xd)installName=name;else dependencies.push(name);
    }
    p+=n;
  }
  if(p!==end)throw Error('Load command size mismatch');
  return {count,size,end,uuid,encrypted,firstContent,dependencies,installName,fileType:bytes.readUInt32LE(12)};
}

export function addEmbeddedLoad(bytes) {
  const info=inspectMachO(bytes),name='@executable_path/Frameworks/TurboIOPrivateAddon.dylib';
  if(info.encrypted)throw Error('Encrypted executable: provide an authorized usable research copy; this tool does not decrypt it');
  if(info.fileType!==2)throw Error('Only an executable can receive this load command');
  if(info.dependencies.includes(name)||info.dependencies.some(x=>x.endsWith('/TurboIOPrivateAddon.dylib')))throw Error('Addon is already referenced');
  const encoded=Buffer.from(name+'\0'),length=Math.ceil((24+encoded.length)/8)*8;
  if(info.firstContent===bytes.length||info.end+length>info.firstContent||info.end+length>bytes.length)throw Error('Insufficient verified header padding');
  if(bytes.subarray(info.end,info.end+length).some(x=>x!==0))throw Error('Header padding is not empty');
  const result=Buffer.from(bytes);result.writeUInt32LE(0xc,info.end);result.writeUInt32LE(length,info.end+4);result.writeUInt32LE(24,info.end+8);encoded.copy(result,info.end+24);
  result.writeUInt32LE(info.count+1,16);result.writeUInt32LE(info.size+length,20);
  const after=inspectMachO(result);if(after.uuid!==info.uuid||!after.dependencies.includes(name))throw Error('Post-patch verification failed');
  return result;
}

function prepare() {
  const [sourceArg,outArg,addonArg,bundle]=process.argv.slice(2);
  if(!sourceArg||!outArg||!addonArg||!bundle||process.argv.length!==6)throw Error('Usage: node macho-embed.mjs /absolute/Runner.app /absolute/new/Runner.app /absolute/embedded/TurboIOPrivateAddon.dylib your.bundle.id');
  if(![sourceArg,outArg,addonArg].every(path.isAbsolute)||![sourceArg,outArg].every(x=>x.endsWith('.app')))throw Error('Use absolute app and addon paths');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(bundle))throw Error('Invalid explicit Bundle ID');
  const source=fs.realpathSync(sourceArg),out=path.resolve(outArg),addon=fs.realpathSync(addonArg);
  if(out===source||out.startsWith(source+path.sep)||fs.existsSync(out))throw Error('Output must be a new separate app directory');
  const plist=p=>JSON.parse(execFileSync('plutil',['-convert','json','-o','-',p],{encoding:'utf8'}));
  const info=plist(path.join(source,'Info.plist'));
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleShortVersionString!=='1.0.2'||String(info.CFBundleVersion)!=='67'||info.CFBundleExecutable!=='Runner')throw Error('Unsupported official source app');
  const exe=path.join(source,'Runner'),original=fs.readFileSync(exe),header=inspectMachO(original);
  if(header.uuid!=='eeea85e54114313cb65173c90a6b5d3c')throw Error('Unsupported Runner UUID');
  const embedded=fs.readFileSync(addon),addonInfo=inspectMachO(embedded);
  if(addonInfo.fileType!==6||addonInfo.installName!=='@rpath/TurboIOPrivateAddon.dylib'||addonInfo.encrypted||addonInfo.dependencies.some(x=>/\/var\/jb\/|frida|ellekit|substrate/i.test(x)))throw Error('Use the embedded addon build, with no jailbreak runtime dependency');
  if(!embedded.includes(Buffer.from(bundle+'\0')))throw Error('Build addon for exactly the requested Bundle ID');
  const patched=addEmbeddedLoad(original),inventory=[];
  function walk(dir){for(const name of fs.readdirSync(dir)){const p=path.join(dir,name),st=fs.lstatSync(p);if(st.isSymbolicLink())throw Error('Review bundle symlinks before preparing');if(st.isDirectory()){if(name==='PlugIns')throw Error('Source has app extensions; separate signing/entitlement review required');walk(p);}else {const b=fs.readFileSync(p);if(b.length>=4&&[0xcafebabe,0xbebafeca,0xcafebabf,0xbfbafeca].includes(b.readUInt32BE(0)))throw Error('Fat Mach-O needs slice-by-slice review before preparing');if(b.length>=4&&b.readUInt32LE(0)===0xfeedfacf){const h=inspectMachO(b);if(h.encrypted)throw Error('Encrypted embedded image: '+path.relative(source,p));inventory.push(path.relative(source,p));}}}}
  walk(source); // Complete preflight before creating any output.
  fs.mkdirSync(path.dirname(out),{recursive:true});fs.cpSync(source,out,{recursive:true,force:false,errorOnExist:true,dereference:false});
  fs.writeFileSync(path.join(out,'Runner'),patched);
  fs.mkdirSync(path.join(out,'Frameworks'),{recursive:true});fs.copyFileSync(addon,path.join(out,'Frameworks/TurboIOPrivateAddon.dylib'),fs.constants.COPYFILE_EXCL);
  execFileSync('plutil',['-replace','CFBundleIdentifier','-string',bundle,path.join(out,'Info.plist')]);
  if(plist(path.join(out,'Info.plist')).CFBundleIdentifier!==bundle)throw Error('Bundle ID update failed');
  const hash=b=>createHash('sha256').update(b).digest('hex');
  const report={status:'PREPARED_ONLY_NOT_SIGNED_NOT_INSTALLABLE',originalExecutableSHA256:hash(original),preparedExecutableSHA256:hash(patched),addonSHA256:hash(embedded),binaryCount:inventory.length,uuid:header.uuid,sourcePreserved:hash(fs.readFileSync(exe))===hash(original),requires:['matching developer provisioning profile','review entitlements for every nested code bundle','sign nested code then app','non-jailbroken hardware acceptance']};
  fs.writeFileSync(path.join(out,'TurboIOPrivatePreparation.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});
  console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))prepare();
