import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync,mkdirSync,mkdtempSync,copyFileSync,appendFileSync,rmSync} from 'node:fs';
import {audit} from './check-source.mjs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const catalog=resolve(root,'apps/RayNeoCompanion/Resources/Assets.xcassets');
const specs=resolve(root,'apps/RayNeoCompanion');
// Application targets only; scheme and package entries share the two-space indent.
function applicationTargets(name){
 const spec=readFileSync(resolve(specs,name),'utf8');
 const body=spec.slice(spec.indexOf('\ntargets:\n')).split('\nschemes:\n')[0];
 return body.split(/\n(?=  \w+:\n)/).filter(block=>/\n    type: application\n/.test(block))
  .map(block=>({name:block.match(/ {2}(\w+):/)[1],block}));
}
function png(data,size){
 assert.equal(data.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
 assert.equal(data.subarray(12,16).toString(),'IHDR');
 assert.equal(data.readUInt32BE(16),size);assert.equal(data.readUInt32BE(20),size);
 assert.equal(data[24],8,'eight bit channel depth');
 assert.equal(data[25],2,'opaque RGB, no alpha channel');
}
test('master is a square opaque 1024-pixel PNG',()=>{
 png(readFileSync(resolve(root,'design/branding/norman-io-master.png')),1024);
});
test('every required iPhone, iPad and marketing slot has the correct pixel dimensions',()=>{
 const images=JSON.parse(readFileSync(catalog+'/AppIcon.appiconset/Contents.json')).images;
 const expected=['iphone:20:2','iphone:20:3','iphone:29:2','iphone:29:3','iphone:40:2','iphone:40:3','iphone:60:2','iphone:60:3',
 'ipad:20:1','ipad:20:2','ipad:29:1','ipad:29:2','ipad:40:1','ipad:40:2','ipad:76:1','ipad:76:2','ipad:83.5:2','ios-marketing:1024:1'];
 assert.deepEqual(images.map(i=>`${i.idiom}:${Number(i.size.split('x')[0])}:${Number(i.scale.slice(0,-1))}`).sort(),expected.sort());
 assert.equal(new Set(images.map(i=>i.filename)).size,images.length);
 for(const entry of images){const [w,h]=entry.size.split('x').map(Number);assert.equal(w,h);png(readFileSync(catalog+'/AppIcon.appiconset/'+entry.filename),w*Number(entry.scale.slice(0,-1)));}
});
test('reusable app mark supplies matching 1x, 2x and 3x assets',()=>{
 const images=JSON.parse(readFileSync(catalog+'/NormanIOMark.imageset/Contents.json')).images;
 assert.deepEqual(images.map(i=>i.scale).sort(),['1x','2x','3x']);
 for(const entry of images)png(readFileSync(catalog+'/NormanIOMark.imageset/'+entry.filename),128*Number(entry.scale.slice(0,-1)));
});
test('every application target compiles the shared asset catalog and names the app icon',()=>{
 for(const spec of ['project-source.yml','project-device.yml']){
  const targets=applicationTargets(spec);
  assert.ok(targets.length,spec+' declares application targets');
  for(const {name,block} of targets){
   assert.match(block,/\n {6}- Resources\n/,spec+' '+name+' compiles Resources');
   assert.match(block,/\n {8}ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon\n/,spec+' '+name+' names the app icon set');
  }
 }
});
test('the glasses screen shows the app mark and every named image exists',()=>{
 const view=readFileSync(resolve(root,'apps/RayNeoCompanion/Sources/DeviceView.swift'),'utf8');
 const named=[...view.matchAll(/Image\("([^"]+)"\)/g)].map(match=>match[1]);
 assert.ok(named.includes('NormanIOMark'),'device screen shows the Norman IO mark');
 for(const name of named)assert.ok(existsSync(catalog+'/'+name+'.imageset/Contents.json'),name+' is in the asset catalog');
});
test('ICO entries have valid independent PNGs and exact contiguous offsets',()=>{
 const data=readFileSync(resolve(root,'design/branding/norman-io.ico'));
 assert.equal(data.readUInt16LE(0),0);assert.equal(data.readUInt16LE(2),1);
 const sizes=[16,24,32,48,64,128,256];assert.equal(data.readUInt16LE(4),sizes.length);
 let end=6+sizes.length*16;
 sizes.forEach((size,index)=>{const entry=6+index*16,bytes=data.readUInt32LE(entry+8),offset=data.readUInt32LE(entry+12);
  assert.equal(data[entry]||256,size);assert.equal(data[entry+1]||256,size);assert.equal(offset,end);
  png(data.subarray(offset,offset+bytes),size);end+=bytes;
 });assert.equal(end,data.length);
});
test('source audit accepts the reviewed brand asset but detects changed bytes',()=>{
 mkdirSync(resolve(root,'artifacts/branding'),{recursive:true});
 const temporary=mkdtempSync(resolve(root,'artifacts/branding/source-audit-'));
 const relative='design/branding/norman-io-master.png',file=resolve(temporary,relative);
 try{
  mkdirSync(dirname(file),{recursive:true});copyFileSync(resolve(root,relative),file);
  assert.deepEqual(audit(temporary).findings,[]);
  appendFileSync(file,'changed');
  assert.deepEqual(audit(temporary).findings,[{file:relative,rule:'branding-needs-privacy-review'}]);
 }finally{rmSync(temporary,{recursive:true,force:true});}
});
