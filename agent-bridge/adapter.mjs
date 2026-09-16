import {spawn} from 'node:child_process';
import {realpath, lstat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {BridgeError} from './bridge.mjs';

export async function createHermesRunner({python,workspace,worker=fileURLToPath(new URL('./hermes_worker.py',import.meta.url)),timeoutMs=30000}) {
  if(process.platform!=='darwin') throw new BridgeError('macos_sandbox_required');
  const executable=await realpath(python), directory=await realpath(workspace), script=await realpath(worker);
  if(!(await lstat(directory)).isDirectory()) throw new BridgeError('invalid_workspace');
  const quote=value=>'"'+value.replaceAll('\\','\\\\').replaceAll('"','\\"')+'"';
  const policy=`(version 1) (allow default) (deny file-write*) (allow file-write* (subpath ${quote(directory)}) (literal "/dev/null")) (deny process-exec) (allow process-exec (literal ${quote(executable)}))`;
  return (input,{signal}={})=>new Promise((resolve,reject)=>{
    if(signal?.aborted) { reject(new BridgeError('cancelled')); return; }
    // Start with a small environment. Hermes loads its own provider credentials;
    // the bridge's bearer and question never enter argv or child environment.
    const env={};
    for(const key of ['HOME','USER','PATH','LANG','LC_ALL','HERMES_HOME','HTTPS_PROXY','HTTP_PROXY','ALL_PROXY','NO_PROXY'])
      if(process.env[key]) env[key]=process.env[key];
    Object.assign(env,{PYTHONDONTWRITEBYTECODE:'1',PYTHONUNBUFFERED:'1',HERMES_SAFE_MODE:'1',TMPDIR:directory});
    const child=spawn('/usr/bin/sandbox-exec',['-p',policy,python,script],{cwd:directory,env,detached:true,stdio:['pipe','pipe','ignore']});
    let output=Buffer.alloc(0), failure, killTimer;
    function groupAlive() {
      if(!child.pid) return false;
      try { process.kill(-child.pid,0); return true; }
      catch(error) { return error.code!=='ESRCH'; }
    }
    function kill(reason) {
      if(failure) return;
      failure=reason;
      try { process.kill(-child.pid,'SIGTERM'); } catch {}
      killTimer=setTimeout(()=>{try { process.kill(-child.pid,'SIGKILL'); } catch {}},500);
    }
    const cancelled=()=>kill('cancelled');
    signal?.addEventListener('abort',cancelled,{once:true});
    const deadline=setTimeout(()=>kill('hermes_timeout'),timeoutMs);
    child.stdout.on('data',chunk=>{
      if(output.length+chunk.length>65536) { kill('hermes_output_limit'); return; }
      output=Buffer.concat([output,chunk]);
    });
    child.stdin.on('error',()=>kill('hermes_input_failed'));
    child.on('error',()=>{failure='hermes_launch_failed';});
    child.on('close',async code=>{
      clearTimeout(deadline); signal?.removeEventListener('abort',cancelled);
      // The process leader may exit before descendants that ignore SIGTERM.
      // Do not acknowledge completion/cancellation until the whole group exits.
      if(groupAlive()) {
        try { process.kill(-child.pid,'SIGKILL'); } catch {}
        const until=Date.now()+2000;
        while(groupAlive() && Date.now()<until) await new Promise(ok=>setTimeout(ok,20));
        if(groupAlive()) failure='hermes_stop_unconfirmed';
      }
      clearTimeout(killTimer);
      if(failure) { reject(new BridgeError(failure)); return; }
      try {
        const result=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(output));
        if(code!==0) {
          const allowed=new Set(['hermes_input_failed','hermes_runtime_failed','hermes_initialization_failed','hermes_conversation_failed']);
          throw new BridgeError(allowed.has(result.error)?result.error:'hermes_failed');
        }
        if(Object.keys(result).join(',')!=='answer' || typeof result.answer!=='string' || !result.answer.trim() || Buffer.byteLength(result.answer)>8192) throw new Error('invalid');
        resolve(result.answer);
      } catch(error) { reject(error instanceof BridgeError ? error:new BridgeError('hermes_output_invalid')); }
    });
    child.stdin.end(JSON.stringify(input));
  });
}
