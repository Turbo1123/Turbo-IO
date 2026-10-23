// Mechanical transformation of a private, locally supplied APK derivative.
// Does not remove login, signature checks, certificate pinning or app licensing.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {profileFor,verifyHost} from './host-profiles.mjs';
import {queueHook,fileHook,EVENT_GUARD,OTA_106,OTA_107} from './ota-hooks.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const source=process.argv[2];
if(!source) throw new Error('Usage: node android-addon/package.mjs /path/to/supported-RayNeo.apk');
const sha=crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex');
const profile=profileFor(sha),host=path.join(root,'build',profile.directory);
const OTA_ABI={'1.0.6':OTA_106,'1.0.7':OTA_107};
if(!OTA_ABI[profile.version])throw new Error('TVP2 builder only supports pinned 1.0.6 (216) / 1.0.7 (230)');
if(!fs.existsSync(host)) execFileSync('apktool',['d','--no-res','--output',host,source],{stdio:'inherit'});
// No writes until every required callback/transport descriptor has been checked.
const abi=verifyHost(host,profile);
const otaAbi=OTA_ABI[profile.version];
if(abi.ota){fs.writeFileSync(abi.ota.queue,queueHook(fs.readFileSync(abi.ota.queue,'utf8'),otaAbi));fs.writeFileSync(abi.ota.sender,fileHook(fs.readFileSync(abi.ota.sender,'utf8'),otaAbi));}

