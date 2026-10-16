import fs from 'node:fs';
import path from 'node:path';

// Obfuscated host ABI per pinned build. 1.0.6 shifted every package and two method names.
const ABI_105=Object.freeze({transport:'E3',sdk:'P3',core:'Q3',listener:'LH7/c$c;',queue:'LE3/V;',send:'u',file:'v'});
const ABI_106=Object.freeze({transport:'X3',sdk:'i4',core:'j4',listener:'Lp8/c$c;',queue:'LX3/U;',send:'t',file:'u'});
export const PROFILES = Object.freeze({
  ef2e7dd346ca478e13d0f3f1bf31fa61412e44fb9b4ca9cf0d3e864ac608584b:
    Object.freeze({version:'1.0.4', code:195, directory:'host-104', abi:ABI_105}),
  '770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3':
    Object.freeze({version:'1.0.5', code:201, directory:'host-105', abi:ABI_105}),
  '4c1c57ae811cb959478efb5ec510000f7f51ddcb427afff369b1582c66b60206':
    Object.freeze({version:'1.0.6', code:216, directory:'host-106', abi:ABI_106}),
});
export function profileFor(sha) {
  const profile=PROFILES[sha];
  if(!profile)throw new Error('Unsupported APK SHA256; no host mutations performed');
  return profile;
}
// Apktool suffixes u.1.smali on case-insensitive APFS when U.smali exists.
// Resolve by the exact DEX descriptor, never by case-insensitive filename alone.
export function classFile(root,descriptor) {
  if(!/^L[A-Za-z0-9_$/]+;$/.test(descriptor))throw new Error('Invalid descriptor');
  const relative=descriptor.slice(1,-1),folder=path.dirname(relative),name=path.basename(relative);
  const matches=[];
  for(const dex of fs.readdirSync(root).filter(n=>/^smali(?:_classes\d+)?$/.test(n))) {
    const directory=path.join(root,dex,folder);
    if(!fs.existsSync(directory))continue;
    for(const f of fs.readdirSync(directory)) {
      if(!f.endsWith('.smali')||!(f===name+'.smali'||f.startsWith(name+'.')))continue;
      const full=path.join(directory,f),text=fs.readFileSync(full,'utf8');
      if(text.split('\n').some(line=>line.startsWith('.class ')&&line.endsWith(' '+descriptor)))matches.push(full);
    }
  }
  if(matches.length!==1)throw new Error('Expected one exact class: '+descriptor);
  return matches[0];
}
export function verifyHost(root,profile) {
  const expect=(descriptor,lines)=>{
    const file=classFile(root,descriptor),text=fs.readFileSync(file,'utf8');
    for(const line of lines)if(!text.split('\n').includes(line))throw new Error('Host ABI mismatch: '+descriptor+' '+line);
    return file;
  };
  const abi=profile.abi||ABI_105,T='L'+abi.transport+'/',S='L'+abi.sdk+'/',C='L'+abi.core+'/';
  const listener=expect(abi.listener,[
    '.method public final onAsrResult(Ljava/lang/String;ZLjava/lang/String;)V',
    '.method public final onNlpResult(Lcom/rayneo/airuntime/controller/NlpResult;)V',
    '.method public final onResponseComplete()V']);
  const activity=expect('Lcom/rayneo/venus/MainActivity;',['.method public final onPostResume()V']);
  const event=expect('Lcom/rayneo/rayneo_venus_sdk_plugin/j;',['.method public final z(Ljava/lang/String;Ljava/util/Map;)V']);
  const sendHeader='.method public final '+abi.send+'('+T+'Q;Lkotlin/jvm/functions/Function2;)V';
  const fileHeader='.method public final '+abi.file+'(Ljava/io/File;Ljava/lang/String;'+C+'q;Ljava/lang/String;)Ljava/lang/String;';
  expect(T+'u;',[
    '.field public static volatile h:'+T+'u;',
    '.method public static g()Ljava/util/List;',
    sendHeader,fileHeader]);
  expect(T+'Q;',['.method public constructor <init>([BLjava/lang/String;Ljava/lang/String;'+S+'h;'+S+'Q;'+T+'b;ZZ'+C+'p;Lkotlin/jvm/functions/Function2;)V']);
  expect(T+'C;',['.field public final a:Ljava/lang/String;','.method public final b()Z']);
  expect('Lcom/amap/api/maps/MapsInitializer;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/location/AMapLocationClient;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/services/core/ServiceSettings;',['.method public static getInstance()Lcom/amap/api/services/core/ServiceSettings;', '.method public setApiKey(Ljava/lang/String;)V']);
  for(const [descriptor,value] of [[S+'h;','AI_SUBTITLE'],[S+'h;','LAUNCHER'],[S+'h;','TELEPROMPTER'],[T+'b;','NORMAL'],[C+'q;','SmallCore']]) {
    const source=fs.readFileSync(classFile(root,descriptor),'utf8');
    if(!source.includes('"'+value+'"'))throw new Error('Missing enum '+value);
  }
  let ota;
  if(profile.version!=='1.0.4'){
    const queueHeader='.method public static o('+T+'Q;)V';
    const queue=expect(abi.queue,[queueHeader]);
    const sender=classFile(root,T+'u;');
    expect(T+'Q;',['.field public final b:Ljava/lang/String;','.field public final c:'+S+'h;','.field public final e:[B','.field public k:Lkotlin/jvm/functions/Function2;']);
    expect(S+'A;',['.field public static final enum r:'+S+'A;']);
    if(!fs.readFileSync(classFile(root,S+'A;'),'utf8').includes('"MESSAGE_SEND_FAILED"'))throw new Error('Missing MESSAGE_SEND_FAILED');
    if(!fs.readFileSync(classFile(root,S+'h;'),'utf8').includes('"MARS_FOTA"'))throw new Error('Missing MARS_FOTA');
    ota={queue,sender,queueClass:abi.queue,senderClass:T+'u;',message:T+'Q;',queueHeader,fileHeader,fileMethod:abi.file};
  }
  return {listener,activity,event,ota,abi,version:profile.version,code:profile.code};
}
