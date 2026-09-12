#!/usr/bin/env node
// Local-only source-release packager. Does not download, decrypt or upload apps.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync as exec } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
export function validateOptions(o) {
  for(const k of ['app','addon','profile','out'])if(typeof o[k]!=='string'||!path.isAbsolute(o[k]))throw Error('absolute_paths_required');
  if(!o.app.endsWith('.app')||o.out.endsWith('.app'))throw Error('use_app_input_and_new_output_directory');
  if(!/^[a-f0-9]{40}$/i.test(o.identity||'')||!/^[a-z0-9-]{8,80}$/i.test(o.device||''))throw Error('explicit_identity_and_device_required');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(o.bundle||''))throw Error('invalid_bundle');
  if(o.product&&!/^iPhone\d+,\d+$/.test(o.product))throw Error('invalid_explicit_product');
  if(fs.existsSync(o.out))throw Error('output_must_not_exist');
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
  if(process.argv.includes('--help')){console.log('node official-addon/package.mjs --app /absolute/Runner.app --addon /absolute/TurboIOPrivateAddon.dylib --profile /absolute/profile.mobileprovision --identity CERTIFICATE_SHA1 --device YOUR_DEVICE_ID --out /absolute/new-private-output [--bundle com.rayneo.venus.pub] [--product iPhone18,4]');return;}
  const o={bundle:'com.rayneo.venus.pub'};const args=process.argv.slice(2);
  if(args.length%2)throw Error('expected_named_arguments');
  const seen=new Set();for(let i=0;i<args.length;i+=2){const k=args[i].slice(2);if(!args[i].startsWith('--')||!['app','addon','profile','identity','device','out','bundle','product'].includes(k)||seen.has(k))throw Error('unknown_or_duplicate_argument');seen.add(k);o[k]=args[i+1];}
  validateOptions(o);
  const source=fs.realpathSync(o.app),destination=path.resolve(o.out);
  if(destination===source||destination.startsWith(source+path.sep))throw Error('output_must_be_separate');
  if(fs.existsSync(path.join(source,'TurboIOPrivateBootstrap.json'))||fs.existsSync(path.join(source,'TurboIOKnowledgeConnection.json')))throw Error('source_contains_private_bootstrap');
  const profile=JSON.parse(run('python3',['-c',`import sys,plistlib,json,hashlib,subprocess
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
print(json.dumps({'entitlements':p['Entitlements'],'expires':p['ExpirationDate'].isoformat()+'Z','devices':p.get('ProvisionedDevices',[]),'certs':[hashlib.sha1(x).hexdigest().upper() for x in p['DeveloperCertificates']]}))`,o.profile],{encoding:'utf8'}));
  const entitlement=entitlementsFor(profile,o);
  fs.mkdirSync(destination,{mode:0o700});
  const app=path.join(destination,'Payload','Runner.app');
  run(process.execPath,[path.join(here,'macho-embed.mjs'),source,app,o.addon,o.bundle]);
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
  const report={status:'SIGNED_NOT_DEVICE_ACCEPTED',signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']};
  fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){try{main();}catch(e){const known=/^[a-z_]+$/.test(e.message);console.error(known?e.message:'Local packaging failed. Check compatible source, profile and signing identity. No subprocess output or credentials are printed.');process.exitCode=1;}}
