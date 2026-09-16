import {randomBytes} from 'node:crypto';
import {createServer} from 'node:http';
import {constants} from 'node:fs';
import {mkdir,lstat,open,unlink} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';
import {TaskBridge,createHandler,BridgeError} from './bridge.mjs';
import {createHermesRunner} from './adapter.mjs';

async function privateDirectory(dir) {
  const stat=await lstat(dir);
  if(!stat.isDirectory() || (stat.mode & 0o077) || stat.uid!==process.getuid()) throw new BridgeError('private_directory_required');
}
export async function initializeState(dir) {
  await mkdir(dir,{recursive:true,mode:0o700}); await privateDirectory(dir);
  const file=await open(join(dir,'bridge.token'),'wx',0o600);
  try { await file.writeFile(randomBytes(48).toString('base64url')+'\n'); await file.sync(); }
  finally { await file.close(); }
  await mkdir(join(dir,'worker'),{mode:0o700});
}
export async function loadToken(dir) {
  await privateDirectory(dir);
  const file=await open(join(dir,'bridge.token'),constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat=await file.stat();
    if(!stat.isFile() || (stat.mode & 0o077) || stat.uid!==process.getuid() || stat.size>1024) throw new BridgeError('private_token_required');
    const token=(await file.readFile('utf8')).trim();
    if(!/^[A-Za-z0-9_-]{32,256}$/.test(token)) throw new BridgeError('private_token_required');
    return token;
  } finally { await file.close(); }
}
async function main() {
  process.umask(0o077);
  const {values}=parseArgs({options:{init:{type:'boolean'},tasks:{type:'boolean'},python:{type:'string'},'state-dir':{type:'string'},port:{type:'string'},workspace:{type:'string'}}});
  const state=resolve(values['state-dir'] ?? '.private/agent-bridge');
  if(values.init) { await initializeState(state); console.log('Private bridge state created. Token is stored in bridge.token; it is never printed.'); return; }
  const port=Number(values.port ?? 8788);
  if(!Number.isInteger(port) || port<1024 || port>65535 || !values.python) throw new BridgeError('python_and_valid_port_required');
  const token=await loadToken(state);
  const workspace=join(state,'worker'); await privateDirectory(workspace);
  const run=values.tasks ? null : await createHermesRunner({python:values.python,workspace});
  // One bridge per ledger. A stale lock requires explicit operator inspection,
  // preventing a restart from racing an orphaned worker and replaying work.
  const lockPath=join(state,'running.lock');
  const lock=await open(lockPath,'wx',0o600);
  await lock.writeFile(String(process.pid)+'\n'); await lock.close();
  let server,bridge,gateway;
  try {
    if(values.tasks) {
      const {createHermesGateway}=await import('./gateway.mjs');
      const {TaskService}=await import('./tasks.mjs');
      const {createTaskHandler}=await import('./task-http.mjs');
      gateway=await createHermesGateway({python:values.python,cwd:resolve(values.workspace??'.'),
        onEvent:event=>bridge?.handleEvent(event).catch(()=>{}),
        onExit:()=>bridge?.gatewayExited().catch(()=>{})});
      bridge=await TaskService.open({gateway,ledger:join(state,'task-ledger-v2.json')});
      await gateway.start();
      server=createServer(createTaskHandler(bridge,token));
    }else {
      bridge=await TaskBridge.open({run,ledger:join(state,'task-ledger.json')});
      server=createServer(createHandler(bridge,token));
    }
    server.requestTimeout=35000; server.headersTimeout=10000;
    await new Promise((ok,fail)=>{server.once('error',fail);server.listen(port,'127.0.0.1',ok);});
  } catch(error) { await gateway?.close().catch(()=>{}); await unlink(lockPath); throw error; }
  let stopping=false;
  const shutdown=async()=>{
    if(stopping) return; stopping=true;
    const drained=bridge.shutdown();
    server.close();
    await drained;
    server.closeAllConnections(); await unlink(lockPath); process.exit(0);
  };
  process.on('SIGTERM',shutdown); process.on('SIGINT',shutdown);
  console.log(`Norman Hermes bridge listening on 127.0.0.1:${port}; ${values.tasks?'task mode v2':'conversation only'}; use Tailscale Serve for HTTPS.`);
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error=>{console.error(error instanceof BridgeError ? error.message:'bridge_start_failed');process.exitCode=1;});
}
