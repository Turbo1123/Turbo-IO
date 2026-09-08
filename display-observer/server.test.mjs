import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createObserverServer, validToken, validSnapshot, publicState, origin } from './server.mjs';
const sample = () => ({version:1,connected:true,includesText:false,session:'synthetic',sampledAt:Date.now()/1000,phase:'idle',page:{},question:'',answer:'',events:[]});
test('token and snapshot validation',() => {
  assert.ok(validToken('a'.repeat(32))); assert.ok(!validToken('a'.repeat(31))); assert.ok(!validToken('x'.repeat(32)));
  assert.ok(validSnapshot(sample())); assert.ok(!validSnapshot({...sample(),events:Array(81).fill({})}));
});
test('stale snapshots are never served as live',() => {
  assert.equal(publicState({lastSuccess:100,status:'offline',snapshot:sample()},5000).snapshot,null);
});
test('local server blocks hostile hosts/origins; no token in response; loses stale data',async () => {
  let fail = false, calls=0;
  const { server,poll } = createObserverServer({fetcher:async (_,options) => {
    calls++; assert.equal(options.headers.Authorization,`Bearer ${'a'.repeat(32)}`);
    if(fail) throw Error('secret-private-server-error'); return Response.json(sample());
  }});
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  const request = (path,options={}) => new Promise((resolve,reject) => {
    const req=http.request(url+path,{method:options.method || 'GET',headers:{Host:'127.0.0.1:8790',...options.headers}},res => {
      const parts=[]; res.on('data',part=>parts.push(part));
      res.on('end',()=>resolve(new Response(Buffer.concat(parts),{status:res.statusCode,headers:res.headers})));
    }); req.on('error',reject); req.end(options.body);
  });
  try {
    assert.equal((await fetch(url+'/api/state')).status,403);
    assert.equal((await request('/api/connect',{method:'POST',headers:{Origin:'https://evil.example','Content-Type':'application/json'},body:'{}'})).status,403);
    assert.equal((await request('/api/connect',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({token:'a'.repeat(32)})})).status,200);
    await new Promise(r=>setTimeout(r,30));
    const state = await (await request('/api/state')).json(); assert.equal(state.transport,'online'); assert.ok(calls>0);
    assert.ok(!JSON.stringify(state).includes('a'.repeat(32)));
    fail=true; await poll(); const lost=await (await request('/api/state')).json(); assert.equal(lost.snapshot,null); assert.ok(!JSON.stringify(lost).includes('secret-private'));
    assert.equal((await request('/api/control',{method:'POST'})).status,404);
    const page=await request('/'); assert.ok(page.headers.get('content-security-policy').includes("frame-ancestors 'none'"));
    assert.ok((await page.text()).includes('不是镜片截图'));
    await request('/api/disconnect',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:'{}'});
    assert.equal((await (await request('/api/state')).json()).transport,'unpaired');
  } finally { server.closeAllConnections(); await new Promise(r=>server.close(r)); }
});
