// Generate a relocatable-link input, NOT a firmware patch or executable image.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {inflateSync} from 'node:zlib';
import assert from 'node:assert/strict';
const [firmware,pngPath,out]=process.argv.slice(2);
assert(firmware&&pngPath&&out&&!fs.existsSync(out),'Need firmware, PNG, new output');
const ap=fs.readFileSync(path.join(firmware,'nuttx_ap.bin'));
const hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(hash(ap),'53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988');
const png=fs.readFileSync(pngPath);
assert.equal(hash(png),'738169867ec0ca778cd6ce14e803aaa508bf16f8e169d1081db3e622d571db24','Exact approved compressed photo only');
assert.equal(png.length,4022);
assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
let off=8,compressed=[],ended=false;
function crc(b) { let c=0xffffffff;for(const x of b){c^=x;for(let n=0;n<8;n++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0; }
while(off+12<=png.length){
  const n=png.readUInt32BE(off),end=off+12+n;assert(end<=png.length);
  assert.equal(crc(png.subarray(off+4,end-4)),png.readUInt32BE(end-4));
  const type=png.toString('ascii',off+4,off+8);
  if(type==='IDAT')compressed.push(png.subarray(off+8,end-4));
  off=end;if(type==='IEND'){assert.equal(n,0);ended=true;break;}
}
assert(ended&&off===png.length);
assert.equal(png.readUInt32BE(16),88);assert.equal(png.readUInt32BE(20),98);
assert.equal(png[24],8);assert.equal(png[25],6);assert.equal(png[28],0);
assert.equal(inflateSync(Buffer.concat(compressed),{maxOutputLength:40000}).length,98*(88*4+1));
const symbols=JSON.parse(fs.readFileSync(path.join(firmware,'symbols.json')));
const source=fs.readFileSync(new URL('./menu8-native-lvgl.c',import.meta.url),'utf8');
const required=[...new Set(source.match(/tio_lv_\w+/g))].sort();
const bindings=required.map(alias=>{
  const name=alias.slice(4),found=symbols.entries.filter(e=>e.name===name);
  assert.equal(found.length,1,`Unique ${name}`);const e=found[0];
  assert.equal(ap.readUInt32LE(e.tableOffset+4),e.address,'Symbol table address matches AP');
  const pointer=ap.readUInt32LE(e.tableOffset);let at;
  for(const [lo,hi,base]of symbols.segments)if(pointer>=lo&&pointer<hi)at=base+pointer-lo;
  if(at===undefined)at=pointer-parseInt(symbols.flash,16);
  assert(at>=0&&at+name.length<ap.length);
  assert.equal(ap.subarray(at,at+name.length+1).toString(),name+'\0');
  assert(e.address&1,'Thumb address');
  return {alias,name,address:'0x'+e.address.toString(16)};
});
fs.mkdirSync(out,{recursive:true,mode:0o700});
const write=(n,b)=>fs.writeFileSync(path.join(out,n),b,{flag:'wx',mode:0o600});
write('native-symbols.ld',bindings.map(b=>`${b.alias} = ${b.address};`).join('\n')+'\n');
let c='#include "menu8-renderer.h"\nstatic const uint8_t pixels[4022]={\n';
for(let n=0;n<png.length;n+=16)c+=' '+[...png.subarray(n,n+16)].map(x=>'0x'+x.toString(16).padStart(2,'0')).join(',')+',\n';
c+='};\nconst M8Image m8_photo={.magic=0x19,.cf=1,.width=88,.height=98,.bytes=4022,.data=pixels};\n';
write('photo-payload.c',c);
write('report.json',JSON.stringify({kind:'relocatable-link-input-only',firmwareModified:false,readyToFlash:false,apSHA256:hash(ap),photoSHA256:hash(png),photoBytes:png.length,bindings},null,2));
console.log(JSON.stringify({out,bindings:bindings.length,photoBytes:png.length,firmwareModified:false}));
