import {createHash,randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import {open,rename,unlink} from 'node:fs/promises';
import {dirname} from 'node:path';
import {BridgeError} from './bridge.mjs';

export const validID=value=>typeof value==='string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
const final=status=>['completed','failed','cancelled'].includes(status);
const bounded=(value,max)=>typeof value==='string' && Buffer.byteLength(value)<=max;
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const exact=(value,keys)=>value && typeof value==='object' && !Array.isArray(value) && Object.keys(value).sort().join(',')===keys.split(',').sort().join(',');
const labels={running:'Hermes 正在执行',waiting:'Hermes 等待你回应',stopping:'正在停止，等待电脑确认',completed:'Hermes 任务已完成',failed:'Hermes 任务未完成',cancelled:'Hermes 本轮已停止',unknown:'任务结果待核对；没有自动重发'};
const snapshot=task=>structuredClone(Object.fromEntries(['requestId','conversationId','status','answer','summary','revision','prompt'].map(key=>[key,task[key]])));
const marker=id=>`[Norman IO request: ${id}]`;
const MAX_LEDGER_BYTES=16*1024*1024; // Covers 512 tasks × 128 bounded decisions.

/** Durable IDs and session ownership; content lives in Hermes, not this ledger. */
export class TaskService {
  constructor({gateway,ledger}) {
    this.gateway=gateway;this.ledger=ledger;this.tasks=new Map();this.sessions=new Map();this.lock=Promise.resolve();this.exited=false;
  }
  static async open(options) {
    const service=new TaskService(options);
    try {
      const file=await open(options.ledger,constants.O_RDONLY|constants.O_NOFOLLOW);
      let data;
      try {
        const stat=await file.stat();
        if(!stat.isFile() || stat.mode&0o077 || stat.uid!==process.getuid() || stat.size>MAX_LEDGER_BYTES) throw new BridgeError('invalid_task_ledger',500);
        data=JSON.parse(await file.readFile('utf8'));
      } finally {await file.close();}
      if(data.version!==2 || !Array.isArray(data.tasks) || data.tasks.length>512 || !Array.isArray(data.sessions) || data.sessions.length>16) throw new Error('invalid');
      for(const item of data.sessions) {
        if(!validID(item.conversationId) || !bounded(item.storedSessionId,256) || !item.storedSessionId || service.sessions.has(item.conversationId)) throw new Error('invalid');
        service.sessions.set(item.conversationId,{storedSessionId:item.storedSessionId,everSubmitted:item.everSubmitted ?? data.tasks.some(t=>t.conversationId===item.conversationId&&!t.tombstone)});
      }
      for(const item of data.tasks) {
        if(!validID(item.requestId)||!validID(item.conversationId)||!(item.status in labels)||!Number.isSafeInteger(item.revision)||item.revision<0||service.tasks.has(item.requestId)||!Array.isArray(item.decisions)||item.decisions.length>128||item.decisions.some(d=>!validID(d.id)||!bounded(d.digest,64))) throw new Error('invalid');
        const task={...item,priorStatus:item.status==='unknown'?(item.priorStatus??'unknown'):item.status,recovered:true,answer:'',prompt:null,prompts:[],status:final(item.status)?item.status:'unknown',revision:item.revision+1};
        task.summary=labels[task.status];service.tasks.set(task.requestId,task);
      }
    } catch(error) {if(error.code!=='ENOENT') throw new BridgeError('invalid_task_ledger',500);}
    return service;
  }
  serialize(action) {const result=this.lock.then(action);this.lock=result.catch(()=>{});return result;}
  async persist() {
    const data={version:2,sessions:[...this.sessions].filter(([,s])=>s.storedSessionId).map(([conversationId,s])=>({conversationId,storedSessionId:s.storedSessionId,everSubmitted:s.everSubmitted===true})),
      tasks:[...this.tasks.values()].map(t=>({requestId:t.requestId,conversationId:t.conversationId,digest:t.digest,status:t.status,revision:t.revision,decisions:t.decisions,tombstone:t.tombstone===true,acknowledged:t.acknowledged===true,priorStatus:t.priorStatus}))};
    const temp=this.ledger+'.'+randomUUID()+'.new';
    const encoded=JSON.stringify(data);
    if(Buffer.byteLength(encoded)>MAX_LEDGER_BYTES)throw new BridgeError('task_ledger_full',429);
    try {
      const file=await open(temp,'wx',0o600);
      try {await file.writeFile(encoded);await file.sync();} finally {await file.close();}
      await rename(temp,this.ledger);
      const directory=await open(dirname(this.ledger),'r');try{await directory.sync();}finally{await directory.close();}
    } finally {await unlink(temp).catch(()=>{});}
  }
  change(task,patch) {Object.assign(task,patch);task.revision++;task.summary=patch.summary??labels[task.status];}
  async session(conversationId) {
    let session=this.sessions.get(conversationId);
    if(session?.opening) return session.opening;
    if(session?.sessionId) {await this.gateway.readySession?.(session.sessionId);return session;}
    if(!session) {if(this.sessions.size>=16) throw new BridgeError('session_limit',429);session={everSubmitted:false};this.sessions.set(conversationId,session);}
    session.opening=(async()=>{
      let info;
      if(session.storedSessionId) {
        try {info=await this.gateway.resumeSession(session.storedSessionId);}
        catch(error){if(session.everSubmitted)throw error;info=await this.gateway.createSession();}
      }else info=await this.gateway.createSession();
      if(!bounded(info.sessionId,256)||!info.sessionId||!bounded(info.storedSessionId,256)||!info.storedSessionId)throw new Error('invalid_session');
      Object.assign(session,info);await this.serialize(()=>this.persist());
      await this.gateway.readySession?.(session.sessionId);
      return session;
    })();
    try{return await session.opening;}finally{delete session.opening;}
  }
  async health(conversationId) {
    if(!validID(conversationId))throw new BridgeError('invalid_request');
    if(this.exited||this.stopping)throw new BridgeError('hermes_unavailable',503);
    try {await this.session(conversationId);}catch{throw new BridgeError('hermes_not_ready',503);}
    return {ok:true,agent:'hermes',mode:'tasks',protocolVersion:2,ready:true};
  }
  async submit(input) {
    if(!exact(input,'requestId,conversationId,text')||!validID(input.requestId)||!validID(input.conversationId)||!bounded(input.text,8192)||!input.text.trim())throw new BridgeError('invalid_request');
    return this.serialize(async()=>{
      const hash=digest([input.conversationId,input.text]);
      const old=this.tasks.get(input.requestId);
      if(old) {
        if(old.conversationId!==input.conversationId||(!old.tombstone&&old.digest!==hash))throw new BridgeError('request_conflict',409);
        return snapshot(old);
      }
      if(this.exited||this.stopping)throw new BridgeError('hermes_unavailable',503);
      if([...this.tasks.values()].some(t=>t.status==='unknown'&&!t.acknowledged))throw new BridgeError('reconcile_required',409);
      if([...this.tasks.values()].some(t=>!final(t.status)&&t.status!=='unknown'))throw new BridgeError('busy',409);
      if(this.tasks.size>=512)throw new BridgeError('task_limit',429);
      const task={requestId:input.requestId,conversationId:input.conversationId,digest:hash,status:'running',answer:'',summary:labels.running,revision:0,prompt:null,prompts:[],decisions:[]};
      this.tasks.set(task.requestId,task);
      try{await this.persist();}catch{this.tasks.delete(task.requestId);throw new BridgeError('ledger_failed',503);}
      // Launch outside admission lock. HTTP disconnect never owns this promise.
      setImmediate(()=>this.launch(task,input.text));
      return snapshot(task);
    });
  }
  async launch(task,text) {
    try {
      const session=await this.session(task.conversationId);
      if(this.stopping||task.status==='cancelled')return;
      task.sessionId=session.sessionId;
      if(task.status==='stopping') {await this.serialize(async()=>{this.change(task,{status:'cancelled'});await this.persist();});return;}
      const previouslyUsed=session.everSubmitted;
      await this.serialize(async()=>{session.everSubmitted=true;session.lastAdmission=task.requestId;await this.persist();});
      if(task.status==='stopping') {await this.serialize(async()=>{session.everSubmitted=previouslyUsed;this.change(task,{status:'cancelled'});await this.persist();});return;}
      const admission=await this.gateway.submit(session.sessionId,text+'\n\n'+marker(task.requestId));
      if(admission?.accepted===false&&admission.interrupted===true) {
        await this.serialize(async()=>{if(session.lastAdmission===task.requestId)session.everSubmitted=previouslyUsed;await this.persist();});
      }
    }catch {
      await this.serialize(async()=>{if(!final(task.status)){this.change(task,{status:'unknown',prompt:null});await this.persist();}}).catch(()=>{});
    }
  }
  async get(id) {
    if(!validID(id))throw new BridgeError('invalid_request');
    const task=this.tasks.get(id);if(!task)throw new BridgeError('not_found',404);
    if(task.recovered && (task.priorStatus==='completed'||task.priorStatus==='failed')) {
      // Only durable terminal evidence can promote historical text to a result.
      try {
        const session=await this.session(task.conversationId),history=await this.gateway.history(session.sessionId);
        const start=history.findLastIndex(m=>m.role==='user'&&m.text?.endsWith(marker(id)));
        if(start>=0) {
          const next=history.slice(start+1).findIndex(m=>m.role==='user');
          const turn=history.slice(start+1,next<0?undefined:start+1+next);
          const answer=turn.findLast(m=>m.role==='assistant'&&!m.toolCalls)?.text;
          if(bounded(answer,32768)&&answer.trim())await this.serialize(async()=>{task.recovered=false;this.change(task,{status:task.priorStatus,answer});await this.persist();});
        }
      }catch{/* Unknown remains visible; never rerun to recover a missing answer. */}
    }
    return snapshot(task);
  }
  async handleEvent(event) {
    return this.serialize(async()=>{
      const task=[...this.tasks.values()].find(t=>t.sessionId===event.sessionId&&!final(t.status)&&!t.acknowledged);
      if(!task)return;
      if(event.type==='text'&&bounded(event.text,32768)) {
        const answer=task.answer+event.text;
        if(Buffer.byteLength(answer)<=32768)this.change(task,{answer});
      }else if(event.type==='progress') {
        this.change(task,{summary:bounded(event.text,1024)?event.text:labels[task.status]});
      }else if(event.type==='prompt') {
        const p=event.prompt;
        if(!p||!bounded(p.id,256)||!['approval','clarify','localAction'].includes(p.kind))return;
        if(task.prompts.some(x=>x.upstream.id===p.id))return;
        if(task.prompts.length>=16) {this.change(task,{status:'unknown',prompt:null});await this.persist();return;}
        const value={id:randomUUID(),kind:p.kind,title:bounded(p.title,4096)?p.title:'请在电脑检查此请求',options:Array.isArray(p.options)?p.options.filter(s=>bounded(s,512)).slice(0,12):[]};
        task.prompts.push({view:value,upstream:p});
        this.change(task,{status:task.status==='stopping'?'stopping':'waiting',prompt:task.prompts[0].view});
      }else if(event.type==='promptExpired') {
        task.prompts=task.prompts.filter(p=>p.upstream.id!==event.id);
        this.change(task,{prompt:task.prompts[0]?.view??null,status:task.status==='stopping'?'stopping':task.prompts.length?'waiting':'running'});
      }else if(event.type==='done') {
        task.result={status:event.interrupted?'cancelled':event.failed?'failed':'completed',answer:bounded(event.text,32768)?event.text:task.answer};
      }else if(event.type==='failed') {
        task.result={status:'failed',answer:task.answer};
      }else if(event.type==='idle') {
        if(!task.result)return; // An initial idle/session-info is not completion.
        this.change(task,{status:task.result.status,answer:task.result.answer,prompt:null});task.prompts=[];
      }else return;
      try {await this.persist();}catch {this.change(task,{status:'unknown',summary:'任务登记失败，请在电脑核对'});}
    });
  }
  async stop(id,conversationId) {
    if(!validID(id)||!validID(conversationId))throw new BridgeError('invalid_request');
    let task;
    await this.serialize(async()=>{
      task=this.tasks.get(id);
      if(!task) {
        if(this.tasks.size>=512)throw new BridgeError('task_limit',429);
        task={requestId:id,conversationId,status:'cancelled',answer:'',summary:labels.cancelled,revision:0,prompt:null,prompts:[],decisions:[],tombstone:true};this.tasks.set(id,task);await this.persist();return;
      }
      if(task.conversationId!==conversationId)throw new BridgeError('request_conflict',409);
      if(final(task.status))return;
      if(task.status==='unknown')throw new BridgeError('reconcile_required',409);
      this.change(task,{status:'stopping',prompt:null});task.prompts=[];await this.persist();
    });
    if(task.sessionId&&!final(task.status)) {
      try {await this.gateway.interrupt(task.sessionId);}catch {throw new BridgeError('stop_unconfirmed',503);}
    }
    return snapshot(task);
  }
  async decide(id,input) {
    if(!validID(id)||!input||!validID(input.conversationId)||!validID(input.promptId)||!validID(input.decisionId))throw new BridgeError('invalid_decision');
    const hash=digest(input);let task,pending,duplicate=false;
    await this.serialize(async()=>{
      task=this.tasks.get(id);
      if(!task||task.conversationId!==input.conversationId)throw new BridgeError('request_conflict',409);
      const existing=task.decisions.find(d=>d.id===input.decisionId);
      if(existing){if(existing.digest!==hash)throw new BridgeError('decision_conflict',409);duplicate=true;return;}
      pending=task.prompts[0];
      if(task.status!=='waiting'||pending?.view.id!==input.promptId)throw new BridgeError('stale_prompt',409);
      const base='conversationId,promptId,decisionId,';
      if(pending.view.kind==='approval') {
        if(!exact(input,base+'choice')||!['once','deny'].includes(input.choice))throw new BridgeError('invalid_decision');
      }else if(pending.view.kind==='clarify') {
        if(!exact(input,base+'text')||!bounded(input.text,4096)||!input.text.trim())throw new BridgeError('invalid_decision');
      }else throw new BridgeError('local_action_required',409);
      if(task.decisions.length>=128)throw new BridgeError('decision_limit',429);
      task.decisions.push({id:input.decisionId,digest:hash});
      task.prompts.shift();this.change(task,{status:task.prompts.length?'waiting':'running',prompt:task.prompts[0]?.view??null});
      await this.persist();
    });
    if(!duplicate) {
      try {await this.gateway.respond(task.sessionId,pending.upstream,input.choice?{choice:input.choice}:{text:input.text});}
      catch {throw new BridgeError('decision_unconfirmed',503);}
    }
    return snapshot(task);
  }
  async acknowledge(id,conversationId) {
    return this.serialize(async()=>{
      const task=this.tasks.get(id);
      if(!validID(id)||!validID(conversationId)||!task||task.conversationId!==conversationId)throw new BridgeError('invalid_request');
      // Only a task recovered after process loss can be released. A live,
      // uncertain RPC may still execute and must remain exclusive.
      if(task.status!=='unknown'||!task.recovered)throw new BridgeError('reconcile_required',409);
      task.acknowledged=true;this.change(task,{summary:'已结束本机核对；原操作没有回滚'});await this.persist();return snapshot(task);
    });
  }
  async gatewayExited() {
    this.exited=true;
    return this.serialize(async()=>{for(const task of this.tasks.values())if(!final(task.status)){this.change(task,{status:'unknown',prompt:null});}await this.persist();});
  }
  async shutdown() {this.stopping=true;await this.gateway.close();await this.gatewayExited();}
}
