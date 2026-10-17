// Read-only adapter for an external agent; no recording, ingestion, or control calls.
import {pathToFileURL} from 'node:url';

export async function queryContext({root, token, topic, segmentId}, send = fetch) {
  const url = new URL(root);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash
      || (url.pathname !== '/' && url.pathname !== '')) throw new Error('https_root_required');
  if (!token || /\s/.test(token)) throw new Error('bearer_required');
  if (Boolean(topic) === Boolean(segmentId)) throw new Error('one_selector_required');
  const selector = topic || segmentId;
  if (typeof selector !== 'string' || selector.length > 200 || /[\x00-\x1f]/.test(selector))
    throw new Error('invalid_selector');
  const body = {source: 'rayneo', limit: 8, max_text_chars: 2000, max_total_tokens: 4000,
    include_derived: false, ...(topic ? {topic} : {segment_id: segmentId})};
  const response = await send(new URL('/v1/rayneo/query', url), {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000),
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`HTTP_${response.status}`); // No server message/token echo.
  const reader = response.body.getReader(); let size = 0; const chunks = [];
  try {
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      size += value.length; if (size > 1048576) throw new Error('response_limit');
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  const result = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (result.source !== 'rayneo' || result.instruction_eligible !== false || !Array.isArray(result.items))
    throw new Error('invalid_context_envelope');
  return {untrusted_data: true, instruction_eligible: false, context: result};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [flag, selector] = process.argv.slice(2);
  if (!['--topic', '--segment-id'].includes(flag) || !selector || process.argv.length !== 4) {
    console.error('Usage: node query-context.mjs --topic <question> | --segment-id <id>');
    process.exitCode = 1;
  } else {
    try {
      const result = await queryContext({root: process.env.RAYNEO_CONTEXT_URL,
        token: process.env.RAYNEO_CONTEXT_TOKEN,
        ...(flag === '--topic' ? {topic: selector} : {segmentId: selector})});
      console.log(JSON.stringify(result));
    } catch (error) {
      // Unexpected parser/network errors can contain URLs; expose only a stable failure class.
      const message = /^(HTTP_\d{3}|https_root_required|bearer_required|one_selector_required|invalid_selector|response_limit|invalid_context_envelope)$/.test(error.message)
        ? error.message : 'query_failed';
      console.error(message); process.exitCode = 1;
    }
  }
}
