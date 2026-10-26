// Exact 1.0.7 input only. Two data strings, no instruction/header edits.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {makeRoute,stringHash,originals} from './route-hash.mjs';
export const originalSHA='fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e';
export const unsignedSHA='041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d';
export const offsets=[41206352,32115728];
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const check=(v,m)=>{if(!v)throw Error(m);};
// Signing may change the signature blob; verify the exact two records afterwards.
export function verifyRoute(input){
  for(let i=0;i<originals.length;i++){
    const offset=offsets[i],original=originals[i],replacement=makeRoute(original);
    check(input.length>=offset+original.length,'Truncated route image');
    check(input.readBigUInt64LE(offset-8)===BigInt(original.length*2),'Dart length mismatch');
    check(input.readUInt32LE(offset-12)===stringHash(original),'Cached hash mismatch');
    check(input.subarray(offset,offset+original.length).equals(Buffer.from(replacement)),'Route record mismatch');
  }
  return true;
}
export function patch(input){
  check([originalSHA,unsignedSHA].includes(sha(input)),'Wrong host image: requires pinned original or unsigned 1.0.7/230');
  const output=Buffer.from(input),changes=[];
  for(let i=0;i<originals.length;i++){
    const original=originals[i],offset=offsets[i];
    check(input.indexOf(original)===offset&&input.indexOf(original,offset+1)===-1,'Unexpected query record');
    check(input.readBigUInt64LE(offset-8)===BigInt(original.length*2),'Dart length mismatch');
    check(input.readUInt32LE(offset-12)===stringHash(original),'Cached hash mismatch');
    const replacement=makeRoute(original);output.write(replacement,offset,'ascii');
    check(output.subarray(offset-16,offset).equals(input.subarray(offset-16,offset)),'Header changed');
    changes.push({offset,bytes:original.length,original,replacement});
  }
  for(let i=0;i<input.length;i++)if(input[i]!==output[i])check(changes.some(c=>i>=c.offset&&i<c.offset+c.bytes),'Unexpected edit');
  return {output,report:{host:'1.0.7',build:230,inputSHA:sha(input),outputSHA:sha(output),changes,instructionsChanged:false,deviceIO:false,runtimeValidated:false}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const [source,out]=process.argv.slice(2);check(source&&out&&!fs.existsSync(out),'Requires input and fresh output directory');
  const {output,report}=patch(fs.readFileSync(source));fs.mkdirSync(out,{mode:0o700});
  fs.writeFileSync(path.join(out,'App'),output,{flag:'wx',mode:0o600});
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});
  console.log(JSON.stringify(report));
}
