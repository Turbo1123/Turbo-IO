// Exact iOS 1.0.6/218 string routing for a private, guarded download source.
// Preserves length, object header and cached Dart hash. No device operations.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {makeRoute,stringHash,originals} from './route-hash.mjs';
// Two exact stock encodings only: original App Store signature retained, or the
// separately audited unsigned original Release. No generic hash bypass.
export const inputPins=Object.freeze([
 '50d91ba920f0cc9fa93255f5d0bb647fbc50a4b2a0e34b37c2696fbbdeda0845',
 '57d064491c46a21420fd73c969ebfb390707556861526e62db58633514caf884',
]);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const assert=(ok,message)=>{if(!ok)throw Error(message);};
export function patch(input){
const b=input,inputSHA=sha(b);assert(inputPins.includes(inputSHA),'Wrong host image');
const output=Buffer.from(b),changes=[];
for(const original of originals){
 const offset=b.indexOf(original);assert(offset>=16&&b.indexOf(original,offset+1)===-1,'Not a unique string');
 assert(b.readBigUInt64LE(offset-8)===BigInt(original.length*2),'Dart length mismatch');
 assert(b.readUInt32LE(offset-12)===stringHash(original),'Cached hash mismatch');
 const replacement=makeRoute(original);output.write(replacement,offset,'ascii');
 assert(output.subarray(offset-16,offset).equals(b.subarray(offset-16,offset)),'Object header changed');
 changes.push({offset,bytes:original.length,original,replacement,stringHash:stringHash(original)});
}
for(let i=0;i<b.length;i++)if(b[i]!==output[i])assert(changes.some(c=>i>=c.offset&&i<c.offset+c.bytes),'Unexpected edit');
return {output,report:{host:'1.0.6',build:218,inputSHA,outputSHA:sha(output),changes,instructionsChanged:false,objectHeadersChanged:false,deviceIO:false}};
}
