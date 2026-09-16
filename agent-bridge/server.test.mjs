import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,stat,rm,chmod} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {initializeState,loadToken} from './server.mjs';

test('independent private token is generated once, never overwritten; insecure files rejected',async t=>{
  const parent=resolve('artifacts/hermes-integration/server-tests'); await mkdir(parent,{recursive:true});
  const dir=await mkdtemp(join(parent,'case-')); t.after(()=>rm(dir,{recursive:true,force:true}));
  await initializeState(dir);
  const tokenFile=join(dir,'bridge.token');
  const first=await readFile(tokenFile,'utf8');
  assert.match(first,/^[A-Za-z0-9_-]{64}\n$/);
  assert.equal((await stat(tokenFile)).mode & 0o777,0o600);
  assert.equal(await loadToken(dir),first.trim());
  await assert.rejects(initializeState(dir));
  assert.equal(await readFile(tokenFile,'utf8'),first);
  await chmod(tokenFile,0o644);
  await assert.rejects(loadToken(dir),/private_token_required/);
});
