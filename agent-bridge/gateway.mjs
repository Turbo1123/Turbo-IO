import {spawn as nodeSpawn} from 'node:child_process';
import {stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

export class GatewayError extends Error {
  constructor(code) { super(code); this.name='GatewayError'; this.code=code; }
}
const fail=code=>new GatewayError(code);
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const record=value=>value&&typeof value==='object'&&!Array.isArray(value);
const identifier=value=>typeof value==='string'&&/^[\w.:-]{1,256}$/.test(value);
const textLimit=(value,bytes)=>{
  if(typeof value!=='string')return '';
  if(Buffer.byteLength(value)<=bytes)return value;
  return new TextDecoder().decode(Buffer.from(value).subarray(0,bytes)).replace(/\uFFFD$/,'');
};

/** A persistent, private JSON-lines connection to the official Hermes gateway.
 * HTTP/voice detach does not close this process. Only the host calls close().
 * rpcTimeoutMs bounds acknowledgments, never a running computer task.
 */
export async function createHermesGateway({
  python,cwd,onEvent=()=>{},onExit=()=>{},
  command,spawn=nodeSpawn,rpcTimeoutMs=30000,readyTimeoutMs=60000,pollMs=500,
  maxLineBytes=2*1024*1024,maxPendingBytes=4*1024*1024,
}={}) {
  if(typeof python!=='string'||!python||typeof cwd!=='string'||!(await stat(cwd)).isDirectory())throw fail('hermes_invalid_runtime');
  const launch=command||[python,'-B',fileURLToPath(new URL('./hermes_gateway.py',import.meta.url))];
  if(!Array.isArray(launch)||!launch.length||launch.some(part=>typeof part!=='string'))throw fail('hermes_invalid_runtime');
  const sessions=new Map(), pending=new Map();
  let child,starting,resolveReady,rejectReady,ready=false,closed=false,exited=false;
  let counter=0,buffer=Buffer.alloc(0),exitReason,killTimer,startTimer,closePromise,resolveClose;
  const notify=event=>{try {Promise.resolve(onEvent(event)).catch(()=>{});}catch{}};
  const requireSession=sessionId=>{const session=sessions.get(sessionId);if(!session)throw fail('hermes_unknown_session');return session;};
  function expired(session,id) {
    const index=session.prompts.findIndex(prompt=>prompt.id===id);
    if(index<0)return;
    const wasHead=index===0;session.prompts.splice(index,1);
    notify({sessionId:session.id,type:'promptExpired',id});
    if(wasHead)showPrompt(session);
  }
  function showPrompt(session) {
    const prompt=session.prompts[0];
    if(prompt&&!prompt.shown){prompt.shown=true;notify({sessionId:session.id,type:'prompt',prompt:{id:prompt.id,kind:prompt.kind,title:prompt.title,options:prompt.options}});}
  }
  function expireAll(session) {
    const prompts=session.prompts.splice(0);
    for(const prompt of prompts)notify({sessionId:session.id,type:'promptExpired',id:prompt.id});
  }
  function markFailure(session,reason='hermes_task_failed') {
    if(session.failureSent)return;
    session.failureSent=true;session.terminal=true;
    notify({sessionId:session.id,type:'failed',reason});
  }
  function finishExit(code,signal) {
    if(exited)return;
    exited=true;ready=false;clearTimeout(startTimer);clearTimeout(killTimer);
    const reason=exitReason||(closed?'hermes_gateway_closed':'hermes_gateway_exited');
    rejectReady?.(fail(reason));
    for(const item of pending.values()){clearTimeout(item.timer);item.reject(fail(reason));}pending.clear();
    for(const session of sessions.values()) {
      clearTimeout(session.pollTimer);expireAll(session);
      // A dead transport cannot certify what detached computer processes did.
      // Do not synthesize idle or successful completion on process exit.
      if(session.active&&!closed)markFailure(session,reason);
    }
    try {Promise.resolve(onExit({code:typeof code==='number'?code:null,signal:signal||null,expected:closed,reason})).catch(()=>{});}catch{}
    resolveClose?.();
  }
  function stop(reason) {
    if(exited)return;
    exitReason=exitReason||reason;
    if(!child){finishExit(null,null);return;}
    child.kill('SIGTERM');
    killTimer=setTimeout(()=>{if(!exited)child.kill('SIGKILL');},1500);
    killTimer.unref?.();
  }
  function rpc(method,params={}) {
    if(!ready||exited||closed)return Promise.reject(fail('hermes_gateway_unavailable'));
    if(pending.size>=64)return Promise.reject(fail('hermes_rpc_busy'));
    const id=++counter, line=JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n';
    if(Buffer.byteLength(line)>maxLineBytes||child.stdin.writableLength+Buffer.byteLength(line)>maxPendingBytes)return Promise.reject(fail('hermes_input_limit'));
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{pending.delete(id);reject(fail('hermes_rpc_timeout'));},rpcTimeoutMs);
      pending.set(id,{resolve,reject,timer});
      child.stdin.write(line,error=>{if(error){const item=pending.get(id);if(item){pending.delete(id);clearTimeout(timer);reject(fail('hermes_input_failed'));}stop('hermes_input_failed');}});
    });
  }
  function receive(message) {
    if(!record(message)||message.jsonrpc!=='2.0')return;
    if(Object.hasOwn(message,'id')) {
      const item=pending.get(message.id);if(!item)return;
      pending.delete(message.id);clearTimeout(item.timer);
      if(message.error)item.reject(fail('hermes_rpc_failed'));
      else if(record(message.result))item.resolve(message.result);
      else item.reject(fail('hermes_protocol_invalid'));
      return;
    }
    if(message.method!=='event'||!record(message.params))return;
    const {type,session_id:sessionId,payload:rawPayload}=message.params;
    if(type==='gateway.ready'&&!ready){ready=true;clearTimeout(startTimer);resolveReady?.();return;}
    const session=sessions.get(sessionId),payload=record(rawPayload)?rawPayload:{};
    if(!session)return; // Includes all foreign-session and startup metadata.
    if(type==='error') {
      if(session.active)markFailure(session);
      else session.initFailed=true;
      return;
    }
    if(type==='session.info')return; // Poll io.status for real thread liveness.
    if(!session.active)return;
    if(type==='message.start'){session.terminal=false;return;}
    if(type==='message.delta') {
      const text=textLimit(payload.text,Math.min(16384,Math.max(0,1048576-session.emittedBytes)));
      session.emittedBytes+=Buffer.byteLength(text);
      if(text)notify({sessionId,type:'text',text});
    } else if(type==='message.complete') {
      session.terminal=true;
      if(payload.status==='error')markFailure(session);
      notify({sessionId,type:'done',text:payload.status==='error'?'':textLimit(payload.text,131072),...(payload.status==='interrupted'?{interrupted:true}:{}),...(payload.status==='error'?{failed:true}:{})});
    } else if(type==='tool.start'||type==='tool.generating'||type==='tool.complete') {
      // Only a validated tool name, never arguments, previews or tool output.
      const name=typeof payload.name==='string'&&/^[a-zA-Z0-9_.:-]{1,80}$/.test(payload.name)?payload.name:'';
      notify({sessionId,type:'progress',text:name?`Hermes is using ${name}.`:'Hermes is working.'});
    } else if(type==='status.update') {
      const messages={compacting:'Hermes is summarizing the conversation.',compressing:'Hermes is summarizing the conversation.',tool:'Hermes is working.',lifecycle:'Hermes is working.',status:'Hermes is working.'};
      if(messages[payload.kind])notify({sessionId,type:'progress',text:messages[payload.kind]});
    } else if(/^(approval|clarify|sudo|secret|auth|oauth|terminal\.read)\.request$/.test(type)) {
      const id=payload.request_id;
      if(!identifier(id)||session.prompts.some(prompt=>prompt.id===id))return;
      if(session.prompts.length>=32){markFailure(session,'hermes_prompt_limit');void interrupt(sessionId).catch(()=>{});return;}
      const secretQuestion=type==='clarify.request'&&/(password|api[ _-]?key|credential|verification code|one.time (?:code|password)|密码|密钥|验证码)/i.test(String(payload.question||''));
      const kind=type==='approval.request'?'approval':type==='clarify.request'&&!secretQuestion?'clarify':'localAction';
      const title=kind==='localAction'?'请在电脑上完成权限或登录操作；这里不接收密码、验证码或密钥。':kind==='approval'?textLimit([payload.description,payload.command].filter(value=>typeof value==='string'&&value.trim()).join('\n'),4096)||'Approve this computer action?':textLimit(payload.question,4096)||'Hermes needs clarification.';
      const options=kind==='approval'?['once','deny']:kind==='clarify'&&Array.isArray(payload.choices)?payload.choices.filter(value=>typeof value==='string').slice(0,12).map(value=>textLimit(value,512)):[];
      session.prompts.push({id,kind,title,options,shown:false});showPrompt(session);
    } else if(/\.(expire|expired)$/.test(type)&&identifier(payload.request_id))expired(session,payload.request_id);
  }
  function consume(chunk) {
    if(exited||exitReason)return;
    buffer=Buffer.concat([buffer,chunk]);
    let newline;
    while((newline=buffer.indexOf(10))!==-1) {
      if(newline>maxLineBytes){buffer=Buffer.alloc(0);stop('hermes_output_limit');return;}
      const line=buffer.subarray(0,newline);buffer=buffer.subarray(newline+1);
      if(!line.length)continue;
      try{receive(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(line)));}catch{/* Discard raw logs and malformed frames without echoing them. */}
    }
    if(buffer.length>maxLineBytes){buffer=Buffer.alloc(0);stop('hermes_output_limit');}
  }
  function start() {
    if(starting)return starting;
    if(closed||exited)return Promise.reject(fail('hermes_gateway_unavailable'));
    starting=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});
    const env={};
    for(const name of ['HOME','USER','PATH','LANG','LC_ALL','HERMES_HOME','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY'])if(process.env[name])env[name]=process.env[name];
    Object.assign(env,{PYTHONUNBUFFERED:'1',PYTHONDONTWRITEBYTECODE:'1'});
    try{
      child=spawn(launch[0],launch.slice(1),{cwd,env,stdio:['pipe','pipe','ignore']});
      child.stdout.on('data',consume);
      child.stdin.on('error',()=>stop('hermes_input_failed'));
      child.on('error',()=>{exitReason='hermes_launch_failed';finishExit(null,null);});
      child.on('close',finishExit);
      startTimer=setTimeout(()=>{rejectReady(fail('hermes_gateway_timeout'));stop('hermes_gateway_timeout');},readyTimeoutMs);
    }catch{exitReason='hermes_launch_failed';finishExit(null,null);}
    return starting;
  }
  function addSession(result) {
    const sessionId=result.session_id,storedSessionId=result.stored_session_id||result.session_key||result.resumed;
    if(!identifier(sessionId)||!identifier(storedSessionId))throw fail('hermes_protocol_invalid');
    if(!sessions.has(sessionId))sessions.set(sessionId,{id:sessionId,storedSessionId,prompts:[],active:false,terminal:false,emittedBytes:0,initFailed:false,failureSent:false,submitting:false});
    return {sessionId,storedSessionId};
  }
  async function createSession() {await start();return addSession(await rpc('session.create',{source:'norman-io',cwd,close_on_disconnect:false}));}
  async function resumeSession(storedSessionId) {
    if(!identifier(storedSessionId))throw fail('hermes_invalid_session');
    await start();return addSession(await rpc('session.resume',{session_id:storedSessionId,source:'norman-io',close_on_disconnect:false}));
  }
  async function status(session) {
    const result=await rpc('io.status',{session_id:session.id});
    if(typeof result.ready!=='boolean'||typeof result.failed!=='boolean'||typeof result.running!=='boolean'||typeof result.run_thread_alive!=='boolean'||!Array.isArray(result.pending_prompt_ids))throw fail('hermes_protocol_invalid');
    if(identifier(result.stored_session_id))session.storedSessionId=result.stored_session_id;
    return result;
  }
  async function readySession(sessionId) {
    const session=requireSession(sessionId),until=Date.now()+readyTimeoutMs;
    do{
      const state=await status(session);
      if(state.failed||session.initFailed)throw fail('hermes_initialization_failed');
      if(state.ready)return {ready:true};
      await sleep(pollMs);
    }while(Date.now()<until);
    throw fail('hermes_initialization_timeout');
  }
  function schedulePoll(session) {
    if(session.pollTimer||session.polling||!session.active||closed||exited)return;
    session.pollTimer=setTimeout(async()=>{
      session.pollTimer=null;session.polling=true;
      try{
        const observedPromptIds=new Set(session.prompts.map(prompt=>prompt.id));
        const state=await status(session);
        for(const prompt of [...session.prompts])if(observedPromptIds.has(prompt.id)&&!state.pending_prompt_ids.includes(prompt.id))expired(session,prompt.id);
        if(state.failed)markFailure(session,'hermes_initialization_failed');
        // A readiness/admission continuation must settle before releasing the
        // session. Otherwise a later submit could overwrite its stop latch.
        if(!state.running&&!state.run_thread_alive&&!session.submitting) {
          if(!session.terminal) {
            if(session.interrupted)notify({sessionId:session.id,type:'done',text:'',interrupted:true});
            else markFailure(session,'hermes_completion_unknown');
          }
          session.active=false;expireAll(session);notify({sessionId:session.id,type:'idle'});
        }
      }catch(error){
        // An unavailable status RPC is uncertainty about liveness, not proof
        // the computer action failed or stopped. Keep polling and busy.
        if(!closed&&!exited&&!session.pollFailureSent){session.pollFailureSent=true;notify({sessionId:session.id,type:'progress',text:'正在重新确认 Hermes 的执行状态。'});}
      }finally{session.polling=false;schedulePoll(session);}
    },pollMs);
  }
  async function submit(sessionId,text) {
    const session=requireSession(sessionId);
    if(typeof text!=='string'||!text.trim()||Buffer.byteLength(text)>65536)throw fail('hermes_invalid_input');
    if(session.active||session.submitting)throw fail('hermes_session_busy');
    session.submitting=true;
    session.active=true;session.terminal=false;session.failureSent=false;session.pollFailureSent=false;session.interrupted=false;session.emittedBytes=0;
    let submissionSent=false;
    try{
      await readySession(sessionId);
      // interrupt() can run while readySession awaits initialization. Preserve
      // that turn's cancellation latch and never admit the deferred prompt.
      if(session.interrupted){schedulePoll(session);return {accepted:false,interrupted:true};}
      submissionSent=true;
      const result=await rpc('prompt.submit',{session_id:sessionId,text});
      if(result.status!=='streaming')throw fail('hermes_submission_unknown');
      schedulePoll(session);return {accepted:true};
    }catch(error){
      if(session.interrupted&&!submissionSent){schedulePoll(session);return {accepted:false,interrupted:true};}
      // A rejected RPC never ran. Timeout/transport errors are ambiguous and
      // keep the session busy until status proves the thread stopped.
      if(error.code==='hermes_rpc_failed')session.active=false;
      else if(session.active)schedulePoll(session);
      throw error;
    }finally{session.submitting=false;}
  }
  async function interrupt(sessionId) {
    const session=requireSession(sessionId);session.interrupted=true;
    const result=await rpc('session.interrupt',{session_id:sessionId});
    if(result.status!=='interrupted')throw fail('hermes_interrupt_unknown');
    expireAll(session);schedulePoll(session);return {accepted:true};
  }
  async function respond(sessionId,prompt,decision) {
    const session=requireSession(sessionId),current=session.prompts[0];
    if(!record(prompt)||!current||current.id!==prompt.id||current.responding)throw fail('hermes_stale_prompt');
    if(current.kind==='localAction')throw fail('hermes_local_action_required');
    let method,params={session_id:sessionId,request_id:current.id};
    if(current.kind==='approval') {
      if(!record(decision)||!['once','deny'].includes(decision.choice))throw fail('hermes_invalid_decision');
      method='approval.respond';params.choice=decision.choice;
    }else{
      if(!record(decision)||typeof decision.text!=='string'||!decision.text.trim()||Buffer.byteLength(decision.text)>8192)throw fail('hermes_invalid_decision');
      method='clarify.respond';params.answer=decision.text;
    }
    current.responding=true;
    try{
      const result=await rpc(method,params);
      if((method==='approval.respond'&&result.resolved!==1)||(method==='clarify.respond'&&result.status!=='ok'))throw fail('hermes_stale_prompt');
      // Removing by ID handles an expiry event arriving before its ACK.
      const index=session.prompts.findIndex(item=>item.id===current.id);if(index>=0)session.prompts.splice(index,1);showPrompt(session);
      return {accepted:true};
    }catch(error){expired(session,current.id);throw error;}
  }
  async function history(sessionId) {
    requireSession(sessionId);const result=await rpc('session.history',{session_id:sessionId});
    if(!Array.isArray(result.messages))throw fail('hermes_protocol_invalid');
    const messages=[];let total=0;
    for(const row of result.messages.slice(-500)) {
      if(!record(row)||!['user','assistant'].includes(row.role)||typeof row.text!=='string'||!row.text.trim())continue;
      // Truncated records must not accidentally confirm the task's final answer.
      const truncated=Buffer.byteLength(row.text)>65536,text=textLimit(row.text,65536);
      total+=Buffer.byteLength(text);
      messages.push({role:row.role,text,...(row.role==='assistant'?{toolCalls:truncated||row.tool_calls!==false}:{})});
      while(total>524288&&messages.length){total-=Buffer.byteLength(messages[0].text);messages.shift();}
    }
    return messages;
  }
  async function close() {
    if(closePromise)return closePromise;
    if(exited){closed=true;return;}
    closed=true;
    for(const session of sessions.values())clearTimeout(session.pollTimer);
    if(!child){exited=true;rejectReady?.(fail('hermes_gateway_closed'));return;}
    closePromise=new Promise(resolve=>{resolveClose=resolve;});
    stop('hermes_gateway_closed');return closePromise;
  }
  return {start,createSession,resumeSession,readySession,submit,interrupt,respond,history,close};
}
