import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TaskBridge, createHandler } from './bridge.mjs';

class FakeRPC extends EventEmitter {
  calls = []; replies = []; early = false;
  async request(method, params) {
    this.calls.push({ method, params });
    if (method === 'thread/start') return { thread: { id: 'thread-a' } };
    if (method === 'turn/start') {
      this.emit('message', { method: 'turn/started', params: { threadId: 'thread-a', turn: { id: 'turn-a' } } });
      if (this.early) this.emit('message', { method: 'turn/completed', params: { threadId: 'thread-a', turn: { id: 'turn-a', status: 'completed' } } });
      return { turn: { id: 'turn-a' } };
    }
    return {};
  }
  send(msg) { this.replies.push(msg); }
}
const rid = () => crypto.randomUUID();
async function fixture(options = {}) {
  const rpc = new FakeRPC(); const bridge = new TaskBridge(rpc, { cwd: '/synthetic/workspace', ...options });
  const result = await bridge.message({ text: 'synthetic task', requestId: rid() });
  return { rpc, bridge, taskId: result.taskId };
}
function approval(rpc, overrides = {}) { rpc.emit('message', { id: 123, method: 'item/commandExecution/requestApproval', params: { threadId: 'thread-a', turnId: 'turn-a', command: 'synthetic operation', ...overrides } }); }
test('only starts read-only user-reviewed tasks', async () => {
  const { rpc } = await fixture(); const p = rpc.calls[0].params;
  assert.equal(p.sandbox, 'read-only'); assert.equal(p.approvalPolicy, 'on-request'); assert.equal(p.approvalsReviewer, 'user');
});
test('idempotent submissions do not create second tasks', async () => {
  const rpc = new FakeRPC(), b = new TaskBridge(rpc, { cwd: '/synthetic' });
  const input = { text: 'sample', requestId: rid() };
  assert.deepEqual(await b.message(input), await b.message(input)); assert.equal(rpc.calls.length, 2);
});
test('early completion is never resurrected', async () => {
  const rpc = new FakeRPC(); rpc.early = true; const b = new TaskBridge(rpc, { cwd: '/synthetic' });
  await b.message({ text: 'sample', requestId: rid() }); assert.equal(b.snapshot().tasks[0].turnId, null);
});
test('late other-turn output ignored', async () => {
  const { rpc, bridge } = await fixture();
  rpc.emit('message', { method: 'item/agentMessage/delta', params: { threadId: 'thread-a', turnId: 'old', delta: 'do not show' } });
  assert.equal(bridge.snapshot().tasks[0].answer, '');
});
test('approval is pending and bound to exact task; replay rejected', async () => {
  const { rpc, bridge, taskId } = await fixture(); approval(rpc);
  assert.equal(rpc.replies.length, 0); const id = bridge.snapshot().tasks[0].pending[0].id;
  await assert.rejects(bridge.decide({ taskId: 'wrong', approvalId: id, decision: 'accept', requestId: rid() }));
  await bridge.decide({ taskId, approvalId: id, decision: 'accept', requestId: rid() });
  assert.deepEqual(rpc.replies[0], { id: 123, result: { decision: 'accept' } });
  await assert.rejects(bridge.decide({ taskId, approvalId: id, decision: 'accept', requestId: rid() }));
});
test('expired approvals fail closed', async () => {
  let now = 0; const { rpc, bridge, taskId } = await fixture({ now: () => now }); approval(rpc);
  const id = bridge.snapshot().tasks[0].pending[0].id; now = 120001;
  await assert.rejects(bridge.decide({ taskId, approvalId: id, decision: 'accept', requestId: rid() }));
  assert.equal(rpc.replies[0].result.decision, 'decline');
});
test('unknown server request is never approved', async () => {
  const { rpc } = await fixture(); rpc.emit('message', { id: 42, method: 'arbitrary/permission', params: {} });
  assert.ok(rpc.replies[0].error); assert.equal(rpc.replies[0].result, undefined);
});
test('completion clears pending approvals', async () => {
  const { rpc, bridge } = await fixture(); approval(rpc);
  rpc.emit('message', { method: 'turn/completed', params: { threadId: 'thread-a', turn: { id: 'turn-a', status: 'interrupted' } } });
  assert.equal(bridge.snapshot().tasks[0].pending.length, 0);
});
test('questions require all explicit answers', async () => {
  const { rpc, bridge, taskId } = await fixture();
  rpc.emit('message', { id: 8, method: 'item/tool/requestUserInput', params: { threadId: 'thread-a', turnId: 'turn-a', questions: [{ id: 'q1', question: 'pick', options: [] }] } });
  const id = bridge.snapshot().tasks[0].pending[0].id;
  await assert.rejects(bridge.decide({ taskId, approvalId: id, answers: {}, requestId: rid() }));
  await bridge.decide({ taskId, approvalId: id, answers: { q1: 'user answer' }, requestId: rid() });
  assert.deepEqual(rpc.replies[0].result, { answers: { q1: { answers: ['user answer'] } } });
});
test('ledger survives restart without replaying accepted mutation', async () => {
  const root = mkdtempSync(join(tmpdir(), 'rayneo-codex-test-')), stateFile = join(root, 'ledger.json');
  const rpc = new FakeRPC(), b = new TaskBridge(rpc, { cwd: '/synthetic', stateFile });
  const input = { text: 'sample', requestId: rid() }, result = await b.message(input);
  const other = new FakeRPC(), restored = new TaskBridge(other, { cwd: '/synthetic', stateFile });
  assert.deepEqual(await restored.message(input), result); assert.equal(other.calls.length, 0);
});
test('HTTP rejects no auth, cross-origin and arbitrary RPC paths', async t => {
  const b = new TaskBridge(new FakeRPC(), { cwd: '/synthetic' }), token = 'a'.repeat(40);
  const s = http.createServer(createHandler(b, token)); await new Promise(r => s.listen(0, '127.0.0.1', r));
  t.after(() => s.close()); const url = `http://127.0.0.1:${s.address().port}`;
  assert.equal((await fetch(url + '/v1/state')).status, 401);
  assert.equal((await fetch(url + '/v1/state', { headers: { authorization: 'Bearer ' + token, origin: 'https://evil.invalid' } })).status, 401);
  assert.equal((await fetch(url + '/command/exec', { headers: { authorization: 'Bearer ' + token } })).status, 404);
  assert.equal((await fetch(url + '/v1/state', { headers: { authorization: 'Bearer ' + token } })).status, 200);
});