function wrap(file,name,signature,args,returnMode) {
  let text=fs.readFileSync(file,'utf8');
  const original='turboioOriginal_'+name;
  const header='.method public final '+name+signature;
  // Replace our generated wrapper on repeated builds, retain the original body.
  if(text.includes(original+'(')) {
    const start=text.indexOf(header+'\n');
    if(start<0)throw new Error('Generated wrapper missing');
    const end=text.indexOf('.end method',start);
    text=text.slice(0,start)+text.slice(end+'.end method'.length);
  } else {
  if(text.split(header).length!==2) throw new Error('Method signature mismatch: '+name);
  text=text.replace(header,'.method public final '+original+signature);
  }
  const className=text.match(/^\.class[^\n]* (L[^;]+;)$/m)?.[1];
  if(!className) throw new Error('Class header missing');
  const invoke='invoke-virtual/range {'+args+'}, '+className+'->'+original+signature;
  const map={onAsrResult:'dispatchAsr(Ljava/lang/Object;Ljava/lang/String;ZLjava/lang/String;)V',
    onNlpResult:'dispatchNlp(Ljava/lang/Object;Ljava/lang/Object;)V',onResponseComplete:'dispatchComplete(Ljava/lang/Object;)V',
    onPostResume:'install(Landroid/app/Activity;)V',
    onNotificationPosted:'notificationPosted(Ljava/lang/Object;Landroid/service/notification/StatusBarNotification;)V',
    onNotificationRemoved:'notificationRemoved(Ljava/lang/Object;Landroid/service/notification/StatusBarNotification;)V'};
  // Observers run after the original and never affect it; the ASR/NLP hooks own dispatch instead.
  const after=['onPostResume','onNotificationPosted','onNotificationRemoved'].includes(name);
  const bridge='invoke-static/range {'+args+'}, Lcom/turboio/addon/TurboAddon;->'+map[name];
  const body=!after
    ? `    :turboio_try\n    ${bridge}\n    :turboio_try_end\n    return-void\n    :turboio_error\n    move-exception v0\n    ${invoke}\n    return-void`
    : `    ${invoke}\n    :turboio_try\n    ${bridge}\n    :turboio_try_end\n    return-void\n    :turboio_error\n    move-exception v0\n    return-void`;
  text+='\n'+header+'\n    .locals 1\n'+body+'\n    .catch Ljava/lang/Throwable; {:turboio_try .. :turboio_try_end} :turboio_error\n.end method\n';
  fs.writeFileSync(file,text);
}
const listener=abi.listener;
wrap(listener,'onAsrResult','(Ljava/lang/String;ZLjava/lang/String;)V','p0 .. p3','after');
wrap(listener,'onNlpResult','(Lcom/rayneo/airuntime/controller/NlpResult;)V','p0 .. p1','guard');
wrap(listener,'onResponseComplete','()V','p0 .. p0','guard');
wrap(abi.activity,'onPostResume','()V','p0 .. p0','after');
wrap(abi.notifications,'onNotificationPosted','(Landroid/service/notification/StatusBarNotification;)V','p0 .. p1','after');
wrap(abi.notifications,'onNotificationRemoved','(Landroid/service/notification/StatusBarNotification;)V','p0 .. p1','after');
// Preserve official event delivery; observe bounded file and custom ACK metadata afterward.
const eventFile=abi.event;
let eventText=fs.readFileSync(eventFile,'utf8');
const eventHeader='.method public final z(Ljava/lang/String;Ljava/util/Map;)V';
if(eventText.includes('turboioOriginal_z(')) {
  const start=eventText.indexOf(eventHeader+'\n');if(start<0)throw new Error('Missing event wrapper');
  const end=eventText.indexOf('.end method',start);eventText=eventText.slice(0,start)+eventText.slice(end+11);
} else {
  if(eventText.split(eventHeader).length!==2)throw new Error('Event signature mismatch');
  eventText=eventText.replace(eventHeader,'.method public final turboioOriginal_z(Ljava/lang/String;Ljava/util/Map;)V');
}
eventText+='\n'+eventHeader+`\n    .locals 1
${abi.ota?EVENT_GUARD:''}
    invoke-virtual {p0, p1, p2}, Lcom/rayneo/rayneo_venus_sdk_plugin/j;->turboioOriginal_z(Ljava/lang/String;Ljava/util/Map;)V
    :turboio_nav_try
    invoke-static {p1, p2}, Lcom/turboio/addon/NativeTransfer;->event(Ljava/lang/String;Ljava/util/Map;)V
    :turboio_nav_end
    return-void
    :turboio_nav_error
    move-exception v0
    return-void
    .catch Ljava/lang/Throwable; {:turboio_nav_try .. :turboio_nav_end} :turboio_nav_error
.end method\n`;
fs.writeFileSync(eventFile,eventText);
// 1.0.6/1.0.7 classes2.dex sits at the 64K reference ceiling, so the hooked classes move to
// one new contiguous DEX; vendor bodies stay byte-for-byte apart from the wrappers.
{
  const dexDirs=fs.readdirSync(host).filter(n=>/^smali(?:_classes\d+)?$/.test(n));
  let hookDir=dexDirs.find(n=>fs.existsSync(path.join(host,n,'.turboio-hooks')));
  if(!hookDir){hookDir='smali_classes'+(dexDirs.length+1);fs.mkdirSync(path.join(host,hookDir));fs.writeFileSync(path.join(host,hookDir,'.turboio-hooks'),'');}
  for(const file of [listener,abi.activity,eventFile,...(abi.ota?[abi.ota.queue,abi.ota.sender]:[])]){
    const rel=path.relative(host,file),parts=rel.split(path.sep);
    if(parts[0]===hookDir)continue;
    if(parts[0]!=='smali_classes2')throw new Error('Unexpected hook DEX: '+rel);
    const dest=path.join(host,hookDir,...parts.slice(1));
    fs.mkdirSync(path.dirname(dest),{recursive:true});fs.renameSync(file,dest);
  }
}
const output=path.join(root,'build/TurboIO-RayNeo-'+profile.version+'-unsigned.apk');
const assembled=path.join(root,'build/TurboIO-RayNeo-'+profile.version+'-assembled.apk');
execFileSync('apktool',['b',host,'-o',assembled],{stdio:'inherit'});
const dex=path.join(root,'build/dex/classes.dex');
execFileSync('python3',[path.join(root,'assemble_apk.py'),source,assembled,dex,output,'--public-assets'],{stdio:'inherit'});
execFileSync('python3',[path.join(root,'verify_apk.py'),source,output,'--public-assets'],{stdio:'inherit'});
const report={sourceSha256:sha,sourceVersion:profile.version+' ('+profile.code+')',originalSignaturePreserved:false,
  changes:['ASR observer','NLP/complete guards','onPostResume native entry','bounded event observer; exclusive business9 before-vendor interception','version-pinned OTA queue and file gates','classes4.dex addon','allowlisted public editorial assets and 20 SDK gallery ZIPs','TTS visibility; non-exported task and dedicated OTA foreground services'],
  credentialsBundled:false,outputSha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),
  installed:false,nonRootValidated:false};
fs.writeFileSync(path.join(root,'build/package-report-'+profile.version+'.json'),JSON.stringify(report,null,2)+'\n');
console.log('Unsigned private derivative prepared; signing and non-root acceptance still required.');
