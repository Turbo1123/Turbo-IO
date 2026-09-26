import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {
  addStoredFile,
  compareOfficialResources,
  isResourceName,
  readZipEntries,
  restoreOfficialResources,
  storedEntry,
  writeZipEntries,
} from './package-105.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const repo = path.join(root, '..');

test('package.mjs is unchanged from git HEAD', () => {
  const diff = execFileSync('git', ['diff', 'HEAD', '--', 'android-addon/package.mjs'], {
    encoding: 'utf8',
    cwd: repo,
  });
  assert.equal(diff, '');
});

test('synthetic colliding res/ names restore from ZIP entries without extracting', () => {
  const low = storedEntry('res/2f.xml', Buffer.from('<low/>'));
  const high = storedEntry('res/2F.xml', Buffer.from('<HIGH/>'));
  const arsc = storedEntry('resources.arsc', Buffer.from('ARSC-OFFICIAL'));
  const dex = storedEntry('classes.dex', Buffer.from('official-dex'));
  const official = writeZipEntries([low, high, arsc, dex]);

  const folded = storedEntry('res/2F.xml', Buffer.from('<HIGH/>'));
  const wrongArsc = storedEntry('resources.arsc', Buffer.from('ARSC-REBUILT'));
  const rebuiltDex = storedEntry('classes.dex', Buffer.from('rebuilt-dex'));
  const addon = storedEntry('classes4.dex', Buffer.from('addon-dex'));
  const built = writeZipEntries([folded, wrongArsc, rebuiltDex, addon]);

  const before = compareOfficialResources(official, built);
  assert.ok(before.missing.includes('res/2f.xml'));
  assert.ok(before.unauthorized.includes('resources.arsc'));

  const restored = restoreOfficialResources(official, built);
  const names = readZipEntries(restored).map(entry => entry.name);
  assert.ok(names.includes('res/2f.xml'));
  assert.ok(names.includes('res/2F.xml'));
  assert.ok(names.includes('resources.arsc'));
  assert.ok(names.includes('classes4.dex'));
  assert.ok(names.includes('classes.dex'));
  assert.equal(names.filter(name => name === 'res/2f.xml' || name === 'res/2F.xml').length, 2);

  const after = compareOfficialResources(official, restored);
  assert.equal(after.missing.length, 0);
  assert.equal(after.unauthorized.length, 0);
  assert.equal(after.officialCount, 3);

  const byName = new Map(readZipEntries(restored).map(entry => [entry.name, entry]));
  assert.equal(Buffer.compare(byName.get('res/2f.xml').data, low.data), 0);
  assert.equal(Buffer.compare(byName.get('res/2F.xml').data, high.data), 0);
  assert.equal(byName.get('res/2f.xml').method, 0);
  assert.equal(byName.get('resources.arsc').crc, arsc.crc);
  assert.equal(Buffer.compare(byName.get('classes4.dex').data, addon.data), 0);
  assert.equal(Buffer.compare(byName.get('classes.dex').data, rebuiltDex.data), 0);

  const broken = addStoredFile(restored, 'res/2f.xml', Buffer.from('<tampered/>'));
  const tampered = compareOfficialResources(official, broken);
  assert.ok(tampered.unauthorized.includes('res/2f.xml'));
  assert.ok(isResourceName('resources.arsc'));
});

test('optional official APK evidence restore when the local file is present', {skip: !process.env.RAYNEO_OFFICIAL_APK}, () => {
  const officialPath = process.env.RAYNEO_OFFICIAL_APK;
  if (!officialPath) return;
  if (!fs.existsSync(officialPath)) {
    console.log('official 1.0.5 APK absent; synthetic ZIP gate still holds');
    return;
  }
  const official = fs.readFileSync(officialPath);
  const sha = crypto.createHash('sha256').update(official).digest('hex');
  assert.equal(sha, '770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3');
  const dummy = writeZipEntries([
    storedEntry('classes.dex', Buffer.from('x')),
    storedEntry('res/2F.xml', Buffer.from('folded')),
    storedEntry('resources.arsc', Buffer.from('nope')),
  ]);
  const restored = restoreOfficialResources(official, dummy);
  const comparison = compareOfficialResources(official, restored);
  console.log('official resource evidence official=' + comparison.officialCount
    + ' missing=' + comparison.missing.length
    + ' unauthorized=' + comparison.unauthorized.length);
  assert.equal(comparison.missing.length, 0);
  assert.equal(comparison.unauthorized.length, 0);
  assert.ok(comparison.officialCount >= 1605);
});
