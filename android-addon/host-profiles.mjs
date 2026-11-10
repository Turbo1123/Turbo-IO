import fs from 'node:fs';
import path from 'node:path';

// Obfuscated host ABI per pinned build. 1.0.6 shifted every package and two method names;
// 1.0.7 shifted packages again and the transport message class became S.
const ABI_106=Object.freeze({transport:'X3',sdk:'i4',core:'j4',listener:'Lp8/c$c;',queue:'LX3/U;',send:'t',file:'u',message:'Q',alwaysOn:'Ll8/l;'});
const ABI_107=Object.freeze({transport:'Y3',sdk:'j4',core:'k4',listener:'Lq8/c$c;',queue:'LY3/V;',send:'t',file:'u',message:'S',alwaysOn:'Lm8/k;'});
export const PROFILES = Object.freeze({
  '4c1c57ae811cb959478efb5ec510000f7f51ddcb427afff369b1582c66b60206':
    Object.freeze({version:'1.0.6', code:216, directory:'host-106', abi:ABI_106}),
  '30239f65d910cf7008cfdf6cfacd5c068c5877068b4a637027786377a9ce4f91':
    Object.freeze({version:'1.0.7', code:230, directory:'host-107', abi:ABI_107}),
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
  const abi=profile.abi,T='L'+abi.transport+'/',S='L'+abi.sdk+'/',C='L'+abi.core+'/',M=T+abi.message+';';
  const listener=expect(abi.listener,[
    '.method public final onAsrResult(Ljava/lang/String;ZLjava/lang/String;)V',
    '.method public final onNlpResult(Lcom/rayneo/airuntime/controller/NlpResult;)V',
    '.method public final onResponseComplete()V']);
  // Voice exit: the listener's outer voice controller and its official stop_assistant entry.
  const voiceStop=abi.listener.replace('$c;',';');
  expect(abi.listener,['.field public final synthetic a:'+voiceStop]);
  {let text;try{text=fs.readFileSync(classFile(root,voiceStop),'utf8');}catch(e){throw new Error('Host ABI mismatch: voice stop entry '+voiceStop);}const head='.method public final s(Ljava/lang/String;ZZ)V',at=text.split('\n').indexOf(head);
   const body=at<0?'':text.split('\n').slice(at,at+400).join('\n'),end=body.indexOf('.end method');
   if(at<0||end<0||!body.slice(0,end).includes('"stop_assistant"'))throw new Error('Host ABI mismatch: voice stop entry '+voiceStop);}
  const activity=expect('Lcom/rayneo/venus/MainActivity;',['.method public final onPostResume()V']);
  // Notification history observes the host's own NotificationListenerService (original runs first).
  const notifications=expect('Lim/zoe/labs/flutter_notification_listener/NotificationsHandlerService;',[
    '.method public final onNotificationPosted(Landroid/service/notification/StatusBarNotification;)V',
    '.method public final onNotificationRemoved(Landroid/service/notification/StatusBarNotification;)V']);
  const event=expect('Lcom/rayneo/rayneo_venus_sdk_plugin/j;',['.method public final z(Ljava/lang/String;Ljava/util/Map;)V']);
  // Always-on audio: the SDK plugin's controller (field y) with configureDump f(ZZZZ) and status k().
  const sdkPlugin=expect('Lcom/rayneo/rayneo_venus_sdk_plugin/f;',['.method public constructor <init>()V','.field public final y:'+abi.alwaysOn]);
  expect(abi.alwaysOn,['.method public final f(ZZZZ)V','.method public final k()Ljava/util/LinkedHashMap;']);
  const sendHeader='.method public final '+abi.send+'('+M+'Lkotlin/jvm/functions/Function2;)V';
  const fileHeader='.method public final '+abi.file+'(Ljava/io/File;Ljava/lang/String;'+C+'q;Ljava/lang/String;)Ljava/lang/String;';
  expect(T+'u;',[
    '.field public static volatile h:'+T+'u;',
    '.method public static g()Ljava/util/List;',
    sendHeader,fileHeader]);
  expect(M,['.method public constructor <init>([BLjava/lang/String;Ljava/lang/String;'+S+'h;'+S+'Q;'+T+'b;ZZ'+C+'p;Lkotlin/jvm/functions/Function2;)V']);
  expect(T+'C;',['.field public final a:Ljava/lang/String;','.method public final b()Z']);
  // Phase 3b todo replay: official NLP result/command are constructed and filled by reflection.
  expect('Lcom/rayneo/airuntime/controller/NlpResult;',['.method public constructor <init>()V','.method public final setCommand(Lcom/rayneo/airuntime/controller/NlpCommand;)V','.method public final getCommand()Lcom/rayneo/airuntime/controller/NlpCommand;']);
  expect('Lcom/rayneo/airuntime/controller/NlpCommand;',['.method public constructor <init>()V','.method public final setName(Ljava/lang/String;)V','.method public final setParams(Ljava/util/Map;)V','.method public final setCommandRequestId(Ljava/lang/String;)V','.method public final setOtherState(Ljava/util/Map;)V','.method public final getParams()Ljava/util/Map;']);
  expect('Lcom/amap/api/maps/MapsInitializer;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/location/AMapLocationClient;',['.method public static setApiKey(Ljava/lang/String;)V']);
  expect('Lcom/amap/api/services/core/ServiceSettings;',['.method public static getInstance()Lcom/amap/api/services/core/ServiceSettings;', '.method public setApiKey(Ljava/lang/String;)V']);
  for(const [descriptor,value] of [[S+'h;','AI_SUBTITLE'],[S+'h;','LAUNCHER'],[S+'h;','TELEPROMPTER'],[S+'h;','LOG_REPORT'],[S+'h;','SCHEDULE_TODO'],[T+'b;','NORMAL'],[C+'q;','SmallCore']]) {
    const source=fs.readFileSync(classFile(root,descriptor),'utf8');
    if(!source.includes('"'+value+'"'))throw new Error('Missing enum '+value);
  }
  let ota;
  {
    const queueHeader='.method public static o('+M+')V';
    const queue=expect(abi.queue,[queueHeader]);
    const sender=classFile(root,T+'u;');
    expect(M,['.field public final b:Ljava/lang/String;','.field public final c:'+S+'h;','.field public final e:[B','.field public k:Lkotlin/jvm/functions/Function2;']);
    expect(S+'A;',['.field public static final enum r:'+S+'A;']);
    if(!fs.readFileSync(classFile(root,S+'A;'),'utf8').includes('"MESSAGE_SEND_FAILED"'))throw new Error('Missing MESSAGE_SEND_FAILED');
    if(!fs.readFileSync(classFile(root,S+'h;'),'utf8').includes('"MARS_FOTA"'))throw new Error('Missing MARS_FOTA');
    ota={queue,sender,queueClass:abi.queue,senderClass:T+'u;',message:M,queueHeader,fileHeader,fileMethod:abi.file};
  }
  // No verified final-transcript listener on these hosts. abi.alwaysOn is the
  // audio dump controller, not the old onAlwaysOnResponse listener.
  return {listener,activity,event,ota,abi,voiceStop,notifications,sdkPlugin,ambientFinalListener:null,version:profile.version,code:profile.code};
}
