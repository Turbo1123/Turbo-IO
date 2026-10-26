// Mechanical transformation of a private, locally supplied APK derivative.
// Does not remove login, signature checks, certificate pinning or app licensing.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {profileFor,verifyHost} from './host-profiles.mjs';
import {wrapHostCallback as wrap} from './host-callbacks.mjs';
import {fileURLToPath} from 'node:url';
import {restoreOfficialResources,compareOfficialResources} from './package-resources.mjs';
import {queueHook,fileHook,EVENT_GUARD,LOG_CONSUME,OTA_106,OTA_107} from './ota-hooks.mjs';

const root=path.dirname(fileURLToPath(import.meta.url));
const source=process.argv[2];
if(!source) throw new Error('Usage: node android-addon/package.mjs /path/to/supported-RayNeo.apk');
const officialBuffer=fs.readFileSync(source);
const sha=crypto.createHash('sha256').update(officialBuffer).digest('hex');
const apktool=process.env.APKTOOL || 'apktool';
const dex=path.join(root,'build/dex/classes.dex');
if(!fs.existsSync(dex))throw new Error('Build the original addon first: bash android-addon/build.sh');
const profile=profileFor(sha),host=path.join(root,'build',profile.directory);
const OTA_ABI={'1.0.6':OTA_106,'1.0.7':OTA_107};
if(!OTA_ABI[profile.version])throw new Error('TVP2 builder only supports pinned 1.0.6 (216) / 1.0.7 (230)');
if(!fs.existsSync(host)) execFileSync(apktool,['d','--no-res','--output',host,source],{stdio:'inherit'});
// No writes until every required callback/transport descriptor has been checked.
const abi=verifyHost(host,profile);
const otaAbi=OTA_ABI[profile.version];
if(abi.ota){fs.writeFileSync(abi.ota.queue,queueHook(fs.readFileSync(abi.ota.queue,'utf8'),otaAbi));fs.writeFileSync(abi.ota.sender,fileHook(fs.readFileSync(abi.ota.sender,'utf8'),otaAbi));}

const listener=abi.listener;
wrap(listener,'onAsrResult','(Ljava/lang/String;ZLjava/lang/String;)V','p0 .. p3','after');
wrap(listener,'onNlpResult','(Lcom/rayneo/airuntime/controller/NlpResult;)V','p0 .. p1','guard');
wrap(listener,'onResponseComplete','()V','p0 .. p0','guard');
wrap(abi.activity,'onPostResume','()V','p0 .. p0','after');
wrap(abi.notifications,'onNotificationPosted','(Landroid/service/notification/StatusBarNotification;)V','p0 .. p1','after');
wrap(abi.notifications,'onNotificationRemoved','(Landroid/service/notification/StatusBarNotification;)V','p0 .. p1','after');
// Capture the SDK plugin instance for always-on audio: a guarded static call before each return of f.<init>()V.
{
  let text=fs.readFileSync(abi.sdkPlugin,'utf8');
  if(!text.includes('turboio_sdk_try_')){
    const head='.method public constructor <init>()V',start=text.indexOf(head);if(start<0)throw new Error('SDK plugin constructor missing');
    const end=text.indexOf('.end method',start);let body=text.slice(start,end),k=0;
    if(!/\n    \.locals [1-9]/.test(body))throw new Error('SDK plugin constructor has no local register');
    body=body.replace(/\n    return-void\n/g,()=>{k++;return `\n    :turboio_sdk_try_${k}\n    invoke-static {p0}, Lcom/turboio/addon/TurboAddon;->sdkPlugin(Ljava/lang/Object;)V\n    :turboio_sdk_end_${k}\n    .catch Ljava/lang/Throwable; {:turboio_sdk_try_${k} .. :turboio_sdk_end_${k}} :turboio_sdk_catch_${k}\n    return-void\n    :turboio_sdk_catch_${k}\n    move-exception v0\n    return-void\n`;});
    if(k<1)throw new Error('SDK plugin constructor has no return');
    fs.writeFileSync(abi.sdkPlugin,text.slice(0,start)+body+text.slice(end));
  }
}
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
${LOG_CONSUME}    invoke-virtual {p0, p1, p2}, Lcom/rayneo/rayneo_venus_sdk_plugin/j;->turboioOriginal_z(Ljava/lang/String;Ljava/util/Map;)V
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
execFileSync(apktool,['b',host,'-o',assembled],{stdio:'inherit'});
execFileSync('python3',[path.join(root,'assemble_apk.py'),source,assembled,dex,output,'--public-assets'],{stdio:'inherit'});
// Restore compressed official resources after the current multi-DEX/manifest assembly.
const restored=restoreOfficialResources(officialBuffer,fs.readFileSync(output));
const resources=compareOfficialResources(officialBuffer,restored);
if(!resources.officialCount || resources.missing.length || resources.unauthorized.length)
  throw new Error('Official resource verification failed');
fs.writeFileSync(output,restored);
execFileSync('python3',[path.join(root,'verify_apk.py'),source,output,'--public-assets'],{stdio:'inherit'});
const report={sourceSha256:sha,sourceVersion:profile.version+' ('+profile.code+')',originalSignaturePreserved:false,
  changes:['ASR observer','NLP/complete guards','onPostResume native entry','bounded event observer; exclusive business9 before-vendor interception','version-pinned OTA queue and file gates','classes4.dex addon','allowlisted public editorial assets and 20 SDK gallery ZIPs','TTS visibility; non-exported task and dedicated OTA foreground services'],
  ambientFinalCapture:false,ambientUpload:false,ambientReason:'final_listener_unverified',
  resources:{...resources,rawZipEntries:true},
  credentialsBundled:false,outputSha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),
  installed:false,nonRootValidated:false};
fs.writeFileSync(path.join(root,'build/package-report-'+profile.version+'.json'),JSON.stringify(report,null,2)+'\n');
console.log('Unsigned private derivative prepared; signing and non-root acceptance still required.');
