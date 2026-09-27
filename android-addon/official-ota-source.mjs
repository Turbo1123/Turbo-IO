// Android 1.0.5 only. Offline serialized-string source routing, not an OTA sender.
// Dart 3.11.5 StringSerializationCluster encodes length<<1, then raw one-byte
// characters. Preserve length AND hash: the canonical table layout is serialized.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {makeRoute,stringHash} from '../official-addon/research/patch-ios105-ota-source.mjs';
export const sourceSHA='78214ba0e1057871315da1cee17d860415c8b913521e59afc2748e45ead64c6c';
export const slots=[
 {offset:0x86e1f5,pp:'0x2c8b8',text:'/xrlauncherapi/v1/signApi/gray/upgrade'},
 {offset:0xd95b8,pp:'0x2c9c0',text:'/xrlauncherhwapi/v1/signApi/gray/upgrade'}
];
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const check=(v,m)=>{if(!v)throw Error(m);};
export function patchAndroidSource(input){
 check(sha(input)===sourceSHA,'Unsupported Android libapp.so; no changes');
 const output=Buffer.from(input),changes=[];
 for(const {offset,pp,text} of slots){
  check(input.indexOf(text)===offset&&input.indexOf(text,offset+1)===-1,'Nonunique string');
  check(input[offset-1]===0x80+(text.length<<1),'Unexpected serialized string length/CID');
  const replacement=makeRoute(text);
  check(replacement.length===text.length&&stringHash(replacement)===stringHash(text),'Canonical hash/size changed');
  output.write(replacement,offset,'ascii');
  changes.push({offset,pp,bytes:text.length,replacement,hash:stringHash(text)});
 }
 for(let i=0;i<input.length;i++)if(input[i]!==output[i])check(changes.some(c=>i>=c.offset&&i<c.offset+c.bytes),'Outside string change');
 return {output,report:{inputSHA:sourceSHA,outputSHA:sha(output),changes,bytes:output.length,
  deviceIO:false,installed:false,flashed:false,runtimeValidated:false,
  scope:'Source routing only; requires preparation-only transport guard. No firmware or executable instruction modification.'}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const [src,dst]=process.argv.slice(2);check(src&&dst,'Usage: original-libapp.so new-output-directory');
 check(!fs.existsSync(dst),'Output already exists');
 const {output,report}=patchAndroidSource(fs.readFileSync(src));fs.mkdirSync(dst,{recursive:true});
 fs.writeFileSync(dst+'/libapp.so',output,{flag:'wx'});fs.writeFileSync(dst+'/report.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify(report,null,2));
}
