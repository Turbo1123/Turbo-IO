import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {TaskService} from './tasks.mjs';

const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const input=(n=1)=>({requestId:id(n),conversationId:id(90),text:'write fixture'});
const tick=()=>new Promise(ok=>setTimeout(ok,15));
async function submitted(calls,count=1) {
  for(let i=0;i<100;i++) {if(calls.filter(x=>x==='launched'||x[0]==='submit').length>=count)return;await tick();}
  assert.fail('fixture did not receive a submission');
}
async function setup(t) {
  const root=resolve('artifacts/hermes-tasks/task-tests'); await mkdir(root,{recursive:true});
  const dir=await mkdtemp(join(root,'case-')); t.after(()=>rm(dir,{recursive:true,force:true}));
  const calls=[];
  const gateway={
    async createSession(){calls.push('create'); return {sessionId:'live',storedSessionId:'stored'};},
    async resumeSession(stored){calls.push(['resume',stored]);return {sessionId:'live',storedSessionId:stored};},
    async readySession(){},
    async submit(session,text){calls.push(['submit',session,text]);},
    async interrupt(session){calls.push(['interrupt',session]);},
    async respond(...args){calls.push(['respond',...args]);},
    async history(){return [];}, async close(){}
  };
  const ledger=join(dir,'tasks.json');
  const service=await TaskService.open({gateway,ledger});
  return {service,gateway,calls,ledger};
}
const event=(type,extra={})=>({sessionId:'live',type,...extra});
test('admission persists before submit and duplicate IDs never launch again',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);
  gateway.submit=async()=>{const disk=JSON.parse(await readFile(ledger));assert.equal(disk.tasks[0].requestId,id(1));calls.push('launched');};
  assert.equal((await service.submit(input())).status,'running'); await submitted(calls);
  await service.submit(input()); assert.equal(calls.filter(x=>x==='launched').length,1);
  await assert.rejects(service.submit({...input(),text:'different'}),/request_conflict/);
  await assert.rejects(service.submit(input(2)),/busy/);
});
test('progress and final text do not mean execution ended; idle completes',async t=>{
  const {service,calls}=await setup(t); await service.submit(input()); await submitted(calls);
  await service.handleEvent(event('progress',{text:'正在运行脚本'}));
  await service.handleEvent(event('done',{text:'文件已写入'}));
  assert.equal((await service.get(id(1))).status,'running');
  await service.handleEvent(event('idle'));
  assert.equal((await service.get(id(1))).status,'completed');
  assert.equal((await service.get(id(1))).answer,'文件已写入');
  await service.submit(input(2)); await submitted(calls,2);
});
test('stop sends interrupt but waits for actual interrupted final and idle',async t=>{
  const {service,calls}=await setup(t); await service.submit(input());await submitted(calls);
  assert.equal((await service.stop(id(1),id(90))).status,'stopping');
  assert.ok(calls.some(x=>x[0]==='interrupt'));
  await service.handleEvent(event('done',{text:'',interrupted:true}));
  assert.equal((await service.get(id(1))).status,'stopping');
  await service.handleEvent(event('idle'));
  assert.equal((await service.get(id(1))).status,'cancelled');
});
test('completion racing stop preserves proven completion',async t=>{
  const {service,calls}=await setup(t); await service.submit(input());await submitted(calls);
  await service.handleEvent(event('done',{text:'done'}));await service.stop(id(1),id(90));
  await service.handleEvent(event('idle'));assert.equal((await service.get(id(1))).status,'completed');
});
test('stop before submit reserves a tombstone',async t=>{
  const {service,calls}=await setup(t);
  await service.stop(id(1),id(90));
  assert.equal((await service.submit(input())).status,'cancelled');assert.equal(calls.length,0);
});
test('prompt decision is bound to current task, id, kind; duplicates cannot approve next prompt',async t=>{
  const {service,calls}=await setup(t); await service.submit(input());await submitted(calls);
  await service.handleEvent(event('prompt',{prompt:{id:'upstream',kind:'approval',title:'执行命令',options:[]}}));
  const first=await service.get(id(1));assert.equal(first.status,'waiting');
  const decision={conversationId:id(90),promptId:first.prompt.id,decisionId:id(3),choice:'once'};
  await assert.rejects(service.decide(id(1),{...decision,choice:'always'}),/invalid_decision/);
  await service.decide(id(1),decision);
  await service.handleEvent(event('prompt',{prompt:{id:'upstream2',kind:'approval',title:'另一个命令',options:[]}}));
  await service.decide(id(1),decision);
  assert.equal(calls.filter(x=>x[0]==='respond').length,1);
  assert.notEqual((await service.get(id(1))).prompt.id,first.prompt.id);
  await assert.rejects(service.decide(id(1),{...decision,decisionId:id(4)}),/stale_prompt/);
});
test('clarification is distinct from approval and expired prompts cannot receive decisions',async t=>{
  const {service,calls}=await setup(t);await service.submit(input());await submitted(calls);
  await service.handleEvent(event('prompt',{prompt:{id:'q',kind:'clarify',title:'文件叫什么？',options:['a','b']}}));
  const p=(await service.get(id(1))).prompt;
  await assert.rejects(service.decide(id(1),{conversationId:id(90),promptId:p.id,decisionId:id(4),choice:'once'}),/invalid_decision/);
  await service.handleEvent(event('promptExpired',{id:'q'}));
  await assert.rejects(service.decide(id(1),{conversationId:id(90),promptId:p.id,decisionId:id(4),text:'a'}),/stale_prompt/);
});
test('restart preserves IDs and session ownership, marks uncertain work without replay',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);await service.submit(input());await submitted(calls);
  const recovered=await TaskService.open({gateway,ledger});
  assert.equal((await recovered.submit(input())).status,'unknown');
  assert.equal(calls.filter(x=>x[0]==='submit').length,1);
  const disk=await readFile(ledger,'utf8');assert.ok(!disk.includes('write fixture'));
  await assert.rejects(recovered.submit({...input(2),conversationId:id(91)}),/reconcile_required/);
});
test('recover completed output only from owned session history and matching task marker',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);await service.submit(input());await submitted(calls);
  await service.handleEvent(event('done',{text:'answer'}));await service.handleEvent(event('idle'));
  gateway.history=async()=>[{role:'user',text:'write fixture\n\n[Norman IO request: '+id(1)+']'},{role:'assistant',text:'answer'}];
  const recovered=await TaskService.open({gateway,ledger});
  const state=await recovered.get(id(1));assert.equal(state.status,'completed');assert.equal(state.answer,'answer');
});
test('gateway exit never becomes successful completion or confirmed cancellation',async t=>{
  const {service,calls}=await setup(t);await service.submit(input());await submitted(calls);
  await service.gatewayExited();assert.equal((await service.get(id(1))).status,'unknown');
});
test('rejects arbitrary request fields, invalid ids and oversized input',async t=>{
  const {service,calls}=await setup(t);
  for(const patch of [{cwd:'/tmp'},{requestId:'bad'},{text:''},{text:'x'.repeat(8193)}]) await assert.rejects(service.submit({...input(),...patch}),/invalid_request/);
});
test('historical terminal records do not block new tasks after restart',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);await service.submit(input());await submitted(calls);
  await service.handleEvent(event('done',{text:'first'}));await service.handleEvent(event('idle'));
  await service.submit(input(2));await submitted(calls,2);await service.handleEvent(event('done',{text:'second'}));await service.handleEvent(event('idle'));
  const recovered=await TaskService.open({gateway,ledger});
  assert.equal((await recovered.submit(input(3))).status,'running');await submitted(calls,3);
});
test('health retries failed initialization rather than trusting a cached live ID',async t=>{
  const {service,gateway}=await setup(t);let ready=false;
  gateway.readySession=async()=>{if(!ready)throw new Error('initialization');};
  await assert.rejects(service.health(id(90)),/hermes_not_ready/);
  await assert.rejects(service.health(id(90)),/hermes_not_ready/);
  ready=true;assert.equal((await service.health(id(90))).ready,true);
});
test('an owned never-submitted draft can be recreated after restart',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);await service.health(id(90));
  gateway.resumeSession=async()=>{throw new Error('not_persisted_yet');};
  const recovered=await TaskService.open({gateway,ledger});
  assert.equal((await recovered.health(id(90))).ready,true);
});
test('proven cancellation before first admission retains recoverable draft',async t=>{
  const {service,gateway,ledger,calls}=await setup(t);
  gateway.submit=async()=>{calls.push('launched');await service.handleEvent(event('done',{text:'',interrupted:true}));await service.handleEvent(event('idle'));return {accepted:false,interrupted:true};};
  await service.submit(input());await submitted(calls);await tick();
  assert.equal((await service.get(id(1))).status,'cancelled');
  gateway.resumeSession=async()=>{throw new Error('no_database_row');};
  const recovered=await TaskService.open({gateway,ledger});
  assert.equal((await recovered.health(id(90))).ready,true);
});
test('valid metadata capacity remains readable beyond one MiB',async t=>{
  const {gateway,ledger}=await setup(t);
  const tasks=Array.from({length:512},(_,n)=>({requestId:id(1000+n),conversationId:id(90),digest:'d'.repeat(64),status:'completed',revision:1,
    decisions:Array.from({length:16},(_,k)=>({id:id(k),digest:'a'.repeat(64)}))}));
  const encoded=JSON.stringify({version:2,sessions:[],tasks});assert.ok(Buffer.byteLength(encoded)>1048576);
  await writeFile(ledger,encoded,{mode:0o600});
  const recovered=await TaskService.open({gateway,ledger});
  assert.equal((await recovered.get(id(1000))).status,'completed');
});
test('an unconfirmed stop can be explicitly retried while stopping',async t=>{
  const {service,gateway,calls}=await setup(t);await service.submit(input());await submitted(calls);
  let attempts=0;gateway.interrupt=async()=>{if(++attempts===1)throw new Error('transient');};
  await assert.rejects(service.stop(id(1),id(90)),/stop_unconfirmed/);
  assert.equal((await service.get(id(1))).status,'stopping');
  assert.equal((await service.stop(id(1),id(90))).status,'stopping');assert.equal(attempts,2);
});
