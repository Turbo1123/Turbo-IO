// Mechanical transformation of a private, locally supplied APK derivative.
// Does not remove login, signature checks, certificate pinning or app licensing.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {profileFor,verifyHost} from './host-profiles.mjs';
import {queueHook,fileHook,EVENT_GUARD} from './ota-hooks.mjs';
import {wrapHostCallback as wrap} from './host-callbacks.mjs';
import {fileURLToPath} from 'node:url';
import {restoreOfficialResources,compareOfficialResources} from './package-resources.mjs';

const root=path.dirname(fileURLToPath(import.meta.url));
const source=process.argv[2];
if(!source) throw new Error('Usage: node android-addon/package.mjs /path/to/supported-RayNeo.apk');
const apktool=process.env.APKTOOL || 'apktool';
const dex=path.join(root,'build/dex/classes.dex');
if(!fs.existsSync(dex))throw new Error('Build the original addon first: bash android-addon/build.sh');
const officialBuffer=fs.readFileSync(source);
const sha=crypto.createHash('sha256').update(officialBuffer).digest('hex');
const profile=profileFor(sha),host=path.join(root,'build',profile.directory);
if(profile.version!=='1.0.5')throw new Error('INTEGRATION-07 OTA adapter only supports pinned 1.0.5 (201); use the prior builder for 1.0.4');
if(!fs.existsSync(host)) execFileSync(apktool,['d','--no-res','--output',host,source],{stdio:'inherit'});
// No writes until every required callback/transport descriptor has been checked.
const abi=verifyHost(host,profile);
if(abi.ota){fs.writeFileSync(abi.ota.queue,queueHook(fs.readFileSync(abi.ota.queue,'utf8')));fs.writeFileSync(abi.ota.sender,fileHook(fs.readFileSync(abi.ota.sender,'utf8')));}

const listener=abi.listener;
wrap(abi.alwaysOn,'onAlwaysOnResponse','(Lcom/rayneo/airuntime/controller/RayNeoAlwaysOnResponse;)V','p0 .. p1');
wrap(listener,'onAsrResult','(Ljava/lang/String;ZLjava/lang/String;)V','p0 .. p3','after');
wrap(listener,'onNlpResult','(Lcom/rayneo/airuntime/controller/NlpResult;)V','p0 .. p1','guard');
wrap(listener,'onResponseComplete','()V','p0 .. p0','guard');
wrap(abi.activity,'onPostResume','()V','p0 .. p0','after');
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
const output=path.join(root,'build/TurboIO-RayNeo-'+profile.version+'-unsigned.apk');
const assembled=path.join(root,'build/TurboIO-RayNeo-'+profile.version+'-assembled.apk');
execFileSync(apktool,['b',host,'-o',assembled],{stdio:'inherit'});
execFileSync('python3',[path.join(root,'assemble_apk.py'),source,assembled,dex,output,'--public-assets'],{stdio:'inherit'});
// Keep exact compressed official res entries after adding reviewed assets/manifest.
const restored=restoreOfficialResources(officialBuffer,fs.readFileSync(output));
const resources=compareOfficialResources(officialBuffer,restored);
if(!resources.officialCount || resources.missing.length || resources.unauthorized.length)
  throw new Error('Official resource verification failed');
fs.writeFileSync(output,restored);
execFileSync('python3',[path.join(root,'verify_apk.py'),source,output,'--public-assets'],{stdio:'inherit'});
const report={sourceSha256:sha,sourceVersion:profile.version+' ('+profile.code+')',originalSignaturePreserved:false,
  changes:['AlwaysOn final-text listener','ASR observer','NLP/complete guards','onPostResume native entry','bounded event observer; exclusive business9 before-vendor interception','version-pinned OTA queue and file gates','classes4.dex addon','allowlisted public editorial assets and 20 SDK gallery ZIPs','TTS visibility; non-exported task and dedicated OTA foreground services'],
  resources:{...resources,rawZipEntries:true},
  credentialsBundled:false,outputSha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),
  installed:false,nonRootValidated:false};
fs.writeFileSync(path.join(root,'build/package-report-'+profile.version+'.json'),JSON.stringify(report,null,2)+'\n');
console.log('Unsigned private derivative prepared; signing and non-root acceptance still required.');
