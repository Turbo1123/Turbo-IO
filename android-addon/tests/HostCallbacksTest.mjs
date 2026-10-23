import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {wrapHostCallback} from '../host-callbacks.mjs';
import {verifyHost} from '../host-profiles.mjs';

test('AlwaysOn callback keeps vendor body and is idempotent with fallback', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-callback-'));
  try {
    const file = path.join(dir, 'listener.smali');
    const signature = '(Lcom/rayneo/airuntime/controller/RayNeoAlwaysOnResponse;)V';
    const original = '.class public LF7/i$b;\n.method public final onAlwaysOnResponse' + signature
      + '\n    .locals 0\n    # synthetic vendor body\n    return-void\n.end method\n';
    fs.writeFileSync(file, original);
    wrapHostCallback(file, 'onAlwaysOnResponse', signature, 'p0 .. p1');
    const first = fs.readFileSync(file, 'utf8');
    assert.match(first, /# synthetic vendor body/);
    assert.match(first, /turboioOriginal_onAlwaysOnResponse/);
    assert.match(first, /TurboAddon;->dispatchAlwaysOn\(Ljava\/lang\/Object;Ljava\/lang\/Object;\)V/);
    assert.match(first, /\.catch Ljava\/lang\/Throwable;/);
    assert.ok(first.indexOf('dispatchAlwaysOn') < first.lastIndexOf('turboioOriginal_onAlwaysOnResponse'));
    wrapHostCallback(file, 'onAlwaysOnResponse', signature, 'p0 .. p1');
    const second = fs.readFileSync(file, 'utf8');
    assert.equal(second.match(/\.method public final onAlwaysOnResponse/g).length, 1);
    assert.equal(second.match(/\.method public final turboioOriginal_onAlwaysOnResponse/g).length, 1);
    assert.equal(second.match(/# synthetic vendor body/g).length, 1);
    assert.throws(() => wrapHostCallback(file, 'onAlwaysOnResponse', '()V', 'p0 .. p0'));
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('missing AlwaysOn ABI rejects before any host file changes', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-abi-'));
  try {
    const listener = path.join(dir, 'smali/H7/c$c.smali');
    fs.mkdirSync(path.dirname(listener), {recursive: true});
    const before = '.class public LH7/c$c;\n'
      + '.method public final onAsrResult(Ljava/lang/String;ZLjava/lang/String;)V\n'
      + '.method public final onNlpResult(Lcom/rayneo/airuntime/controller/NlpResult;)V\n'
      + '.method public final onResponseComplete()V\n';
    fs.writeFileSync(listener, before);
    assert.throws(() => verifyHost(dir, {version: '1.0.5', code: 201}), /F7\/i\$b/);
    assert.equal(fs.readFileSync(listener, 'utf8'), before);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
