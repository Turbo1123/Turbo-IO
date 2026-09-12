import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const master=resolve(root,'design/branding/norman-io-master.png');
const catalog=resolve(root,'apps/RayNeoCompanion/Resources/Assets.xcassets');
const info={author:'xcode',version:1};
function json(file,value){mkdirSync(dirname(file),{recursive:true});writeFileSync(file,JSON.stringify(value,null,2)+'\n');}
function resize(size,file){
 mkdirSync(dirname(file),{recursive:true});
 const result=spawnSync('/usr/bin/sips',['-z',String(size),String(size),master,'--out',file],{encoding:'utf8'});
 if(result.status!==0)throw Error('PNG export failed: '+size);
}
json(catalog+'/Contents.json',{info});
const slots=[['iphone',20,[2,3]],['iphone',29,[2,3]],['iphone',40,[2,3]],['iphone',60,[2,3]],
 ['ipad',20,[1,2]],['ipad',29,[1,2]],['ipad',40,[1,2]],['ipad',76,[1,2]],['ipad',83.5,[2]],['ios-marketing',1024,[1]]];
const images=[];
for(const [idiom,points,scales] of slots)for(const scale of scales){
 const filename=`icon-${idiom}-${points}@${scale}x.png`;
 resize(points*scale,catalog+'/AppIcon.appiconset/'+filename);
 images.push({idiom,size:`${points}x${points}`,scale:`${scale}x`,filename});
}
json(catalog+'/AppIcon.appiconset/Contents.json',{images,info});
const marks=[];
for(const scale of [1,2,3]){
 const filename=`norman-io-mark@${scale}x.png`;
 resize(128*scale,catalog+'/NormanIOMark.imageset/'+filename);
 marks.push({idiom:'universal',scale:`${scale}x`,filename});
}
json(catalog+'/NormanIOMark.imageset/Contents.json',{images:marks,info});
// ICO container with independently resized PNG payloads. No visual redesign.
const sizes=[16,24,32,48,64,128,256];
const payloads=sizes.map(size=>{const file=resolve(root,`artifacts/branding/ico-${size}.png`);resize(size,file);return readFileSync(file);});
const header=Buffer.alloc(6+16*sizes.length);header.writeUInt16LE(1,2);header.writeUInt16LE(sizes.length,4);
let offset=header.length;
payloads.forEach((data,index)=>{const entry=6+index*16,size=sizes[index];header[entry]=size===256?0:size;header[entry+1]=header[entry];header.writeUInt16LE(1,entry+4);header.writeUInt16LE(32,entry+6);header.writeUInt32LE(data.length,entry+8);header.writeUInt32LE(offset,entry+12);offset+=data.length;});
writeFileSync(resolve(root,'design/branding/norman-io.ico'),Buffer.concat([header,...payloads]));
console.log(`Exported ${images.length} iOS icon slots, ${marks.length} app marks, and ${sizes.length} ICO sizes.`);
