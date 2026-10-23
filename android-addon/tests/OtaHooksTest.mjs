import assert from 'node:assert/strict';
import {queueHook,fileHook,EVENT_GUARD,OTA_106,OTA_107} from '../ota-hooks.mjs';
let q='.class public LX3/U;\n.method public static o(LX3/Q;)V\n .locals 0\n return-void\n.end method\n';
let result=queueHook(q,OTA_106);assert.match(result,/\.method public static turboioOriginal_o/);assert.equal(result.split('.method public static o(').length,2);assert.match(result,/allowQueue/);assert.match(result,/->blocked/);assert.match(result,/\.catch Ljava\/lang\/Throwable/);let repeated=queueHook(result,OTA_106);assert.equal(repeated.split('.method public static turboioOriginal_o').length,2);assert.equal(repeated.split('allowQueue').length,4);assert.throws(()=>queueHook(q.replace('o(LE3/Q;)','o(Ljava/lang/Object;)')));
assert.ok(result.indexOf('OfficialOtaBridge;->allowQueue')<result.indexOf('OfficialOtaPreparation;->allowQueue'));
assert.ok(result.indexOf('OfficialOtaPreparation;->allowQueue')<result.indexOf('OtaController;->allowQueue'));
assert.match(EVENT_GUARD,/if-nez v0, :ota_event_pass/);
let f='.class public LX3/u;\n.method public final u(Ljava/io/File;Ljava/lang/String;Lj4/q;Ljava/lang/String;)Ljava/lang/String;\n .locals 0\n return-object p1\n.end method\n';
result=fileHook(f,OTA_106);assert.match(result,/\.method public final turboioOriginal_u/);assert.match(result,/invoke-virtual\/range \{p0 .. p4\}/);assert.match(result,/throw v0/);assert.equal(fileHook(result,OTA_106).split('allowFile').length,3);assert.match(EVENT_GUARD,/consume/);assert.match(EVENT_GUARD,/return-void/);
assert.ok(EVENT_GUARD.indexOf('OfficialOtaBridge;->observe')<EVENT_GUARD.indexOf('OtaController;->consume'));
// 1.0.7: queue moved to Y3/V and the message class is Y3/S (not Q).
const q7='.class public LY3/V;\n.method public static o(LY3/S;)V\n .locals 0\n return-void\n.end method\n';
const r7=queueHook(q7,OTA_107);assert.equal(r7.split('.method public static turboioOriginal_o(LY3/S;)V').length,2);assert.throws(()=>queueHook(q7,OTA_106));
const f7='.class public LY3/u;\n.method public final u(Ljava/io/File;Ljava/lang/String;Lk4/q;Ljava/lang/String;)Ljava/lang/String;\n .locals 0\n return-object p1\n.end method\n';
assert.match(fileHook(f7,OTA_107),/\.method public final turboioOriginal_u\(Ljava\/io\/File;Ljava\/lang\/String;Lk4\/q;/);
// No implicit host default: an ABI must be named.
assert.throws(()=>queueHook(q7));
console.log('OTA wrapper tests passed (19 assertions); exact ABI checked again before package mutation.');
