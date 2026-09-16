import {createHash, timingSafeEqual} from 'node:crypto';
import {lstat, readFile, open, rename} from 'node:fs/promises';
import {dirname} from 'node:path';

export class BridgeError extends Error {
  constructor(code, status=400) { super(code); this.status=status; }
}
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const validID=value=>typeof value==='string' && uuid.test(value);
const terminal=status=>['completed','failed','cancelled'].includes(status);
const summaries={running:'Hermes 正在回答',completed:'Hermes 回答完成',failed:'Hermes 未完成，请检查桥接服务',cancelled:'Hermes 已停止'};
const snapshot=task=>Object.fromEntries(['taskId','requestId','conversationId','agent','status','answer','revision','summary','updatedAt','approval'].map(key=>[key,task[key]]));
function makeTask(requestId,conversationId) {
  return {taskId:requestId,requestId,conversationId,agent:'hermes',status:'running',answer:'',revision:0,summary:summaries.running,updatedAt:new Date().toISOString(),approval:null};
}
function validate(input) {
  if (!input || typeof input!=='object' || Array.isArray(input) ||
      Object.keys(input).sort().join(',')!=='agent,conversationId,mode,requestId,text,workspaceId' ||
      input.agent!=='hermes' || input.workspaceId!=='conversation' || input.mode!=='read-only' ||
      !validID(input.requestId) || !validID(input.conversationId) ||
      typeof input.text!=='string' || !input.text.trim() || Buffer.byteLength(input.text)>8192)
    throw new BridgeError('invalid_request');
}

/// Private in-memory answers and per-conversation context. Only IDs survive restart.
export class TaskBridge {
  constructor({run,ledger}) { this.run=run; this.ledger=ledger; this.tasks=new Map(); this.history=new Map(); this.lock=Promise.resolve(); }
  static async open(options) {
    const bridge=new TaskBridge(options);
    try {
      const stat=await lstat(options.ledger);
      if (!stat.isFile() || (stat.mode & 0o077) || stat.size>65536) throw new BridgeError('invalid_ledger',500);
      const ids=JSON.parse(await readFile(options.ledger,'utf8'));
      if (!Array.isArray(ids) || ids.length>128 || ids.some(id=>!validID(id))) throw new BridgeError('invalid_ledger',500);
      for (const id of ids) { const task=makeTask(id,id); task.recovered=true; bridge.finish(task,'failed'); bridge.tasks.set(id,task); }
    } catch(error) { if(error.code!=='ENOENT') throw error; }
    return bridge;
  }
  serialize(action) { const result=this.lock.then(action); this.lock=result.catch(()=>{}); return result; }
  async reserve(task) {
    if(this.tasks.size>=128) throw new BridgeError('task_limit',429);
    // Reserve on disk BEFORE allowing a process to start. Failed writes fail closed.
    const temp=this.ledger+'.new';
    const file=await open(temp,'wx',0o600);
    try { await file.writeFile(JSON.stringify([...this.tasks.keys(),task.taskId])); await file.sync(); }
    finally { await file.close(); }
    await rename(temp,this.ledger);
    const directory=await open(dirname(this.ledger),'r');
    try { await directory.sync(); } finally { await directory.close(); }
    this.tasks.set(task.taskId,task);
  }
  finish(task,status,answer='') { Object.assign(task,{status,answer,revision:task.revision+1,summary:summaries[status],updatedAt:new Date().toISOString()}); }
  async submit(input) {
    validate(input);
    return this.serialize(async()=>{
      if(this.stopping) throw new BridgeError('shutting_down',503);
      const digest=createHash('sha256').update(JSON.stringify([input.conversationId,input.text])).digest('hex');
      const existing=this.tasks.get(input.requestId);
      if(existing) {
        if(existing.recovered) throw new BridgeError('delivery_unknown',409);
        if(existing.reservedStop) {
          if(existing.conversationId!==input.conversationId) throw new BridgeError('request_conflict',409);
          return snapshot(existing);
        }
        if(existing.digest!==digest) throw new BridgeError('request_conflict',409);
        return snapshot(existing);
      }
      // Bound provider usage across clients and avoid overlapping context commits.
      if([...this.tasks.values()].some(task=>!terminal(task.status) || task.stopUnconfirmed)) throw new BridgeError('busy',409);
      if(!this.history.has(input.conversationId) && this.history.size>=8) throw new BridgeError('conversation_limit',429);
      const task=makeTask(input.requestId,input.conversationId);
      task.digest=digest; task.abort=new AbortController();
      await this.reserve(task);
      if(this.stopping) { this.finish(task,'cancelled'); return snapshot(task); }
      const history=this.history.get(input.conversationId) ?? [];
      this.history.set(input.conversationId,history);
      task.done=(async()=>{
        try {
          const answer=await this.run({text:input.text,history},{signal:task.abort.signal});
          if(task.abort.signal.aborted) { this.finish(task,'cancelled'); return; }
          if(typeof answer!=='string' || !answer.trim() || Buffer.byteLength(answer)>8192) throw new Error('invalid_answer');
          this.history.set(input.conversationId,[...history,{role:'user',content:input.text},{role:'assistant',content:answer}].slice(-6));
          this.finish(task,'completed',answer);
        } catch(error) {
          task.stopUnconfirmed=error instanceof BridgeError && error.message==='hermes_stop_unconfirmed';
          this.finish(task,task.abort.signal.aborted && !task.stopUnconfirmed ? 'cancelled':'failed');
        }
      })();
      return snapshot(task);
    });
  }
  get(id) { if(!validID(id)) throw new BridgeError('invalid_request'); const task=this.tasks.get(id); if(!task) throw new BridgeError('not_found',404); return snapshot(task); }
  async shutdown() {
    this.stopping=true;
    await this.serialize(async()=>{});
    await Promise.all([...this.tasks.values()].filter(task=>!terminal(task.status) || task.stopUnconfirmed).map(task=>this.stop(task.taskId,task.conversationId)));
  }
  async stop(id,conversationId) {
    if(!validID(id) || !validID(conversationId)) throw new BridgeError('invalid_request');
    const task=await this.serialize(async()=>{
      let task=this.tasks.get(id);
      if(!task) { task=makeTask(id,conversationId); task.reservedStop=true; this.finish(task,'cancelled'); await this.reserve(task); }
      if(task.recovered) { task.recovered=false; task.reservedStop=true; task.conversationId=conversationId; this.finish(task,'cancelled'); }
      if(task.conversationId!==conversationId) throw new BridgeError('request_conflict',409);
      if(!terminal(task.status)) task.abort.abort();
      return task;
    });
    // Successful stop means the adapter has acknowledged exit, not merely a sent signal.
    await task.done;
    if(task.stopUnconfirmed) throw new BridgeError('stop_unconfirmed',503);
    return snapshot(task);
  }
}

