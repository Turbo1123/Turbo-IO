import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {wrapHostCallback} from '../host-callbacks.mjs';

test('notification observer keeps vendor-first delivery and is idempotent', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-callback-'));
  try {
    const file = path.join(dir, 'listener.smali');
    const signature = '(Landroid/service/notification/StatusBarNotification;)V';
    const original = '.class public Lsynthetic/Notifications;\n.method public final onNotificationPosted' + signature
      + '\n    .locals 0\n    # synthetic vendor body\n    return-void\n.end method\n';
    fs.writeFileSync(file, original);
    wrapHostCallback(file, 'onNotificationPosted', signature, 'p0 .. p1');
    const first = fs.readFileSync(file, 'utf8');
    assert.match(first, /# synthetic vendor body/);
    assert.match(first, /turboioOriginal_onNotificationPosted/);
    assert.match(first, /TurboAddon;->notificationPosted\(Ljava\/lang\/Object;Landroid\/service\/notification\/StatusBarNotification;\)V/);
    assert.match(first, /\.catch Ljava\/lang\/Throwable;/);
    assert.ok(first.indexOf('turboioOriginal_onNotificationPosted', first.indexOf(':turboio_try') - 180) < first.indexOf('TurboAddon;->notificationPosted'));
    wrapHostCallback(file, 'onNotificationPosted', signature, 'p0 .. p1');
    const second = fs.readFileSync(file, 'utf8');
    assert.equal(second.match(/\.method public final onNotificationPosted/g).length, 1);
    assert.equal(second.match(/\.method public final turboioOriginal_onNotificationPosted/g).length, 1);
    assert.equal(second.match(/# synthetic vendor body/g).length, 1);
    assert.throws(() => wrapHostCallback(file, 'onNotificationPosted', '()V', 'p0 .. p0'));
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