test('completion event contains final answer once and has bounded lifetime', async () => {
  let now = 1000; const {rpc, bridge} = await fixture({now: () => now});
  rpc.emit('message', {method:'item/agentMessage/delta',params:{threadId:'thread-a',turnId:'turn-a',delta:'commentary'}});
  rpc.emit('message', {method:'item/completed',params:{threadId:'thread-a',turnId:'turn-a',item:{type:'agentMessage',phase:'final_answer',text:'PUSH-7392'}}});
  const complete = {method:'turn/completed',params:{threadId:'thread-a',turn:{id:'turn-a',status:'completed'}}};
  rpc.emit('message',complete); rpc.emit('message',complete);
  const events = bridge.snapshot().events;
  assert.equal(events.length,1); assert.equal(events[0].content,'PUSH-7392'); assert.equal(events[0].turnId,'turn-a');
  now += 3600001; assert.equal(bridge.snapshot().events.length,0);
});
test('resolved or expired approval is removed from push events; notification never approves', async () => {
  const {rpc,bridge,taskId} = await fixture(); approval(rpc);
  assert.equal(bridge.snapshot().events[0].kind,'approval'); assert.equal(rpc.replies.length,0);
  const id = bridge.snapshot().tasks[0].pending[0].id;
  await bridge.decide({taskId,approvalId:id,decision:'decline',requestId:rid()});
  assert.equal(bridge.snapshot().events.length,0);
});
test('push event queue bounded and unicode safe', async () => {
  const {bridge,taskId} = await fixture(); const task=bridge.tasks.get(taskId);
  for(let n=0;n<140;n++) bridge.notify(task,{kind:'completed',title:'test',content:'😀'.repeat(400),turnId:'turn-'+n});
  const events=bridge.snapshot().events; assert.equal(events.length,128);
  assert.equal(Array.from(events[0].content).length,350); assert.equal(events[0].content.includes('\ufffd'),false);
});
test('stop reply cannot overwrite early completed status', async () => {
  const {rpc,bridge,taskId} = await fixture(); const original=rpc.request.bind(rpc);
  rpc.request=async (method,p) => {
    if(method==='turn/interrupt') rpc.emit('message',{method:'turn/completed',params:{threadId:'thread-a',turn:{id:'turn-a',status:'interrupted'}}});
    return original(method,p);
  };
  await bridge.stop({taskId,requestId:rid()}); assert.equal(bridge.snapshot().tasks[0].status,'已停止');
});