export function createHandler(bridge,token) {
  if(!/^[A-Za-z0-9_-]{32,256}$/.test(token)) throw new BridgeError('invalid_token');
  const expected=Buffer.from('Bearer '+token);
  return async(req,res)=>{
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    try {
      const actual=Buffer.from(req.headers.authorization ?? '');
      if(actual.length!==expected.length || !timingSafeEqual(actual,expected)) throw new BridgeError('unauthorized',401);
      if(req.headers.origin!==undefined) throw new BridgeError('browser_origin_forbidden',403);
      let result;
      if(req.method==='GET' && req.url==='/v1/health') result={ok:true,agent:'hermes',mode:'conversation-only',protocolVersion:1};
      else if(req.method==='POST' && req.url==='/v1/tasks') {
        result=await bridge.submit(await jsonBody(req));
      } else {
        const match=/^\/v1\/tasks\/([a-f0-9-]{36})(\/stop)?$/.exec(req.url ?? '');
        if(match && req.method==='GET' && !match[2]) result=bridge.get(match[1]);
        else if(match && req.method==='POST' && match[2]) {
          const body=await jsonBody(req);
          if(!body || Object.keys(body).join(',')!=='conversationId') throw new BridgeError('invalid_request');
          result=await bridge.stop(match[1],body.conversationId);
        }
        else throw new BridgeError('not_found',404);
      }
      res.end(JSON.stringify(result));
    } catch(error) { res.statusCode=error instanceof BridgeError ? error.status:500; res.end(JSON.stringify({error:error instanceof BridgeError ? error.message:'bridge_failed'})); }
  };
}

async function jsonBody(req) {
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type'] ?? '')) throw new BridgeError('json_required',415);
  const chunks=[]; let bytes=0;
  for await(const chunk of req) { bytes+=chunk.length; if(bytes>16384) throw new BridgeError('body_too_large',413); chunks.push(chunk); }
  try { return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks))); }
  catch { throw new BridgeError('invalid_json'); }
}
