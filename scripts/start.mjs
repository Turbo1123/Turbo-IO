#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const mode=process.argv[2];
if(!['--local','--device'].includes(mode) || process.argv.length!==3){
  console.error('Usage: node scripts/start.mjs --local | --device'); process.exit(2);
}
for(const [name,args] of [['xcodebuild',['-version']],['xcodegen',['--version']]]){
  const check=spawnSync(name,args,{cwd:root,stdio:'ignore'});
  if(check.error || check.status!==0){console.error(`Missing ${name}: install/configure Xcode and XcodeGen first.`);process.exit(2);}
}
let spec='apps/RayNeoCompanion/project-source.yml';
if(mode==='--device'){
  spec=existsSync(resolve(root,'apps/RayNeoCompanion/project-device.yml'))?'apps/RayNeoCompanion/project-device.yml':'apps/RayNeoCompanion/project.yml';
  const required=['RayneoNet','CocoaAsyncSocket','OpenSSL','RayneoLog','SwiftProtobuf','CocoaLumberjack','SSZipArchive'].map(n=>`core-probe/Frameworks/${n}.framework`);
  required.push('core-probe/RecoveredInterface/RayneoNet.swift','core-probe/Vendor/opus-ios/libopus.a','core-probe/Vendor/opus-1.5.2/include/opus.h','core-probe/Vendor/opus-1.5.2/COPYING','core-probe/Vendor/py-webrtcvad-2.0.10/cbits/webrtc/common_audio','core-probe/Vendor/py-webrtcvad-2.0.10/LICENSE');
  const missing=required.filter(p=>!existsSync(resolve(root,p)));
  if(missing.length){console.error('Incomplete device dependency checkout. See docs/CONFIGURATION.md. Missing:\n'+missing.join('\n'));process.exit(2);}
  const sdk=spawnSync('xcrun',['--sdk','iphoneos','--show-sdk-path'],{encoding:'utf8'});
  if(sdk.status!==0)process.exit(2);
  const module='core-probe/RecoveredInterface/build/RayneoNet.swiftmodule';
  mkdirSync(resolve(root,module),{recursive:true});
  // Declaration module only. Never link placeholder class implementations.
  const rebuilt=spawnSync('xcrun',['swiftc','-emit-module','-parse-as-library','-module-name','RayneoNet','-target','arm64-apple-ios16.0','-sdk',sdk.stdout.trim(),'core-probe/RecoveredInterface/RayneoNet.swift','-emit-module-path',module+'/arm64-apple-ios.swiftmodule'],{cwd:root,stdio:'inherit'});
  if(rebuilt.status!==0)process.exit(rebuilt.status||1);
}
const generated=spawnSync('xcodegen',['generate','--spec',spec],{cwd:root,stdio:'inherit'});
if(generated.status!==0)process.exit(generated.status||1);
console.log(mode==='--local'?'Select RayNeoCompanion and a simulator; press Run. No glasses transport.':'Select RayNeoCompanionDevice, your signing Team and your own iPhone. No automatic installation.');
const opened=spawnSync('open',['apps/RayNeoCompanion/RayNeoCompanion.xcodeproj'],{cwd:root,stdio:'inherit'});
process.exitCode=opened.status||0;
