// Private, read-only retrieval. No model, shell, WeChat refresh or task writes.
import { open, readdir, lstat, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import { join, resolve, relative, basename } from 'node:path';
import { homedir } from 'node:os';
import { createHash, timingSafeEqual } from 'node:crypto';
import { readTodoPhoneToken } from './token.mjs';
import { createKnowledgeJobs } from './turbo-knowledge-codex.mjs';

const labels = { wechat: '微信已归档消息', projects: 'LLMWiki 项目文档', learning: '学习资料原文' };
export function cleanText(value) {
  return String(value || '').replace(/sk-[A-Za-z0-9_.-]{8,}/g, '[密钥已隐藏]')
    .replace(/Bearer\s+[A-Za-z0-9_.-]+/gi, '[令牌已隐藏]')
    .replace(/((?:api[_ -]?key|password|密码|token|secret)\s*[=:：]\s*)[^\s,;]+/gi, '$1[已隐藏]');
}
async function safeRead(path, root, limit) {
  const actualRoot = await realpath(root), actual = await realpath(path);
  if (relative(actualRoot, actual).startsWith('..') || actual === actualRoot) throw Error('outside_source');
  const f = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try { const s = await f.stat(); if (!s.isFile() || s.size > limit) throw Error('file_limit'); return { text: await f.readFile('utf8'), updatedAt: s.mtime.toISOString(), size: s.size }; }
  finally { await f.close(); }
}
export function normalizeQuery(input) {
  if (!input || Array.isArray(input) || typeof input !== 'object' || Object.keys(input).some(k => !['query', 'source'].includes(k))) throw Error('invalid_query');
  const query = typeof input.query === 'string' ? input.query.trim() : '';
  const source = input.source || 'all';
  if (query.length < 2 || query.length > 200 || /[\x00-\x1f]/.test(query) || !['all', ...Object.keys(labels)].includes(source)) throw Error('invalid_query');
  return { query, source };
}
export function rankDocuments(docs, input) {
  const { query, source } = normalizeQuery(input);
  const normalized = query.toLowerCase().replace(/请|帮我|查一下|搜索|查询|最新|最近|微信|知识库|里面|关于|进展|情况/g, ' ');
  const tokens = [...new Set(normalized.match(/[a-z0-9_.-]{2,}|[\u3400-\u9fff]{2,}/g) || [])].slice(0, 12);
  if (!tokens.length) return [];
  const candidates = [];
  for (const d of docs) {
    if (source !== 'all' && d.source !== source) continue;
    const hay = `${d.title}\n${d.text}`.toLowerCase(); let score = 0, first = -1;
    for (const token of tokens) { const at = hay.indexOf(token); if (at >= 0) { score += 10 + (d.title.toLowerCase().includes(token) ? 5 : 0); if (first < 0) first = at; } }
    if (!score) continue;
    const at = Math.max(0, first - d.title.length - 1 - 80);
    candidates.push({ ...d, score, excerpt: cleanText(d.text.slice(at, at + 700)) });
  }
  const latest = /最新|最近|刚才|今天/.test(query);
  candidates.sort((a, b) => (latest ? String(b.messageAt || b.updatedAt).localeCompare(String(a.messageAt || a.updatedAt)) : b.score - a.score) || b.score - a.score);
  return candidates.slice(0, 6).map(({ id, source, title, excerpt, messageAt, archivedAt, updatedAt }) => ({ id, source, sourceLabel: labels[source], title: cleanText(title), excerpt, messageAt: messageAt || null, archivedAt: archivedAt || null, updatedAt }));
}
export function createKnowledgeIndex(options = {}) {
  const roots = options.roots;
  if(!roots||['wechat','projects','learning'].some(k=>typeof roots[k]!=='string'||!roots[k].startsWith('/')))throw Error('explicit_sources_required');
  let cached, pending;
  async function load() {
    if (cached && Date.now() - cached.at < 30000) return cached;
    if (pending) return pending;
    pending = (async () => {
      const docs = [], sources = []; let budget = 64 * 1024 * 1024;
      const add = (source, title, text, key, meta) => { if (!text.trim()) return; docs.push({ id: createHash('sha256').update(`${source}:${key}`).digest('hex').slice(0, 24), source, title: String(title).slice(0, 180), text: cleanText(text), ...meta }); };
      for (const source of Object.keys(labels)) {
        const root = roots[source]; let count = 0, partial = false, updatedAt = null, available = false;
        try {
          const info = await lstat(root); if (!info.isDirectory() || info.isSymbolicLink()) throw Error('invalid_root'); available = true;
          if (source === 'wechat') {
            let ignored = new Set();
            try { const prefs = JSON.parse((await safeRead(join(root, '..', 'preferences.json'), join(root, '..'), 1024*1024)).text); ignored = new Set((prefs.ignoredConversations || []).map(x => x.id)); }
            catch (e) { if (e.code !== 'ENOENT') throw e; }
            const dirs = (await readdir(root, { withFileTypes: true })).filter(e => e.isDirectory() && /^[\w-]+$/.test(e.name)).sort((a, b) => b.name.localeCompare(a.name));
            partial = dirs.length > 7; const seen = new Set();
            for (const dir of dirs.slice(0, 7)) {
              try {
                const report = JSON.parse((await safeRead(join(root, dir.name, 'report.json'), root, 8 * 1024 * 1024)).text);
                // "review" is this project's completed archive awaiting human
                // task review; it is not an unfinished message extraction.
                if (!['completed', 'success', 'review'].includes(report.status) || !report.completedAt) { partial = true; continue; }
                const file = await safeRead(join(root, dir.name, 'messages.jsonl'), root, Math.min(budget, 20 * 1024 * 1024)); budget -= file.size;
                const archive = report.completedAt || file.updatedAt; if (!updatedAt || archive > updatedAt) updatedAt = archive;
                for (const line of file.text.split('\n')) {
                  if (docs.length >= 80000) { partial = true; break; }
                  if (!line || line.length > 128000) continue;
                  try { const m = JSON.parse(line); const rawConversation=String(m.conversation || m.table || '未知会话');if(ignored.has(createHash('sha256').update(rawConversation).digest('hex').slice(0,24)))continue; const text = String(m.content || ''); if (!text || text.startsWith('<')) continue;
                    const timestamp = Number(m.createTime || 0); const messageAt = timestamp > 0 && timestamp < 1e13 ? new Date(timestamp > 1e11 ? timestamp : timestamp * 1000).toISOString() : null;
                    const identity = createHash('sha256').update(`${m.conversation || m.conversationId || ''}:${messageAt}:${text}`).digest('hex'); if (seen.has(identity)) continue; seen.add(identity);
                    add(source, m.conversationName || m.senderName || '微信归档', text.slice(0, 8000), identity, { messageAt, archivedAt: archive, updatedAt: file.updatedAt }); count++;
                  } catch { partial = true; }
                }
              } catch { partial = true; }
            }
          } else {
            const queue = [{ path: root, depth: 0 }];
            while (queue.length && count < 3000 && budget > 0) {
              const entry = queue.shift();
              for (const child of await readdir(entry.path, { withFileTypes: true })) {
                if (child.name.startsWith('.') || child.isSymbolicLink()) continue;
                const path = join(entry.path, child.name);
                if (child.isDirectory() && entry.depth < 6) queue.push({ path, depth: entry.depth + 1 });
                else if (child.isFile() && /\.md$/i.test(child.name) && count < 3000) {
                  try { const file = await safeRead(path, root, Math.min(budget, 512 * 1024)); budget -= file.size; add(source, basename(path, '.md'), file.text, relative(root, path), { updatedAt: file.updatedAt }); count++; if (!updatedAt || file.updatedAt > updatedAt) updatedAt = file.updatedAt; } catch { partial = true; }
                }
              }
            }
            if (queue.length) partial = true;
          }
        } catch { partial = true; }
        sources.push({ id: source, name: labels[source], available, count, updatedAt, partial, scope: source === 'wechat' ? '最近7个归档目录；不刷新微信、不含图片/语音附件' : '只读Markdown正文；有文件与容量上限' });
      }
      cached = { at: Date.now(), docs, sources }; return cached;
    })();
    try { return await pending; } finally { pending = null; }
  }
  return {
    async sources() { const index = await load(); return { schema: 1, connected: true, readOnly: true, engine: 'local-keyword', sources: index.sources, indexedAt: new Date(index.at).toISOString() }; },
    async query(input) { normalizeQuery(input); const index = await load(); const results = rankDocuments(index.docs, input); return { schema: 1, results, sources: index.sources, indexedAt: new Date(index.at).toISOString(), untrusted_data: true, coverage: '仅检索已归档数据；关键词命中，不代表全量或实时微信。无命中不等于不存在。', engine: 'local-keyword' }; },
  };
}
export function createKnowledgeGateway(options = {}) {
  const index = options.index || createKnowledgeIndex(options);
  const jobs = options.jobs || createKnowledgeJobs(index, options);
  const tokenFile = options.tokenFile || join(homedir(), 'Library/Application Support/TurboIOKnowledge/knowledge-token');
  let active = 0; const arrivals = [];
  const send = (res, code, data) => { res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(JSON.stringify(data)); };
  return async (req, res) => {
    if (!String(req.url).startsWith('/api/turbo-knowledge')) return false;
    const jobMatch = String(req.url).match(/^\/api\/turbo-knowledge\/jobs\/([a-f0-9-]{36})$/);
    const method = jobMatch ? 'GET' : { '/api/turbo-knowledge/sources': 'GET', '/api/turbo-knowledge/query': 'POST' }[req.url];
    if (!method) { send(res, 404, { error: 'not_found' }); return true; }
    if (req.method !== method || req.headers.origin || req.headers['sec-fetch-site']) { send(res, 403, { error: 'native_readonly_client_required' }); return true; }
    let token; try { token = await readTodoPhoneToken(tokenFile); } catch { send(res, 503, { error: 'knowledge_not_configured' }); return true; }
    const a = Buffer.from(req.headers.authorization || ''), b = Buffer.from(`Bearer ${token}`);
    if (a.length !== b.length || !timingSafeEqual(a, b)) { send(res, 401, { error: 'unauthorized' }); return true; }
    const now = Date.now(); while (arrivals.length && arrivals[0] < now - 60000) arrivals.shift();
    if (active >= 2 || arrivals.length >= 30) { send(res, 429, { error: 'busy' }); return true; } arrivals.push(now); active++;
    try {
      let size = 0; const chunks = [];
      if (Number(req.headers['content-length'] || 0) > 4096) throw Error('invalid_query');
      for await (const chunk of req) { size += chunk.length; if (size > 4096) throw Error('invalid_query'); chunks.push(chunk); }
      if (method === 'GET') { if (size) throw Error('invalid_query'); send(res, 200, jobMatch ? await jobs.read(jobMatch[1]) : { ...await index.sources(), executor: 'Codex', readOnly: true }); }
      else { if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] || '')) throw Error('invalid_query'); const input = JSON.parse(Buffer.concat(chunks).toString('utf8')); send(res, 202, await jobs.submit(input)); }
    } catch { send(res, 400, { error: 'invalid_or_unavailable_query' }); } finally { active--; }
    return true;
  };
}
