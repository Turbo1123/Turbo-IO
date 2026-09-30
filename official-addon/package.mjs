#!/usr/bin/env node
// Local-only source-release packager. Does not download, decrypt or upload apps.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync as exec } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {amapResources,copyAMapResources} from './amap-resources.mjs';
import {validateTranslationPair,prepareTranslationResources,copyTranslationResources} from './local-translation/package-resources.mjs';
import {patch as patchExperimentalOTA} from '../firmware-research/strix-1.0.4.12/src/patch-ios105-ota-source.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
export function validateOptions(o) {
  for(const k of ['app','addon','profile','out'])if(typeof o[k]!=='string'||!path.isAbsolute(o[k]))throw Error('absolute_paths_required');
  if(!o.app.endsWith('.app')||o.out.endsWith('.app'))throw Error('use_app_input_and_new_output_directory');
  if(!/^[a-f0-9]{40}$/i.test(o.identity||'')||!/^[a-z0-9-]{8,80}$/i.test(o.device||''))throw Error('explicit_identity_and_device_required');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(o.bundle||''))throw Error('invalid_bundle');
  if(o.product&&!/^iPhone\d+,\d+$/.test(o.product))throw Error('invalid_explicit_product');
  if(fs.existsSync(o.out))throw Error('output_must_not_exist');
  if(o['experimental-ota']!==undefined&&(!['R3','TNV1','TMU1','TFP1'].includes(o['experimental-ota'])||o.bundle!=='com.rayneo.venus.pub'))throw Error('invalid_experimental_ota_target');
  if(['TNV1','TMU1','TFP1'].includes(o['experimental-ota']) && (typeof o.firmware!=='string'||!path.isAbsolute(o.firmware)))throw Error('research_requires_explicit_firmware');
  if(o.firmware && !['TNV1','TMU1','TFP1'].includes(o['experimental-ota']))throw Error('unexpected_firmware');
}
export function validateResearchPair(symbols, kind, firmware) {
  const native=symbols.includes('_TNVStart');
  const music=symbols.includes('_TMMusicConsume');
  const focus=symbols.includes('_TFFocusConsume');
  if(native!==['TNV1','TMU1','TFP1'].includes(kind)||music!==['TMU1','TFP1'].includes(kind)||focus!==(kind==='TFP1'))throw Error('native_addon_and_option_must_match');
  if(kind==='TFP1' && (!Buffer.isBuffer(firmware)||firmware.length!==9300112||createHash('sha256').update(firmware).digest('hex')!=='ad5054e3d7bda90e94d293bea882bd8dd5a125bcc8f42c13a59b2e149313c9e3'))throw Error('tfp1_firmware_identity_mismatch');
  if(kind==='TNV1' && (!Buffer.isBuffer(firmware)||firmware.length!==9258094||
    createHash('sha256').update(firmware).digest('hex')!=='e2a76fdcf0d3d07d766a7329d2d93b32350cb8309b73fc9c73726498fafddecb'))throw Error('tnv1_firmware_identity_mismatch');
  if(kind==='TMU1' && (!Buffer.isBuffer(firmware)||firmware.length!==9468398||
    createHash('sha256').update(firmware).digest('hex')!=='307a0d41aa76b3ed91a8fcc07b09329d76d78a51584c9954c7896d64b1ad9a81'))throw Error('tmu1_firmware_identity_mismatch');
}
export function entitlementsFor(p,o) {
  if(!Array.isArray(p.certs)||!p.certs.includes(o.identity.toUpperCase())||!Array.isArray(p.devices)||!p.devices.includes(o.device)||!(Date.parse(p.expires)>Date.now()))throw Error('profile_identity_device_or_expiry_mismatch');
  const e=structuredClone(p.entitlements), appID=e?.['application-identifier'];
  if(typeof appID!=='string'||(!appID.endsWith('.*')&&!appID.endsWith('.'+o.bundle)))throw Error('profile_bundle_mismatch');
  e['application-identifier']=appID.endsWith('.*')?appID.slice(0,-1)+o.bundle:appID;
  if(e['keychain-access-groups'])e['keychain-access-groups']=e['keychain-access-groups'].map(x=>x.endsWith('.*')?x.slice(0,-1)+o.bundle:x);
  return e; // Never synthesize official push, app groups or sign-in permissions.
}
function run(program,args,options={}){return exec(program,args,{stdio:['pipe','pipe','pipe'],...options});}
function main(){
  if(process.argv.includes('--help'))console.log('FOCUS-04 integrated edition: --experimental-ota TFP1 --firmware /absolute/exact-FOCUS04-release.zip; see focus-edition/README.md. Optional translation resources may be omitted for this edition.');
  if(process.argv.includes('--help'))console.log('Optional local translation: --translation-module-dir /absolute/module --translation-models /absolute/models (requires TIO_LOCAL_TRANSLATION=1 addon; see local-translation/README.md)');
  if(process.argv.includes('--help')){console.log('node official-addon/package.mjs --app /absolute/Runner.app --addon /absolute/TurboIOPrivateAddon.dylib --profile /absolute/profile.mobileprovision --identity CERTIFICATE_SHA1 --device YOUR_DEVICE_ID --out /absolute/new-private-output [--bundle com.rayneo.venus.pub] [--product iPhone18,4] [--amap-sdk-root /absolute/build/amap-sdk] [--experimental-ota R3|TNV1|TMU1 --firmware /absolute/matching-firmware.zip (required for TNV1/TMU1; HIGH RISK)]');return;}
  const o={bundle:'com.rayneo.venus.pub'};const args=process.argv.slice(2);
  if(args.length%2)throw Error('expected_named_arguments');
  const seen=new Set();for(let i=0;i<args.length;i+=2){const k=args[i].slice(2);if(!args[i].startsWith('--')||!['app','addon','profile','identity','device','out','bundle','product','amap-sdk-root','experimental-ota','firmware','translation-module-dir','translation-models'].includes(k)||seen.has(k))throw Error('unknown_or_duplicate_argument');seen.add(k);o[k]=args[i+1];}
  validateOptions(o);
  const mapResources=o['amap-sdk-root']?amapResources(o['amap-sdk-root']):[];
  const symbols=run('/usr/bin/nm',['-g',o.addon],{encoding:'utf8',maxBuffer:64*1024*1024});
  // FOCUS has a dynamic optional entry even without the translation module.
  const focusEdition=symbols.includes('_TFFocusConsume');
  validateTranslationPair(focusEdition&&!o['translation-module-dir']&&!o['translation-models']?symbols.replaceAll('_TIOOpenLocalTranslation',''):symbols,o);
  const translationResources=prepareTranslationResources(o);
  if(symbols.includes('OBJC_CLASS_$_AMapNaviWalkManager')&&!mapResources.length)throw Error('amap_resources_option_required');
  const source=fs.realpathSync(o.app),destination=path.resolve(o.out);
  const researchAddon=symbols.includes('_TIOOTAFlashBuild');
  if(researchAddon!==Boolean(o['experimental-ota']))throw Error('research_addon_and_explicit_option_must_match');
  const firmware=o.firmware?fs.readFileSync(o.firmware):undefined;
  validateResearchPair(symbols,o['experimental-ota'],firmware);
  let otaPatch;
  if(o['experimental-ota']){
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(source,'Info.plist')],{encoding:'utf8'}));
    if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleShortVersionString!=='1.0.5'||info.CFBundleVersion!=='201'||info.TIOExperimentalOTAQueryRouting)throw Error('experimental_ota_requires_original_ios105');
    otaPatch=patchExperimentalOTA(fs.readFileSync(path.join(source,'Frameworks/App.framework/App')));
  }
  if(destination===source||destination.startsWith(source+path.sep))throw Error('output_must_be_separate');
  if(['TurboIOPrivateBootstrap.json','TurboIOKnowledgeConnection.json','TIOAMapPrivate.json'].some(n=>fs.existsSync(path.join(source,n))))throw Error('source_contains_private_bootstrap');
  const profile=JSON.parse(run('python3',['-c',`import sys,plistlib,json,hashlib,subprocess
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
print(json.dumps({'entitlements':p['Entitlements'],'expires':p['ExpirationDate'].isoformat()+'Z','devices':p.get('ProvisionedDevices',[]),'certs':[hashlib.sha1(x).hexdigest().upper() for x in p['DeveloperCertificates']]}))`,o.profile],{encoding:'utf8'}));
  const entitlement=entitlementsFor(profile,o);
  fs.mkdirSync(destination,{mode:0o700});
  const app=path.join(destination,'Payload','Runner.app');
  run(process.execPath,[path.join(here,'macho-embed.mjs'),source,app,o.addon,o.bundle]);
  if(focusEdition){
    fs.cpSync(path.join(here,'focus-edition/TurboIOArt'),path.join(app,'TurboIOArt'),{recursive:true,errorOnExist:true,force:false});
  }
  copyTranslationResources(translationResources,app);
  if(translationResources){
    const plist=path.join(app,'Info.plist');
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSMicrophoneUsageDescription)run('plutil',['-insert','NSMicrophoneUsageDescription','-string','在用户主动开启英语离线字幕时使用所选麦克风；停止后结束收音。',plist]);
  }
  const permissionsPlist=path.join(app,'Info.plist');
  const permissionsInfo=JSON.parse(run('plutil',['-convert','json','-o','-',permissionsPlist],{encoding:'utf8'}));
  for(const [key,message] of Object.entries({
    NSRemindersUsageDescription:'将你明确创建的 Turbo IO 待办写入苹果提醒事项。',
    NSRemindersFullAccessUsageDescription:'将你明确创建的 Turbo IO 待办和日程写入苹果提醒事项。',
    NSCalendarsUsageDescription:'将你明确创建的 Turbo IO 日程写入苹果日历。',
    NSCalendarsWriteOnlyAccessUsageDescription:'将你明确创建的 Turbo IO 日程写入苹果日历。'
  }))if(!permissionsInfo[key])run('plutil',['-insert',key,'-string',message,permissionsPlist]);
  if(otaPatch){
    fs.writeFileSync(path.join(app,'Frameworks/App.framework/App'),otaPatch.output);
    const plist=path.join(app,'Info.plist');
    const music=['TMU1','TFP1'].includes(o['experimental-ota']);
    run('plutil',['-insert','TIOExperimentalOTAQueryRouting','-string',focusEdition?'ios105-tfp1-loopback-flash-gated':music?'ios105-tmu1-loopback-flash-gated':o['experimental-ota']==='TNV1'?'ios105-tnv1-loopback-flash-gated':'ios105-r3-loopback-flash-gated',plist]);
    run('plutil',['-insert','TIOExperimentalOTABuild','-string',focusEdition?'FOCUS-04-SOURCE':music?'TMU1-SOURCE-01':o['experimental-ota']==='TNV1'?'TNV1-SOURCE-01':'R3-SOURCE-RESEARCH-01',plist]);
    if(firmware)fs.writeFileSync(path.join(app,focusEdition?'TurboWeReadCandidate.zip':music?'TurboMusicCandidate.zip':'TurboNavigationCandidate.zip'),firmware,{flag:'wx'});
    if(music){
      fs.copyFileSync(path.join(here,'music/Beans-MIT-LICENSE.txt'),path.join(app,'TurboMusic-Beans-MIT-LICENSE.txt'));
      const musicInfo=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
      const modes=musicInfo.UIBackgroundModes||[];
      if(!modes.includes('audio'))run('plutil',musicInfo.UIBackgroundModes?['-insert','UIBackgroundModes.0','-string','audio',plist]:['-insert','UIBackgroundModes','-json','["audio"]',plist]);
    }
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSAppTransportSecurity)run('plutil',['-insert','NSAppTransportSecurity','-dictionary',plist]);
    if(info.NSAppTransportSecurity?.NSAllowsLocalNetworking===undefined)run('plutil',['-insert','NSAppTransportSecurity.NSAllowsLocalNetworking','-bool','YES',plist]);
    fs.writeFileSync(path.join(destination,'experimental-ota-routing.json'),JSON.stringify(otaPatch.report,null,2)+'\n',{flag:'wx',mode:0o600});
  }
  if(mapResources.length){copyAMapResources(mapResources,app);const plist=path.join(app,'Info.plist');const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));if(!info.NSLocationWhenInUseUsageDescription)run('plutil',['-insert','NSLocationWhenInUseUsageDescription','-string','用于用户主动选择的地图定位和前台步行导航。',plist]);}
  if(o.product){const plist=path.join(app,'Info.plist');const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));if(Array.isArray(info.UISupportedDevices)&&!info.UISupportedDevices.includes(o.product))run('plutil',['-insert','UISupportedDevices.0','-string',o.product,plist]);}
  const ep=path.join(destination,'signing-entitlements.plist');
  run('python3',['-c','import sys,json,plistlib; plistlib.dump(json.load(sys.stdin),open(sys.argv[1],"wb"))',ep],{input:JSON.stringify(entitlement)});fs.chmodSync(ep,0o600);
  fs.copyFileSync(o.profile,path.join(app,'embedded.mobileprovision'));
  const nested=[];function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,entry.name);if(entry.isSymbolicLink())throw Error('symlink_requires_review');if(entry.isDirectory()){walk(p);if(entry.name.endsWith('.framework'))nested.push(p);}else if(entry.name.endsWith('.dylib'))nested.push(p);}}
  walk(path.join(app,'Frameworks'));
  for(const p of nested)run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der',p]);
  run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der','--entitlements',ep,app]);
  run('codesign',['--verify','--deep','--strict',app]);
  const ipa=path.join(destination,'TurboIO-local-only.ipa');
  run('/usr/bin/ditto',['-c','-k','--norsrc','--noextattr','--keepParent',path.join(destination,'Payload'),ipa]);fs.chmodSync(ipa,0o600);
  run('/usr/bin/unzip',['-tq',ipa]);
  const names=run('/usr/bin/unzip',['-Z1',ipa],{encoding:'utf8'}).split('\n');if(names.some(n=>n.split('/').some(x=>x==='__MACOSX'||x.startsWith('._'))))throw Error('unexpected_archive_metadata');
  const report={status:'SIGNED_NOT_DEVICE_ACCEPTED',signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,experimentalOTA:!!otaPatch,flashAuthorized:false,ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']};
  fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){try{main();}catch(e){const known=/^[a-z_]+$/.test(e.message);console.error(known?e.message:'Local packaging failed. Check compatible source, profile and signing identity. No subprocess output or credentials are printed.');process.exitCode=1;}}
