import test from 'node:test';
import assert from 'node:assert/strict';
import {queryContext} from './query-context.mjs';
const config = {root: 'https://context.example.invalid', token: 'example-only', segmentId: 'synthetic-id'};
test('exact read-only route, bounded request, labeled untrusted output', async () => {
  let calls = 0;
  const result = await queryContext(config, async (url, options) => {
    calls++; assert.equal(url.pathname, '/v1/rayneo/query'); assert.equal(options.redirect, 'error');
    const body = JSON.parse(options.body); assert.equal(body.segment_id, config.segmentId);
    assert.equal(body.topic, undefined); assert.equal(body.include_derived, false);
    return new Response(JSON.stringify({source:'rayneo',instruction_eligible:false,items:[]}));
  });
  assert.equal(calls, 1); assert.equal(result.untrusted_data, true);
});
test('unsafe configuration fails before a request', async () => {
  for (const root of ['http://example.invalid','https://user:pass@example.invalid','https://example.invalid/path','https://example.invalid/?token=x']) {
    await assert.rejects(queryContext({...config,root},()=>assert.fail('network')),/https_root_required/);
  }
  await assert.rejects(queryContext({...config,topic:'also'},()=>assert.fail('network')),/one_selector_required/);
});
test('auth errors neither retry nor reveal response message', async () => {
  let calls=0;
  await assert.rejects(queryContext(config,async()=>{calls++;return new Response('private-response',{status:401});}),/^Error: HTTP_401$/);
  assert.equal(calls,1);
});
test('reject oversized or instruction-eligible responses', async () => {
  await assert.rejects(queryContext(config,async()=>new Response('x'.repeat(1048577))),/response_limit/);
  await assert.rejects(queryContext(config,async()=>new Response(JSON.stringify({source:'rayneo',instruction_eligible:true,items:[]}))),/invalid_context_envelope/);
});
