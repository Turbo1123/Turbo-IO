import {timingSafeEqual} from 'node:crypto';
import {BridgeError} from './bridge.mjs';
import {validID} from './tasks.mjs';

async function body(req) {
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type']??''))throw new BridgeError('json_required',415);
  const parts=[];let size=0;
  for await(const part of req){size+=part.length;if(size>16384)throw new BridgeError('body_too_large',413);parts.push(part);}
  try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(parts)));}catch{throw new BridgeError('invalid_json');}
}
export function createTaskHandler(service,token) {
  if(!/^[A-Za-z0-9_-]{32,256}$/.test(token))throw new BridgeError('invalid_token');
  const expected=Buffer.from('Bearer '+token);
  return async(req,res)=>{
    res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    try {
      const actual=Buffer.from(req.headers.authorization??'');
      if(actual.length!==expected.length||!timingSafeEqual(actual,expected))throw new BridgeError('unauthorized',401);
      if(req.headers.origin!==undefined)throw new BridgeError('browser_origin_forbidden',403);
      if(req.url?.startsWith('/v1/'))throw new BridgeError('task_client_upgrade_required',409);
      let result;
      const health=/^\/v2\/health\?conversationId=([a-f0-9-]+)$/.exec(req.url??'');
      if(req.method==='GET'&&req.url?.startsWith('/v2/health')) {
        if(!health||!validID(health[1]))throw new BridgeError('invalid_request');
        result=await service.health(health[1]);
      }else if(req.method==='POST'&&req.url==='/v2/tasks')result=await service.submit(await body(req));
      else {
        const match=/^\/v2\/tasks\/([a-f0-9-]{36})(?:\/(stop|decision|acknowledge))?$/.exec(req.url??'');
        if(!match||!validID(match[1]))throw new BridgeError('not_found',404);
        if(req.method==='GET'&&!match[2])result=await service.get(match[1]);
        else if(req.method==='POST'&&match[2]) {
          const value=await body(req);
          if(match[2]==='decision')result=await service.decide(match[1],value);
          else {
            if(!value||Object.keys(value).join(',')!=='conversationId'||!validID(value.conversationId))throw new BridgeError('invalid_request');
            result=await service[match[2]](match[1],value.conversationId);
          }
        }else throw new BridgeError('not_found',404);
      }
      res.end(JSON.stringify(result));
    }catch(error){res.statusCode=error instanceof BridgeError?error.status:500;res.end(JSON.stringify({error:error instanceof BridgeError?error.message:'task_bridge_failed'}));}
  };
}
