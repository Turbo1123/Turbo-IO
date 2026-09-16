import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, rm, realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHermesRunner} from './adapter.mjs';

async function fixture(t,source,timeoutMs=3000) {
  const parent=resolve('artifacts/hermes-integration/adapter-tests'); await mkdir(parent,{recursive:true});
  const workspace=await mkdtemp(join(parent,'case-')); t.after(()=>rm(workspace,{recursive:true,force:true}));
  const worker=join(workspace,'fixture.cjs'); await writeFile(worker,source);
  return createHermesRunner({python:process.execPath,workspace,worker,timeoutMs});
}
test('worker receives text via stdin, never argv, and only structured answer is accepted',async t=>{
  const run=await fixture(t,`const p=JSON.parse(require('fs').readFileSync(0,'utf8')); if(process.argv.join(' ').includes(p.text))process.exit(1);console.log(JSON.stringify({answer:p.text}));`);
  assert.equal(await run({text:'PRIVATE QUESTION',history:[]},{}),'PRIVATE QUESTION');
});
test('cancelled worker is terminated before rejection and a later response is discarded',async t=>{
  const run=await fixture(t,`setTimeout(()=>console.log('{"answer":"late"}'),20000);`);
  const controller=new AbortController();
  const task=run({text:'x',history:[]},{signal:controller.signal});
  setTimeout(()=>controller.abort(),50);
  await assert.rejects(task,/cancelled/);
});
test('deadline and unstructured or overflowing stdout are safe failures',async t=>{
  for(const source of [`setTimeout(()=>{},20000);`,`console.log('raw error sk-private');`,`console.log('x'.repeat(70000));`]) {
    const run=await fixture(t,source,100);
    await assert.rejects(run({text:'x',history:[]},{}),error=>!error.message.includes('private'));
  }
});
test('valid decoded answers are accepted even with JSON escaping overhead',async t=>{
  const run=await fixture(t,`console.log(JSON.stringify({answer:'x'+'\\n'.repeat(8191)}));`);
  assert.equal(Buffer.byteLength(await run({text:'x',history:[]},{})),8192);
});
test('cancellation cleans up descendants even if direct worker exits first',async t=>{
  const parent=await realpath('artifacts/hermes-integration/adapter-tests');
  const workspace=await mkdtemp(join(parent,'group-')); t.after(()=>rm(workspace,{recursive:true,force:true}));
  const pidfile=join(workspace,'child.pid'), worker=join(workspace,'fixture.cjs');
  await writeFile(worker,`const cp=require('child_process').spawn(process.execPath,['-e',"process.on('SIGTERM',()=>{});setInterval(()=>{},1000)"],{stdio:'ignore'});require('fs').writeFileSync(${JSON.stringify(pidfile)},String(cp.pid));setInterval(()=>{},1000);`);
  const run=await createHermesRunner({python:process.execPath,workspace,worker});
  const controller=new AbortController(); const task=run({text:'x',history:[]},{signal:controller.signal});
  let pid;
  try {
    for(let n=0;n<100;n++) {try {pid=Number(await readFile(pidfile,'utf8'));break;}catch{} await new Promise(r=>setTimeout(r,10));}
    assert.ok(pid); await new Promise(r=>setTimeout(r,100)); controller.abort();
    await assert.rejects(task,/cancelled/);
    let alive=true; try {process.kill(pid,0);}catch {alive=false;}
    assert.equal(alive,false,'descendant still running after cancellation acknowledgement');
  } finally { if(pid) {try {process.kill(pid,'SIGKILL');}catch{}} controller.abort(); await task.catch(()=>{}); }
});
test('macOS sandbox prevents worker writes outside its private workspace',async t=>{
  const parent=await realpath('artifacts/hermes-integration/adapter-tests');
  const forbidden=join(parent,'must-not-exist');
  const run=await fixture(t,`let answer='unsafe';try{require('fs').writeFileSync(${JSON.stringify(forbidden)},'bad');}catch(error){if(error.code==='EPERM'||error.code==='EACCES')answer='blocked';}console.log(JSON.stringify({answer}));`);
  assert.equal(await run({text:'x',history:[]},{}),'blocked');
});
