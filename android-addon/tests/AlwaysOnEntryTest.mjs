import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
test('production AlwaysOn entry preserves vendor callbacks before addon readiness', () => {
  const addon = fs.readFileSync(path.join(root, 'src/com/turboio/addon/TurboAddon.java'), 'utf8');
  const start = addon.indexOf('    public static void dispatchAlwaysOn(');
  const end = addon.indexOf('    public static void dispatchNlp(', start);
  assert.ok(start >= 0 && end > start);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-entry-'));
  try {
    const file = path.join(dir, 'AlwaysOnEntryFixture.java');
    fs.writeFileSync(file, `package com.turboio.addon;
import java.io.File;
public class AlwaysOnEntryFixture {
  static Object app, prefs;
  static RayneoContextQueue rayneoQueue;
  static RayneoSourceIdentity rayneoIdentity;
  static String diagnostic;
  static int uploads, calls;
  static void serial(Runnable work) { work.run(); }
  static void ensureContext() {} // Inert initialization seam; no Android or disk setup here.
  static String rayneoSourceInstance() {
    if (prefs == null) throw new NullPointerException("cold prefs");
    return rayneoIdentity.sourceInstance;
  }
  static String rayneoRecordingSession() { return rayneoIdentity.recordingSession; }
  static void scheduleRayneoUpload(int attempt) { uploads++; }
  public static class Listener {
    public void turboioOriginal_onAlwaysOnResponse(Payload response) { calls++; }
  }
  public static class Broken extends Listener {
    public void turboioOriginal_onAlwaysOnResponse(Payload response) { calls++; throw new RuntimeException(); }
  }
  public static class Payload {
    public boolean getFinished() { return true; }
    public String getText() { return "synthetic final text"; }
    public String getRoundId() { return "round-fixture"; }
    public String getRole() { return "user"; }
    public String getSessionId() { return "session-fixture"; }
  }
  static void check(boolean ok) { if (!ok) throw new AssertionError(); }
${addon.slice(start, end)}
  public static void main(String[] args) throws Exception {
    Listener listener = new Listener(); Payload payload = new Payload();
    dispatchAlwaysOn(listener, payload);
    check(calls == 1 && uploads == 0 && rayneoQueue == null);
    app = new Object(); prefs = new Object();
    dispatchAlwaysOn(listener, payload);
    check(calls == 2 && uploads == 0);
    File store = new File(args[0]);
    rayneoQueue = new RayneoContextQueue(store, 8);
    rayneoIdentity = RayneoSourceIdentity.loadOrCreate(new File(store, "identity"));
    dispatchAlwaysOn(listener, payload);
    check(calls == 3 && uploads == 1 && rayneoQueue.pendingCount() == 1);
    dispatchAlwaysOn(listener, payload);
    check(calls == 4 && uploads == 1 && rayneoQueue.pendingCount() == 1);
    dispatchAlwaysOn(new Broken(), payload);
    check(calls == 5 && uploads == 1 && rayneoQueue.pendingCount() == 1);
    System.out.println("PASS cold, unavailable, ready, duplicate, original-failure entry scenarios");
  }
}`);
    const sources = ['AlwaysOnConsume', 'RayneoContextQueue', 'RayneoCurrentQuestion', 'RayneoContextProtocol', 'RayneoSourceIdentity'];
    execFileSync('java', ['-m', 'jdk.compiler/com.sun.tools.javac.Main', '-encoding', 'UTF-8',
      '-source', '8', '-target', '8', '-d', dir,
      ...sources.map(name => path.join(root, 'src/com/turboio/addon', name + '.java')), file], {stdio: 'pipe'});
    const result = execFileSync('java', ['-cp', dir, 'com.turboio.addon.AlwaysOnEntryFixture', path.join(dir, 'queue')], {encoding: 'utf8'});
    assert.match(result, /PASS cold/);
    process.stdout.write(result);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
