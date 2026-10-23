import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {patchAndroidSource,SOURCES} from '../official-ota-source.mjs';
// Every decoded supported host present must patch at exactly its pinned offsets.
const PINNED={'host-106':'e9ab4326681c0b53892550b04e03284b2bba2e30adcf22033b8e23e5b3bc66af','host-107':'a35159a82c0916f62ed6c4da271a40217300cc6678b29c54f2591d9fb592a45c'};
const hosts=Object.keys(PINNED).map(d=>[d,new URL('../build/'+d+'/lib/arm64-v8a/libapp.so',import.meta.url)]).filter(([,u])=>fs.existsSync(u));
assert.ok(hosts.length>0,'decode at least one supported host into android-addon/build/');
for(const [dir,url] of hosts){
  const original=fs.readFileSync(url),sha=crypto.createHash('sha256').update(original).digest('hex');
  assert.equal(sha,PINNED[dir],dir+' libapp.so is not the pinned build');
  const slots=SOURCES[sha];assert.equal(slots.length,2);
  const {output,report}=patchAndroidSource(original);
  assert.equal(output.length,original.length);assert.equal(report.changes.length,2);
  assert.deepEqual(report.changes.map(c=>c.offset),slots.map(s=>s.offset));
  for(const s of slots)assert.equal(output[s.offset-1],original[s.offset-1]);
  assert.deepEqual(patchAndroidSource(original).output,output);
  assert.throws(()=>patchAndroidSource(output));
  const corrupt=Buffer.from(original);corrupt[100]^=1;assert.throws(()=>patchAndroidSource(corrupt));
  assert.throws(()=>patchAndroidSource(original.subarray(1)));
}
// TVP2-only: the 1.0.5 (201) library is no longer a supported input.
assert.equal(SOURCES['78214ba0e1057871315da1cee17d860415c8b913521e59afc2748e45ead64c6c'],undefined);
console.log('Android source routing ('+hosts.map(h=>h[0]).join(', ')+'): fixed input, length/hash, byte allowlist, wrong-input and repeated-patch tests passed');
