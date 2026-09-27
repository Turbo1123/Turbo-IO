import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {profileFor,classFile,verifyHost} from '../host-profiles.mjs';
assert.equal(profileFor('770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3').code,201);
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
  assert.throws(()=>verifyHost(dir,{version:'1.0.5',code:201}));
} finally { fs.rmSync(dir,{recursive:true}); }
console.log('Host profile tests passed (7 assertions).');
