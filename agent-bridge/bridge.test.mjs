import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {createServer} from 'node:http';
import {TaskBridge, createHandler} from './bridge.mjs';

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const input = (n=1, conversation=90) => ({agent:'hermes',workspaceId:'conversation',requestId:id(n),conversationId:id(conversation),mode:'read-only',text:'你好，研究助理'});
const tick = () => new Promise(resolve => setImmediate(resolve));
async function fixture(t, run) {
  const parent=resolve('artifacts/hermes-integration/bridge-tests'); await mkdir(parent,{recursive:true});
  const dir = await mkdtemp(join(parent,'case-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const ledger = join(dir,'ledger.json');
  const bridge = await TaskBridge.open({run,ledger});
  return {bridge,ledger};
}
test('real task contract and independent conversation context; duplicate requests do not rerun', async t => {
  const calls=[];
  const {bridge}=await fixture(t,async request=>{calls.push(request);return '你好。';});
  const first=await bridge.submit(input());
  assert.equal(first.taskId,id(1));
  await tick();
  assert.equal(bridge.get(id(1)).answer,'你好。');
  assert.equal(bridge.get(id(1)).status,'completed');
  await bridge.submit(input());
  assert.equal(calls.length,1);
  await bridge.submit(input(2)); await tick();
  assert.deepEqual(calls[1].history,[{role:'user',content:input().text},{role:'assistant',content:'你好。'}]);
  await bridge.submit(input(3,91)); await tick();
  assert.deepEqual(calls[2].history,[]);
  await assert.rejects(bridge.submit({...input(),text:'changed'}),/request_conflict/);
});
test('stop before delivery reserves ID and prevents a delayed POST from starting', async t=>{
  let calls=0;
  const {bridge}=await fixture(t,async()=>{calls++;return 'wrong';});
  assert.equal((await bridge.stop(id(1),id(90))).status,'cancelled');
  assert.equal((await bridge.submit(input())).status,'cancelled');
  assert.equal(calls,0);
});
test('cancellation waits for worker exit, ignores late answer, and clears no other conversation', async t=>{
  let exit;
  const {bridge}=await fixture(t,(_,{signal})=>new Promise(resolve=>{
    signal.addEventListener('abort',()=>{exit=()=>resolve('late answer');});
  }));
  await bridge.submit(input());
  const stopping=bridge.stop(id(1),id(90)); await tick();
  assert.equal(bridge.get(id(1)).status,'running');
  exit(); await stopping;
  assert.equal(bridge.get(id(1)).status,'cancelled');
  assert.equal(bridge.get(id(1)).answer,'');
});
test('rejects arbitrary agents, modes, workspaces, invalid IDs and oversized text', async t=>{
  const {bridge}=await fixture(t,async()=>assert.fail('must not launch'));
  for(const patch of [{agent:'codex'},{mode:'write'},{workspaceId:'/tmp'},{requestId:'../../x'},{conversationId:'x'},{text:''},{text:'字'.repeat(3000)},{extra:true}]) {
    await assert.rejects(bridge.submit({...input(),...patch}),/invalid_request/);
  }
});
test('metadata ledger contains no prompts or answers, and restart never replays old work', async t=>{
  const {bridge,ledger}=await fixture(t,async()=> 'private answer');
  await bridge.submit(input()); await tick();
  const disk=await readFile(ledger,'utf8');
  assert.ok(!disk.includes(input().text)); assert.ok(!disk.includes('private answer'));
  const recovered=await TaskBridge.open({ledger,run:async()=>assert.fail('replay')});
  await assert.rejects(recovered.submit(input()),/delivery_unknown/);
  assert.equal((await recovered.stop(id(1),id(90))).status,'cancelled');
});
test('worker failure is sanitized and cannot silently call another backend', async t=>{
  const {bridge}=await fixture(t,async()=>{throw new Error('sk-private-secret');});
  await bridge.submit(input()); await tick();
  assert.equal(bridge.get(id(1)).status,'failed');
  assert.ok(!JSON.stringify(bridge.get(id(1))).includes('secret'));
});
test('shutdown rejects in-flight reservations and cannot leave a detached worker running',async t=>{
  let release, calls=0;
  const {bridge}=await fixture(t,async()=>{calls++;return 'wrong';});
  const reserve=bridge.reserve.bind(bridge);
  bridge.reserve=async task=>{await new Promise(resolve=>{release=resolve;});await reserve(task);};
  const submission=bridge.submit(input()); await tick();
  const shutdown=bridge.shutdown(); release();
  await Promise.all([submission,shutdown]);
  assert.equal(calls,0);
  assert.equal(bridge.get(id(1)).status,'cancelled');
  await assert.rejects(bridge.submit(input(2)),/shutting_down/);
});
test('HTTP requires bearer, rejects browser origin and malformed bodies, exposes bounded state', async t=>{
  const {bridge}=await fixture(t,async()=> '回答');
  const token='T'.repeat(48);
  const server=createServer(createHandler(bridge,token));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{server.closeAllConnections();server.close();});
  const base=`http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base+'/v1/health')).status,401);
  const headers={Authorization:`Bearer ${token}`,'Content-Type':'application/json'};
  assert.equal((await fetch(base+'/v1/health',{headers:{...headers,Origin:'https://evil.example'}})).status,403);
  const health=await (await fetch(base+'/v1/health',{headers})).json();
  assert.equal(health.protocolVersion,1);
  assert.equal((await fetch(base+'/v1/tasks',{method:'POST',headers,body:'{'})).status,400);
  assert.equal((await fetch(base+'/v1/tasks',{method:'POST',headers,body:'x'.repeat(20000)})).status,413);
  const result=await (await fetch(base+'/v1/tasks',{method:'POST',headers,body:JSON.stringify(input())})).json();
  assert.equal(result.taskId,id(1));
  assert.equal((await fetch(base+'/v1/tasks/../../etc/passwd',{headers})).status,404);
  const stop=await (await fetch(base+'/v1/tasks/'+id(8)+'/stop',{method:'POST',headers,body:JSON.stringify({conversationId:id(92)})})).json();
  assert.equal(stop.conversationId,id(92));
  assert.equal(stop.status,'cancelled');
});
