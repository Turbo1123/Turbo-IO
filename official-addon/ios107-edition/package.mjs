#!/usr/bin/env node
// Local-only source-release packager. Does not download, decrypt or upload apps.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync as exec } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {amapResources,copyAMapResources} from '../amap-resources.mjs';
import {validateTranslationPair,prepareTranslationResources,copyTranslationResources} from '../local-translation/package-resources.mjs';
import {inspectMachO} from './macho-embed.mjs';
import {patch as patchOTARoute,verifyRoute} from './patch-route.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const digest=b=>createHash('sha256').update(b).digest('hex');
export function validateHost(info,runner,appImage){
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleShortVersionString!=='1.0.7'||String(info.CFBundleVersion)!=='230'||Object.keys(info).some(k=>k.startsWith('TIO')))throw Error('requires_original_ios107_230');
  const h=inspectMachO(runner);
  const acceptedPairs=[
    ['c416d939c90745b170027171844e3275faf5e502306746176375dee5837aadcf','fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e'],
    ['765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3','041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d'],
  ];
  if(h.encrypted||h.uuid!=='410defdbf93739eaacf2f616abff9d0b'||!acceptedPairs.some(([r,a])=>digest(runner)===r&&digest(appImage)===a))throw Error('host_image_identity_mismatch');
}
export function validateOptions(o) {
  for(const k of ['app','addon','profile','out'])if(typeof o[k]!=='string'||!path.isAbsolute(o[k]))throw Error('absolute_paths_required');
  if(!o.app.endsWith('.app')||o.out.endsWith('.app'))throw Error('use_app_input_and_new_output_directory');
  if(!/^[a-f0-9]{40}$/i.test(o.identity||'')||!/^[a-z0-9-]{8,80}$/i.test(o.device||''))throw Error('explicit_identity_and_device_required');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(o.bundle||''))throw Error('invalid_bundle');
  if(o.product&&!/^iPhone\d+,\d+$/.test(o.product))throw Error('invalid_explicit_product');
  if(fs.existsSync(o.out))throw Error('output_must_not_exist');
  if(o['experimental-ota']!==undefined&&o['experimental-ota']!=='TMG2')throw Error('only_exact_tmg2_supported');
  if(o.bundle!=='com.rayneo.venus.pub'||typeof o.firmware!=='string'||!path.isAbsolute(o.firmware))throw Error('exact_host_and_firmware_resource_required');
}
export function validateResearchPair(symbols, kind, firmware) {
  if(kind!=='TMG2'||!symbols.includes('_TIOMenuLayoutController')||!symbols.includes('OBJC_CLASS_$_TIORoadMap'))throw Error('ios107_addon_required');
  if(!Buffer.isBuffer(firmware)||firmware.length!==8842896||createHash('sha256').update(firmware).digest('hex')!=='6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473')throw Error('navs3_firmware_identity_mismatch');

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
  if(process.argv.includes('--help'))console.log('iOS 1.0.7/230 APP107: exact TMG2 OTA route included by default. Installation does NOT grant flash permission; manual one-shot authorization required.');
  if(process.argv.includes('--help'))console.log('Optional local translation: --translation-module-dir /absolute/module --translation-models /absolute/models (requires TIO_LOCAL_TRANSLATION=1 addon; see local-translation/README.md)');
  if(process.argv.includes('--help')){console.log('node official-addon/ios107-edition/package.mjs --app /absolute/Runner.app --addon /absolute/TurboIOPrivateAddon.dylib --profile /absolute/profile.mobileprovision --identity CERTIFICATE_SHA1 --device YOUR_DEVICE_ID --out /absolute/new-private-output --bundle com.rayneo.venus.pub --firmware /absolute/exact-TMG2-release.zip [--product iPhone18,2] [--amap-sdk-root /absolute/build/amap-sdk]');return;}
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
  if(!symbols.includes('_TIOOTAFlashBuild')||!fs.readFileSync(o.addon).includes(Buffer.from('display extension=APP107-OTA-PHONE-01;')))throw Error('ios107_addon_marker_required');
  const firmware=o.firmware?fs.readFileSync(o.firmware):undefined;
  validateResearchPair(symbols,'TMG2',firmware);
  const info=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(source,'Info.plist')],{encoding:'utf8'}));
  validateHost(info,fs.readFileSync(path.join(source,'Runner')),fs.readFileSync(path.join(source,'Frameworks/App.framework/App')));
  if(destination===source||destination.startsWith(source+path.sep))throw Error('output_must_be_separate');
  if(['TurboIOPrivateBootstrap.json','TurboIOKnowledgeConnection.json','TIOAMapPrivate.json','TurboIOPrivateTTS.json','TIOWeReadPrivate.json','TurboMusicCookieImport.txt','TurboWeReadCookieImport.txt'].some(n=>fs.existsSync(path.join(source,n))))throw Error('source_contains_private_bootstrap');
  const profile=JSON.parse(run('python3',['-c',`import sys,plistlib,json,hashlib,subprocess
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
print(json.dumps({'entitlements':p['Entitlements'],'expires':p['ExpirationDate'].isoformat()+'Z','devices':p.get('ProvisionedDevices',[]),'certs':[hashlib.sha1(x).hexdigest().upper() for x in p['DeveloperCertificates']]}))`,o.profile],{encoding:'utf8'}));
  const entitlement=entitlementsFor(profile,o);
  fs.mkdirSync(destination,{mode:0o700});
  const app=path.join(destination,'Payload','Runner.app');
  run(process.execPath,[path.join(here,'macho-embed.mjs'),source,app,o.addon,o.bundle]);
  if(focusEdition){
    fs.cpSync(path.join(here,'TurboIOArt'),path.join(app,'TurboIOArt'),{recursive:true,errorOnExist:true,force:false});
  }
  for(const [key,value] of Object.entries({NSCameraUsageDescription:'用户主动开启眼镜遥控拍照时取景。',NSPhotoLibraryAddUsageDescription:'用户拍摄后保存照片。'})){
    const plist=path.join(app,'Info.plist');run('plutil',['-replace',key,'-string',value,plist]);
  }
  copyTranslationResources(translationResources,app);
  if(translationResources){
    const plist=path.join(app,'Info.plist');
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSMicrophoneUsageDescription)run('plutil',['-insert','NSMicrophoneUsageDescription','-string','在用户主动开启英语离线字幕时使用所选麦克风；停止后结束收音。',plist]);
  }
  {
    // Exact inspected 1.0.7 data records only; no instruction/header edits or OTA grant.
    const image=path.join(app,'Frameworks/App.framework/App');
    fs.writeFileSync(image,patchOTARoute(fs.readFileSync(image)).output);
    const plist=path.join(app,'Info.plist');
    const music=true;
    run('plutil',['-insert','TIOExperimentalOTAQueryRouting','-string','ios107-tmg2-loopback-flash-gated',plist]);
    run('plutil',['-insert','TIOPackagingRevision','-string','APP107-OTA-PUBLIC-SOURCE-01',plist]);
    run('plutil',['-insert','TIOExperimentalOTABuild','-string','TMG2',plist]);
    if(firmware)fs.writeFileSync(path.join(app,focusEdition?'TurboWeReadCandidate.zip':music?'TurboMusicCandidate.zip':'TurboNavigationCandidate.zip'),firmware,{flag:'wx'});
    if(music){
      fs.copyFileSync(path.join(here,'../music/Beans-MIT-LICENSE.txt'),path.join(app,'TurboMusic-Beans-MIT-LICENSE.txt'));
      const musicInfo=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
      const modes=musicInfo.UIBackgroundModes||[];
      if(!modes.includes('audio'))run('plutil',musicInfo.UIBackgroundModes?['-insert','UIBackgroundModes.0','-string','audio',plist]:['-insert','UIBackgroundModes','-json','["audio"]',plist]);
    }
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSAppTransportSecurity)run('plutil',['-insert','NSAppTransportSecurity','-dictionary',plist]);
    if(info.NSAppTransportSecurity?.NSAllowsLocalNetworking===undefined)run('plutil',['-insert','NSAppTransportSecurity.NSAllowsLocalNetworking','-bool','YES',plist]);
    fs.cpSync(path.join(here,'tests/maps'),path.join(app,'TurboHUDMaps'),{recursive:true,errorOnExist:true,force:false});
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
  verifyRoute(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')));
  const ipa=path.join(destination,'TurboIO-local-only.ipa');
  run('/usr/bin/ditto',['-c','-k','--norsrc','--noextattr','--keepParent',path.join(destination,'Payload'),ipa]);fs.chmodSync(ipa,0o600);
  run('/usr/bin/unzip',['-tq',ipa]);
  const names=run('/usr/bin/unzip',['-Z1',ipa],{encoding:'utf8'}).split('\n');if(names.some(n=>n.split('/').some(x=>x==='__MACOSX'||x.startsWith('._'))))throw Error('unexpected_archive_metadata');
  const report={status:'SIGNED_NOT_DEVICE_ACCEPTED',host:'1.0.7 (230)',signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,experimentalOTA:true,flashAuthorized:false,firmwareResourceOnly:false,postSigningRouteVerified:true,ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']};
  fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){try{main();}catch(e){const known=/^[a-z_]+$/.test(e.message);console.error(known?e.message:'Local packaging failed. Check compatible source, profile and signing identity. No subprocess output or credentials are printed.');process.exitCode=1;}}
