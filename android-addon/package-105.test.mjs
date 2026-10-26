import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {deflateRawSync} from 'node:zlib';
import {profileFor} from './host-profiles.mjs';
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

test('compatibility entry delegates to the maintained packaging chain', () => {
  const legacy = fs.readFileSync(path.join(root, 'package-105.mjs'), 'utf8');
  assert.match(legacy, /await import\('\.\/package\.mjs'\)/);
  assert.equal(legacy.includes('NavGlasses;->event'), false);
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

test('raw deflated resources survive without dropping manifest, public assets or addon DEX', () => {
  const raw = storedEntry('res/Case.xml', Buffer.from('synthetic-resource-'.repeat(50)));
  raw.data = deflateRawSync(raw.data, {level: 1});
  raw.method = 8;
  raw.compSize = raw.data.length;
  const official = writeZipEntries([raw, storedEntry('resources.arsc', Buffer.from('arsc'))]);
  const retained = [storedEntry('AndroidManifest.xml', Buffer.from('patched-manifest')),
    storedEntry('assets/turboio/public.bin', Buffer.from('public-asset')),
    storedEntry('classes4.dex', Buffer.from('addon-dex'))];
  const rebuilt = writeZipEntries([...retained, storedEntry('res/unapproved.xml', Buffer.from('remove'))]);
  const restored = restoreOfficialResources(official, rebuilt);
  const entries = new Map(readZipEntries(restored).map(entry => [entry.name, entry]));
  const actual = entries.get(raw.name);
  for (const field of ['method', 'compSize', 'size', 'crc']) assert.equal(actual[field], raw[field]);
  assert.deepEqual(actual.data, raw.data);
  for (const entry of retained) assert.deepEqual(entries.get(entry.name).data, entry.data);
  const result = compareOfficialResources(official, restored);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.unauthorized, []);
  assert.equal(entries.has('res/unapproved.xml'), false);
});

test('optional pinned 1.0.6/1.0.7 resource evidence restore', {skip: !process.env.RAYNEO_OFFICIAL_APK}, () => {
  const officialPath = process.env.RAYNEO_OFFICIAL_APK;
  if (!officialPath) return;
  assert.ok(fs.existsSync(officialPath), 'Explicit official APK input is absent');
  const official = fs.readFileSync(officialPath);
  const sha = crypto.createHash('sha256').update(official).digest('hex');
  assert.ok([216,230].includes(profileFor(sha).code));
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
  assert.ok(comparison.officialCount > 0);
});
