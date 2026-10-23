// Android 1.0.6 / 1.0.7 pinned builds only. Offline serialized-string source routing, not an OTA sender.
// Dart StringSerializationCluster encodes length<<1, then raw one-byte
// characters. Preserve length AND hash: the canonical table layout is serialized.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {makeRoute,stringHash} from '../official-addon/research/patch-ios105-ota-source.mjs';
// Offsets located by unique match; each must still be the only occurrence at patch time.
export const SOURCES=Object.freeze({
 // 1.0.6 (216)
 'e9ab4326681c0b53892550b04e03284b2bba2e30adcf22033b8e23e5b3bc66af':[
  {offset:0x885c9a,text:'/xrlauncherapi/v1/signApi/gray/upgrade'},
  {offset:0xe1ffc,text:'/xrlauncherhwapi/v1/signApi/gray/upgrade'}],
 // 1.0.7 (230): same snapshot string format (shared snapshot version hash with 1.0.6).
 'a35159a82c0916f62ed6c4da271a40217300cc6678b29c54f2591d9fb592a45c':[
  {offset:0x88512e,text:'/xrlauncherapi/v1/signApi/gray/upgrade'},
  {offset:0xe1e48,text:'/xrlauncherhwapi/v1/signApi/gray/upgrade'}],
});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const check=(v,m)=>{if(!v)throw Error(m);};
export function patchAndroidSource(input){
 const inputSHA=sha(input),pinned=SOURCES[inputSHA];
 check(pinned,'Unsupported Android libapp.so; no changes');
 const output=Buffer.from(input),changes=[];
 for(const {offset,pp,text} of pinned){
  check(input.indexOf(text)===offset&&input.indexOf(text,offset+1)===-1,'Nonunique string');
  check(input[offset-1]===0x80+(text.length<<1),'Unexpected serialized string length/CID');
  const replacement=makeRoute(text);
  check(replacement.length===text.length&&stringHash(replacement)===stringHash(text),'Canonical hash/size changed');
  output.write(replacement,offset,'ascii');
  changes.push({offset,pp,bytes:text.length,replacement,hash:stringHash(text)});
 }
 for(let i=0;i<input.length;i++)if(input[i]!==output[i])check(changes.some(c=>i>=c.offset&&i<c.offset+c.bytes),'Outside string change');
 return {output,report:{inputSHA,outputSHA:sha(output),changes,bytes:output.length,
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
