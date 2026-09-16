import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const module=await import('./gateway.mjs').catch(()=>({}));
const fixture=fileURLToPath(new URL('./fixtures/gateway-fixture.mjs',import.meta.url));
const directory=fileURLToPath(new URL('..',import.meta.url));
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(predicate,ms=1500) {const end=Date.now()+ms;while(!predicate()){assert.ok(Date.now()<end,'condition was not reached');await delay(5);}}
async function setup(t,scenario='normal',extra={}) {
  assert.equal(typeof module.createHermesGateway,'function','gateway factory exists');
  const events=[],exits=[];
  const gateway=await module.createHermesGateway({python:process.execPath,cwd:directory,command:[process.execPath,fixture,scenario],rpcTimeoutMs:150,readyTimeoutMs:700,pollMs:5,onEvent:event=>events.push(event),onExit:event=>exits.push(event),...extra});
  t.after(()=>gateway.close());await gateway.start();return {gateway,events,exits};
}
test('start waits for ready; independent sessions wait for actual initialized tools',async t=>{
  const {gateway}=await setup(t);const a=await gateway.createSession(),b=await gateway.createSession();
  assert.notEqual(a.sessionId,b.sessionId);assert.ok(a.storedSessionId);
  assert.deepEqual(await gateway.readySession(a.sessionId),{ready:true});
  assert.deepEqual(await gateway.readySession(b.sessionId),{ready:true});
});
test('normalizes safe events and delays idle until the run thread actually exits',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  assert.deepEqual(await gateway.submit(sessionId,'hello'),{accepted:true});
  await until(()=>events.some(e=>e.type==='done'));
  assert.equal(events.some(e=>e.type==='idle'),false);
  await assert.rejects(gateway.submit(sessionId,'queued elsewhere'),/hermes_session_busy/);
  await until(()=>events.some(e=>e.type==='idle'));
  assert.deepEqual(events.find(e=>e.type==='text'),{sessionId,type:'text',text:'Hello '});
  assert.deepEqual(events.find(e=>e.type==='done'),{sessionId,type:'done',text:'Hello world'});
  assert.ok(!JSON.stringify(events).match(/PRIVATE|SECRET|FOREIGN|RAW|TOOL ARGS/));
  assert.ok(events.findIndex(e=>e.type==='done')<events.findIndex(e=>e.type==='idle'));
});
test('interrupt ACK does not mean idle, and long-running tasks have no RPC-sized deadline',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'long');await delay(220);
  assert.equal(events.some(e=>['done','failed','idle'].includes(e.type)),false);
  await gateway.interrupt(sessionId);assert.equal(events.some(e=>e.type==='idle'),false);
  await until(()=>events.some(e=>e.type==='idle'));
  assert.equal(events.find(e=>e.type==='done').interrupted,true);
});
test('stop during initialization prevents prompt admission and waits for confirmed idle',async t=>{
  const {gateway,events}=await setup(t,'stop-before-ready');const {sessionId}=await gateway.createSession();
  const pending=gateway.submit(sessionId,'this must never start');
  await gateway.interrupt(sessionId);
  assert.equal(events.some(event=>event.type==='idle'),false,'an interrupt ACK does not establish idle');
  assert.deepEqual(await pending,{accepted:false,interrupted:true});
  await until(()=>events.some(event=>event.type==='idle'));
  assert.deepEqual(await gateway.history(sessionId),[],'no user prompt was sent to Hermes');
  assert.deepEqual(events.filter(event=>['done','idle'].includes(event.type)),[
    {sessionId,type:'done',text:'',interrupted:true},{sessionId,type:'idle'},
  ]);
  assert.equal(events.some(event=>event.type==='text'||event.type==='failed'),false);
  assert.deepEqual(await gateway.submit(sessionId,'hello'),{accepted:true},'a later task can reuse the initialized session');
  await until(()=>events.some(event=>event.type==='done'&&event.text==='Hello world'));
});
test('approval decisions are FIFO, session-bound, one-use and never always/session approvals',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'prompt');await until(()=>events.some(e=>e.type==='prompt'));
  const first=events.find(e=>e.type==='prompt').prompt;
  assert.equal(first.id,'approve-1');assert.equal(first.kind,'approval');
  await assert.rejects(gateway.respond(sessionId,{id:'approve-2'},{choice:'once'}),/hermes_stale_prompt/);
  await assert.rejects(gateway.respond(sessionId,first,{choice:'always'}),/hermes_invalid_decision/);
  await gateway.respond(sessionId,first,{choice:'once'});
  await until(()=>events.filter(e=>e.type==='prompt').length===2);
  await assert.rejects(gateway.respond(sessionId,first,{choice:'once'}),/hermes_stale_prompt/);
  await gateway.respond(sessionId,{id:'approve-2'},{choice:'deny'});
  await until(()=>events.filter(e=>e.type==='prompt').length===3);
  const question=events.filter(e=>e.type==='prompt').at(-1).prompt;
  assert.deepEqual(question,{id:'clarify-1',kind:'clarify',title:'Which file?',options:['one','two']});
  await gateway.respond(sessionId,question,{text:'one'});
});
test('secrets require local handling and can never be entered through respond',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'local');await until(()=>events.some(e=>e.type==='prompt'));
  const prompt=events.find(e=>e.type==='prompt').prompt;assert.equal(prompt.kind,'localAction');
  assert.ok(!JSON.stringify(prompt).includes('PRIVATE'));
  await assert.rejects(gateway.respond(sessionId,prompt,{text:'do not send this secret'}),/hermes_local_action_required/);
});
test('silent upstream clarification expiry invalidates the old response',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'expired');await until(()=>events.some(e=>e.type==='promptExpired'));
  await assert.rejects(gateway.respond(sessionId,{id:'clarify-expired'},{text:'a'}),/hermes_stale_prompt/);
});
test('a prompt arriving after a status snapshot is not expired by that old snapshot',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'late-prompt');await until(()=>events.some(e=>e.type==='prompt'));
  await delay(25);assert.equal(events.some(e=>e.type==='promptExpired'),false);
  await gateway.respond(sessionId,{id:'late-question'},{text:'a'});
});
test('a transient status RPC timeout cannot turn a completed task into a failed one',async t=>{
  const {gateway,events}=await setup(t,'status-once-timeout',{rpcTimeoutMs:35});const {sessionId}=await gateway.createSession();
  await gateway.submit(sessionId,'hello');await until(()=>events.some(e=>e.type==='idle'));
  assert.equal(events.some(e=>e.type==='failed'),false);
  assert.equal(events.find(e=>e.type==='done').text,'Hello world');
});
for(const prompt of ['failed','status-error'])test(`failure ${prompt} uses fixed safe reason and still waits for actual idle`,async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();await gateway.submit(sessionId,prompt);
  await until(()=>events.some(e=>e.type==='failed'||e.type==='done'));
  assert.equal(events.some(e=>e.type==='idle'),false);assert.ok(!JSON.stringify(events).includes('SECRET'));
  await until(()=>events.some(e=>e.type==='idle'));
});
test('history retains exact user marker and assistant tool-call finality while dropping private fields',async t=>{
  const {gateway}=await setup(t);const {sessionId}=await gateway.resumeSession('stored-owned');
  assert.deepEqual(await gateway.history(sessionId),[
    {role:'user',text:'question\n\n[Norman IO request: uuid]'},
    {role:'assistant',text:'Checking',toolCalls:true},
    {role:'assistant',text:'Answer',toolCalls:false},
  ]);
  for(const method of ['history','interrupt','readySession'])await assert.rejects(gateway[method]('foreign-session'),/hermes_unknown_session/);
});
test('RPC errors are sanitized; command acceptance is not inferred after an RPC timeout',async t=>{
  const {gateway,events}=await setup(t);const {sessionId}=await gateway.createSession();
  await assert.rejects(gateway.submit(sessionId,'rpc-error'),/hermes_rpc_failed/);
  await assert.rejects(gateway.submit(sessionId,'rpc-timeout'),/hermes_rpc_timeout/);
  assert.ok(!JSON.stringify(events).includes('SECRET'));
});
test('unexpected process exit reports fixed failure and real nonzero exit status exactly once',async t=>{
  const {gateway,events,exits}=await setup(t);const {sessionId}=await gateway.createSession();await gateway.submit(sessionId,'crash');
  await until(()=>exits.length===1);assert.equal(exits[0].code,9);assert.equal(exits[0].expected,false);
  assert.equal(events.filter(e=>e.type==='failed').length,1);assert.equal(events.some(e=>e.type==='idle'),false);
  await gateway.close();assert.equal(exits.length,1);
});
test('start failure rejects without accepting requests',async t=>{
  assert.equal(typeof module.createHermesGateway,'function','gateway factory exists');
  const gateway=await module.createHermesGateway({python:process.execPath,cwd:directory,command:[process.execPath,fixture,'no-ready'],readyTimeoutMs:200});
  t.after(()=>gateway.close());await assert.rejects(gateway.start(),/hermes_gateway_exited/);
});
test('unbounded JSON line stops the peer without leaking the malformed content',async t=>{
  const {gateway,exits}=await setup(t,'oversize',{maxLineBytes:4096});
  await until(()=>exits.length===1);assert.equal(exits[0].reason,'hermes_output_limit');
});
