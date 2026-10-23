import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {PROFILES,profileFor,classFile,verifyHost} from '../host-profiles.mjs';
const SHA_106='4c1c57ae811cb959478efb5ec510000f7f51ddcb427afff369b1582c66b60206',SHA_107='30239f65d910cf7008cfdf6cfacd5c068c5877068b4a637027786377a9ce4f91';
assert.equal(profileFor(SHA_106).code,216);
assert.equal(profileFor(SHA_107).code,230);
// TVP2-only: the 1.0.4 / 1.0.5 hosts are no longer packaged.
assert.throws(()=>profileFor('770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3'));
assert.throws(()=>profileFor('ef2e7dd346ca478e13d0f3f1bf31fa61412e44fb9b4ca9cf0d3e864ac608584b'));
assert.throws(()=>profileFor('unknown'));
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-host-test-'));
try {
  fs.mkdirSync(path.join(dir,'smali/E3'),{recursive:true});
  fs.writeFileSync(path.join(dir,'smali/E3/U.smali'),'.class public LE3/U;\n');
  fs.writeFileSync(path.join(dir,'smali/E3/u.1.smali'),'.class public LE3/u;\n');
  assert.equal(path.basename(classFile(dir,'LE3/u;')),'u.1.smali');
  assert.equal(path.basename(classFile(dir,'LE3/U;')),'U.smali');
  assert.throws(()=>classFile(dir,'LE3/nonexistent;'));
  assert.throws(()=>classFile(dir,'../../secret'));
  assert.throws(()=>verifyHost(dir,profileFor(SHA_106)));
} finally { fs.rmSync(dir,{recursive:true}); }

// Minimal smali tree carrying exactly the lines verifyHost requires for one ABI.
function fakeHost(n){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-host-abi-'));
  const T='L'+n.transport+'/',S='L'+n.sdk+'/',C='L'+n.core+'/',M=T+n.message+';';
  const put=(d,lines)=>{const rel=d.slice(1,-1)+'.smali',f=path.join(root,'smali_classes2',rel);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,['.class public '+d,...lines].join('\n')+'\n');};
  const outer=n.listener.replace('$c;',';');
  put(n.listener,['.field public final synthetic a:'+outer,'.method public final onAsrResult(Ljava/lang/String;ZLjava/lang/String;)V','.method public final onNlpResult(Lcom/rayneo/airuntime/controller/NlpResult;)V','.method public final onResponseComplete()V']);
  if(!n.noStop)put(outer,['.method public final s(Ljava/lang/String;ZZ)V','    const-string v1, "stop_assistant"','.end method']);
  put('Lcom/rayneo/venus/MainActivity;',['.method public final onPostResume()V']);
  put('Lcom/rayneo/rayneo_venus_sdk_plugin/j;',['.method public final z(Ljava/lang/String;Ljava/util/Map;)V']);
  put(T+'u;',['.field public static volatile h:'+T+'u;','.method public static g()Ljava/util/List;','.method public final '+n.send+'('+M+'Lkotlin/jvm/functions/Function2;)V','.method public final '+n.file+'(Ljava/io/File;Ljava/lang/String;'+C+'q;Ljava/lang/String;)Ljava/lang/String;']);
  put(M,['.method public constructor <init>([BLjava/lang/String;Ljava/lang/String;'+S+'h;'+S+'Q;'+T+'b;ZZ'+C+'p;Lkotlin/jvm/functions/Function2;)V','.field public final b:Ljava/lang/String;','.field public final c:'+S+'h;','.field public final e:[B','.field public k:Lkotlin/jvm/functions/Function2;']);
  put(T+'C;',['.field public final a:Ljava/lang/String;','.method public final b()Z']);
  put('Lcom/amap/api/maps/MapsInitializer;',['.method public static setApiKey(Ljava/lang/String;)V']);
  put('Lcom/amap/api/location/AMapLocationClient;',['.method public static setApiKey(Ljava/lang/String;)V']);
  put('Lcom/amap/api/services/core/ServiceSettings;',['.method public static getInstance()Lcom/amap/api/services/core/ServiceSettings;','.method public setApiKey(Ljava/lang/String;)V']);
  put(S+'h;',['"AI_SUBTITLE"','"LAUNCHER"','"TELEPROMPTER"','"MARS_FOTA"']);
  put(T+'b;',['"NORMAL"']);
  put(C+'q;',['"SmallCore"']);
  put(n.queue,['.method public static o('+M+')V']);
  put(S+'A;',['.field public static final enum r:'+S+'A;','"MESSAGE_SEND_FAILED"']);
  return root;
}
const n107={transport:'Y3',sdk:'j4',core:'k4',listener:'Lq8/c$c;',queue:'LY3/V;',send:'t',file:'u',message:'S'};
const h107=fakeHost(n107);
try {
  const r=verifyHost(h107,profileFor(SHA_107));
  assert.equal(r.ota.message,'LY3/S;');
  assert.equal(r.ota.queueHeader,'.method public static o(LY3/S;)V');
  assert.equal(r.ota.queueClass,'LY3/V;');
  assert.equal(PROFILES[SHA_107].directory,'host-107');
  // A 1.0.7 tree must not pass as 1.0.6 (different packages and message class).
  assert.throws(()=>verifyHost(h107,profileFor(SHA_106)));
} finally { fs.rmSync(h107,{recursive:true}); }
const h106=fakeHost({transport:'X3',sdk:'i4',core:'j4',listener:'Lp8/c$c;',queue:'LX3/U;',send:'t',file:'u',message:'Q'});
try { assert.equal(verifyHost(h106,profileFor(SHA_106)).ota.message,'LX3/Q;'); } finally { fs.rmSync(h106,{recursive:true}); }
// Voice exit needs the official stop entry; a host without it is refused before any mutation.
const hNoStop=fakeHost({...n107,noStop:true});
try { assert.throws(()=>verifyHost(hNoStop,profileFor(SHA_107)),/stop/); } finally { fs.rmSync(hNoStop,{recursive:true}); }
const h107b=fakeHost(n107);
try { assert.equal(verifyHost(h107b,profileFor(SHA_107)).voiceStop,'Lq8/c;'); } finally { fs.rmSync(h107b,{recursive:true}); }
console.log('Host profile tests passed (19 assertions).');
