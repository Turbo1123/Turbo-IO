import http from 'node:http';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const root = new URL('./public/', import.meta.url);
export const origin = 'http://127.0.0.1:8790';
export function validToken(value) { return typeof value === 'string' && /^[a-f0-9]{32}$/i.test(value); }
export function validSnapshot(s) {
  return s && s.version === 1 && typeof s.connected === 'boolean' && typeof s.includesText === 'boolean'
    && typeof s.session === 'string' && s.session.length <= 64 && Number.isFinite(s.sampledAt)
    && typeof s.phase === 'string' && s.phase.length <= 100 && s.page && !Array.isArray(s.page)
    && Array.isArray(s.events) && s.events.length <= 80
    && typeof s.question === 'string' && s.question.length <= 16384
    && typeof s.answer === 'string' && s.answer.length <= 32768;
}
export function publicState(state, now = Date.now()) {
  const fresh = state.lastSuccess > 0 && now - state.lastSuccess < 4000;
  return { mode:'live', transport: fresh ? 'online' : state.status, sampledAt:state.lastSuccess || null,
    error:state.error || null, snapshot:fresh ? state.snapshot : null };
}
export function createObserverServer({ phoneURL = 'http://127.0.0.1:18766/snapshot', fetcher = fetch } = {}) {
  // Fixed loopback target in production; never an arbitrary-URL proxy.
  let token = '', generation = 0, busy = false;
  const state = { status:'unpaired', lastSuccess:0, snapshot:null, error:null };
  async function poll() {
    if (!token || busy) return;
    busy = true; const current = generation;
    try {
      const response = await fetcher(phoneURL, { headers:{ Authorization:`Bearer ${token}` },
        redirect:'error', signal:AbortSignal.timeout(2200) });
      if (!response.ok) throw new Error(response.status === 403 ? 'token' : 'transport');
      const reader = response.body.getReader(); const parts = []; let size = 0;
      while (true) {
        const { done, value } = await reader.read(); if (done) break;
        size += value.byteLength; if (size > 250000) { await reader.cancel(); throw new Error('size'); }
        parts.push(Buffer.from(value));
      }
      const snapshot = JSON.parse(Buffer.concat(parts).toString('utf8'));
      if (!validSnapshot(snapshot)) throw new Error('shape');
      if (generation !== current) return;
      state.snapshot = snapshot; state.lastSuccess = Date.now(); state.status = 'online'; state.error = null;
    } catch (error) {
      if (generation !== current) return;
      state.snapshot = null; state.lastSuccess = 0; state.status = 'offline';
      state.error = error.message === 'token' ? '令牌已失效，请在Turbo IO重新开启并连接。' : 'USB 观察接口不可达；检查连接、Turbo IO开关或 App 是否被挂起。';
    } finally { busy = false; }
  }
  const interval = setInterval(poll,1000); interval.unref();
  const headers = { 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
    'X-Frame-Options':'DENY', 'Referrer-Policy':'no-referrer',
    'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" };
  const server = http.createServer(async (req,res) => {
    const send = (code,body,type='application/json; charset=utf-8') => {
      res.writeHead(code,{...headers,'Content-Type':type}); res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
    };
    if (req.headers.host !== '127.0.0.1:8790') return send(403,{error:'host'});
    if (req.method === 'GET' && req.url === '/api/state') return send(200,publicState(state));
    if (req.method === 'POST' && ['/api/connect','/api/disconnect'].includes(req.url)) {
      if (req.headers.origin !== origin || req.headers['content-type'] !== 'application/json') return send(403,{error:'origin'});
      try {
        let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 1024) return send(413,{error:'size'}); }
        const value = JSON.parse(body);
        if (req.url === '/api/connect' && !validToken(value.token)) return send(400,{error:'请输入Turbo IO显示的32位临时令牌'});
        generation++; token = req.url === '/api/connect' ? value.token : '';
        state.snapshot = null; state.lastSuccess = 0; state.status = token ? 'connecting' : 'unpaired'; state.error = null;
        send(200,{ok:true}); void poll();
      } catch { send(400,{error:'无效请求'}); }
      return;
    }
    const files = { '/':['index.html','text/html; charset=utf-8'], '/app.js':['app.js','text/javascript; charset=utf-8'], '/style.css':['style.css','text/css; charset=utf-8'] };
    const file = files[req.url];
    if (req.method !== 'GET' || !file) return send(404,{error:'not found'});
    try { send(200,await fs.readFile(new URL(file[0],root)),file[1]); } catch { send(500,{error:'asset unavailable'}); }
  });
  server.on('close',() => { clearInterval(interval); token = ''; generation++; });
  server.headersTimeout = 5000; server.requestTimeout = 5000;
  return { server, poll };
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const udidIndex = process.argv.indexOf('--udid');
  const udid = udidIndex >= 0 ? process.argv[udidIndex+1] : undefined;
  if (udid !== undefined && !/^[a-f0-9-]{20,50}$/i.test(udid)) throw new Error('Invalid device identifier');
  const proxy = process.argv.includes('--no-proxy') ? null : spawn('iproxy',['-s','127.0.0.1',...(udid ? ['-u',udid]:[]),'18766:18765'],{stdio:'ignore'});
  proxy?.on('error',() => process.stderr.write('USB 转发未启动；请检查 iproxy 是否已安装。\n'));
  proxy?.on('exit',code => { if (code) process.stderr.write('USB 转发已退出；请检查设备或端口占用。\n'); });
  const { server } = createObserverServer();
  server.on('error',() => { proxy?.kill(); process.stderr.write('观察页端口不可用。\n'); process.exitCode = 1; });
  server.listen(8790,'127.0.0.1',() => process.stdout.write(`显示观察页 ${origin} · 只读 / 内存缓存 / USB\n`));
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,() => { proxy?.kill(); server.close(); server.closeAllConnections(); });
}
