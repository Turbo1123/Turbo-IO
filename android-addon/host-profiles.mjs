import fs from 'node:fs';
import path from 'node:path';

export const PROFILES = Object.freeze({
  ef2e7dd346ca478e13d0f3f1bf31fa61412e44fb9b4ca9cf0d3e864ac608584b:
    Object.freeze({version:'1.0.4', code:195, directory:'host-104'}),
  '770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3':
    Object.freeze({version:'1.0.5', code:201, directory:'host-105'}),
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
  const listener=expect('LH7/c$c;',[
    '.method public final onAsrResult(Ljava/lang/String;ZLjava/lang/String;)V',
    '.method public final onNlpResult(Lcom/rayneo/airuntime/controller/NlpResult;)V',
    '.method public final onResponseComplete()V']);
  const activity=expect('Lcom/rayneo/venus/MainActivity;',['.method public final onPostResume()V']);
  const event=expect('Lcom/rayneo/rayneo_venus_sdk_plugin/j;',['.method public final z(Ljava/lang/String;Ljava/util/Map;)V']);
  expect('LE3/u;',[
    '.field public static volatile h:LE3/u;',
    '.method public static g()Ljava/util/List;',
    '.method public final u(LE3/Q;Lkotlin/jvm/functions/Function2;)V',
    '.method public final v(Ljava/io/File;Ljava/lang/String;LQ3/q;Ljava/lang/String;)Ljava/lang/String;']);
  expect('LE3/Q;',['.method public constructor <init>([BLjava/lang/String;Ljava/lang/String;LP3/h;LP3/Q;LE3/b;ZZLQ3/p;Lkotlin/jvm/functions/Function2;)V']);
  expect('Lcom/amap/api/maps/MapsInitializer;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/location/AMapLocationClient;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/services/core/ServiceSettings;',['.method public static getInstance()Lcom/amap/api/services/core/ServiceSettings;', '.method public setApiKey(Ljava/lang/String;)V']);
  for(const [descriptor,value] of [['LP3/h;','AI_SUBTITLE'],['LP3/h;','LAUNCHER'],['LE3/b;','NORMAL']]) {
    const source=fs.readFileSync(classFile(root,descriptor),'utf8');
    if(!source.includes('"'+value+'"'))throw new Error('Missing enum '+value);
  }
  let ota;
  if(profile.version==='1.0.5'){
    const queue=expect('LE3/V;',['.method public static o(LE3/Q;)V']);
    const sender=classFile(root,'LE3/u;');
    expect('LE3/Q;',['.field public final b:Ljava/lang/String;','.field public final c:LP3/h;','.field public final e:[B','.field public k:Lkotlin/jvm/functions/Function2;']);
    expect('LP3/A;',['.field public static final enum r:LP3/A;']);
    if(!fs.readFileSync(classFile(root,'LP3/h;'),'utf8').includes('"MARS_FOTA"'))throw new Error('Missing MARS_FOTA');
    ota={queue,sender};
  }
  return {listener,activity,event,ota,version:profile.version,code:profile.code};
}
