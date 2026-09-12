// Loopback-only reference host. A trusted HTTPS reverse proxy is a separate step.
import fs from 'node:fs';
import path from 'node:path';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:http';
import {createKnowledgeGateway} from './turbo-knowledge.mjs';
import {readTodoPhoneToken} from './token.mjs';
const [action,file]=process.argv.slice(2);
try{
  if(!['--init','--config'].includes(action)||!file||!path.isAbsolute(file)||process.argv.length!==4)throw Error('Usage: node server.mjs --init /absolute/new-private-directory OR --config /absolute/private-directory/config.json');
  if(action==='--init'){
    if(fs.existsSync(file))throw Error('Initialization needs a new directory. Existing data was not changed.');
    fs.mkdirSync(file,{mode:0o700});const roots={};for(const key of ['wechat','projects','learning']){roots[key]=path.join(file,'sources',key);fs.mkdirSync(roots[key],{recursive:true,mode:0o700});}
    const tokenFile=path.join(file,'knowledge-token');fs.writeFileSync(tokenFile,randomBytes(32).toString('base64url'),{flag:'wx',mode:0o600});
    fs.mkdirSync(path.join(file,'workspace'),{mode:0o700});
    const config={port:4175,tokenFile,roots,cwd:path.join(file,'workspace'),directory:path.join(file,'queries'),command:'/Applications/ChatGPT.app/Contents/Resources/codex'};
    fs.writeFileSync(path.join(file,'config.json'),JSON.stringify(config,null,2)+'\n',{flag:'wx',mode:0o600});console.log('Created private configuration and token; no token is printed. Sources are empty. Server has not been started.');
  }else{
    const stat=fs.lstatSync(file);if(!stat.isFile()||stat.isSymbolicLink()||stat.size>16384||(stat.mode&0o077))throw Error('Use a private regular config file (mode 0600).');
    const c=JSON.parse(fs.readFileSync(file,'utf8'));
    if(!Number.isInteger(c.port)||c.port<1024||c.port>65535||!c.roots||['wechat','projects','learning'].some(k=>!path.isAbsolute(c.roots[k]||''))||['tokenFile','cwd','directory','command'].some(k=>!path.isAbsolute(c[k]||'')))throw Error('Invalid explicit paths or port.');
    await readTodoPhoneToken(c.tokenFile);
    const handler=createKnowledgeGateway(c);
    const server=createServer(async(req,res)=>{try{if(!await handler(req,res)){res.writeHead(404);res.end();}}catch{if(!res.headersSent)res.writeHead(500);res.end();}});
    server.requestTimeout=15000;server.headersTimeout=10000;server.on('error',()=>{console.error('Server unavailable; check configured port.');process.exitCode=1;});
    server.listen(c.port,'127.0.0.1',()=>console.log(`Knowledge reference host listening on loopback port ${c.port}; authenticated routes only. No public tunnel created.`));
    for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
  }
}catch(e){console.error(/^[A-Za-z0-9 ():.\/-]+$/.test(e.message)?e.message:'Configuration failed; private contents are not printed.');process.exitCode=1;}
