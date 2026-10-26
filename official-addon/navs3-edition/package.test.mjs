import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {patch,inputPins} from './patch-ios106-route.mjs';
import {validateOptions,validateResearchPair,entitlementsFor} from './package.mjs';
import {inspectedHost} from './host-compatibility.mjs';
import path from 'node:path';
import {inspectMachO,addEmbeddedLoad} from './macho-embed.mjs';

test('only matching 1.0.6/218 UUID accepted as the new host',()=>{
 const i={CFBundleIdentifier:'com.rayneo.venus.pub',CFBundleExecutable:'Runner',CFBundleShortVersionString:'1.0.6',CFBundleVersion:'218'};
 assert.ok(inspectedHost(i,'98a03b57e8163ba19778e55fabe8d762'));
 assert.equal(inspectedHost({...i,CFBundleVersion:'219'},'98a03b57e8163ba19778e55fabe8d762'),null);
 assert.equal(inspectedHost(i,'0'.repeat(32)),null);
});
test('options do not accept old OTA candidates or implicit firmware',()=>{
 const o={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-navs3-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub','experimental-ota':'TMG2',firmware:'/example/navs3.zip'};
 validateOptions(o);
 assert.throws(()=>validateOptions({...o,'experimental-ota':'TFP1'}));
 assert.throws(()=>validateOptions({...o,firmware:undefined}));
 assert.throws(()=>validateOptions({...o,bundle:'example.other'}));
});
test('profile checks and entitlements preserve only granted rights',()=>{
 const o={identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub'};
 const p={certs:[o.identity],devices:[o.device],expires:'2099-01-01T00:00:00Z',entitlements:{'application-identifier':'EXAMPLE.*','keychain-access-groups':['EXAMPLE.*']}};
 const e=entitlementsFor(p,o);
 assert.equal(e['application-identifier'],'EXAMPLE.com.rayneo.venus.pub');
 assert.equal(e['aps-environment'],undefined);
 assert.throws(()=>entitlementsFor({...p,devices:[]},o));
 assert.throws(()=>entitlementsFor({...p,expires:'2000-01-01T00:00:00Z'},o));
});
test('unknown host bytes and unmatched firmwares fail closed',()=>{
 assert.equal(inputPins.length,2);
 assert.throws(()=>patch(Buffer.from('not-a-host')));
 assert.throws(()=>validateResearchPair('_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap','TMG2',Buffer.alloc(32)));
 assert.throws(()=>validateResearchPair('','TMG2',Buffer.alloc(32)));
});
test('exact TMG2 and real NAVS3 symbols are accepted; altered archive is rejected',()=>{
 const firmware=process.env.NAVS3_TEST_FIRMWARE;
 if(!firmware)return;
 const symbols='_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap', bytes=fs.readFileSync(firmware);
 validateResearchPair(symbols,'TMG2',bytes);
 assert.throws(()=>validateResearchPair(symbols,'TMIG1',bytes));
 assert.throws(()=>validateResearchPair('_CEPhoneSendCards _TFFocusConsume','TMG2',bytes));
 const bad=Buffer.from(bytes);bad[bad.length-1]^=1;
 assert.throws(()=>validateResearchPair(symbols,'TMG2',bad));
});
test('optional unsigned stock Release input is exactly pinned and changed only at two routes',()=>{
 const host=process.env.NAVS3_TEST_UNSIGNED_HOST_IMAGE;if(!host)return;
 const input=fs.readFileSync(host),result=patch(input);
 assert.equal(result.report.inputSHA,'57d064491c46a21420fd73c969ebfb390707556861526e62db58633514caf884');
 assert.equal(result.output.length,input.length);
 assert.equal(result.report.changes.length,2);
 assert.equal(result.report.instructionsChanged,false);
 const bad=Buffer.from(input);bad[4096]^=1;assert.throws(()=>patch(bad));
});
test('optional unsigned original bundle has 95 unencrypted images and accepts an addon loader',()=>{
 const app=process.env.NAVS3_TEST_UNSIGNED_APP;if(!app)return;
 let images=0;
 for(const relative of fs.readdirSync(app,{recursive:true})){
  const file=path.join(app,relative);if(!fs.statSync(file).isFile())continue;
  const b=fs.readFileSync(file);if(b.length<4||b.readUInt32LE(0)!==0xfeedfacf)continue;
  const h=inspectMachO(b);assert.equal(h.encrypted,false);
  assert.ok(h.dependencies.every(n=>!n.includes('TurboIOPrivateAddon')));images++;
 }
 assert.equal(images,95);
 const runner=fs.readFileSync(path.join(app,'Runner')),before=inspectMachO(runner);
 const after=inspectMachO(addEmbeddedLoad(runner));
 assert.equal(before.uuid,'98a03b57e8163ba19778e55fabe8d762');
 assert.equal(after.uuid,before.uuid);assert.equal(after.count,before.count+1);
 assert.ok(after.dependencies.includes('@executable_path/Frameworks/TurboIOPrivateAddon.dylib'));
 assert.equal(createHash('sha256').update(runner).digest('hex'),'d59823568be232b1742f7414a6ebae4718f053e1a251577808041b032306bd44');
});
test('optional exact real-input acceptance without signing, installation or device IO',()=>{
 const host=process.env.NAVS3_TEST_HOST_IMAGE, firmware=process.env.NAVS3_TEST_FIRMWARE;
 if(!host||!firmware)return;
 const input=fs.readFileSync(host), result=patch(input);
 assert.equal(createHash('sha256').update(result.output).digest('hex'),'532bdfc1971668df113434de54f69cede8bab3f61c7d82d028d62c54f5ca5940');
 assert.equal(result.report.changes.length,2);
 assert.equal(result.report.objectHeadersChanged,false);
 validateResearchPair('_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap','TMG2',fs.readFileSync(firmware));
 const wrong=Buffer.from(input);wrong[0]^=1;assert.throws(()=>patch(wrong));
 const bad=fs.readFileSync(firmware);bad[bad.length-1]^=1;assert.throws(()=>validateResearchPair('_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap','TMG2',bad));
});
