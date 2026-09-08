import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { createInterface } from 'node:readline';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, mkdirSync, realpathSync, statSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import http from 'node:http';
import https from 'node:https';
import { pathToFileURL } from 'node:url';

export class BridgeError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}
const check = (ok, code, status) => { if (!ok) throw new BridgeError(code, status); };
const bounded = (s, n = 8192) => typeof s === 'string' && s.trim().length > 0 && Buffer.byteLength(s) <= n;

/** Private stdio child. Never exposes arbitrary JSON-RPC or shell endpoints. */
export class CodexRPC extends EventEmitter {
  constructor({ cwd, command = process.env.RAYNEO_CODEX_BINARY || (existsSync('/Applications/ChatGPT.app/Contents/Resources/codex') ? '/Applications/ChatGPT.app/Contents/Resources/codex' : 'codex') }) {
    super(); this.cwd = cwd; this.pending = new Map(); this.counter = 0;
    this.child = spawn(command, ['app-server', '--stdio', '-c', 'mcp_servers={}'], { cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stderr.on('data', () => {}); // SDK logs may contain user content; do not forward.
    this.lines = createInterface({ input: this.child.stdout });
    this.lines.on('line', line => {
      if (Buffer.byteLength(line) > 8_388_608) { this.child.kill(); return; }
      let msg; try { msg = JSON.parse(line); } catch { return; }
      if (msg.method) { this.emit('message', msg); return; }
      const waiter = this.pending.get(msg.id);
      if (!waiter) return;
      this.pending.delete(msg.id); clearTimeout(waiter.timer);
      msg.error ? waiter.reject(new BridgeError('codex_rpc_failed', 502)) : waiter.resolve(msg.result);
    });
    const closed = () => {
      for (const waiter of this.pending.values()) { clearTimeout(waiter.timer); waiter.reject(new BridgeError('codex_unavailable', 503)); }
      this.pending.clear(); this.emit('closed');
    };
    this.child.on('error', closed); this.child.on('exit', closed);
  }
  send(message) { check(this.child.stdin.writable, 'codex_unavailable', 503); this.child.stdin.write(JSON.stringify(message) + '\n'); }
  request(method, params = {}) {
    const id = ++this.counter;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new BridgeError('codex_timeout_outcome_unknown', 504)); }, method.startsWith('thread/') ? 90_000 : 30_000);
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ id, method, params }); } catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  async initialize() {
    await this.request('initialize', { clientInfo: { name: 'rayneo_companion_bridge', title: 'Turbo IO Codex', version: '0.1.0' } });
    this.send({ method: 'initialized' });
  }
  close() { this.child.kill(); }
}

export class TaskBridge {
  constructor(rpc, { cwd, stateFile, allowWrite = false, now = () => Date.now() }) {
    this.rpc = rpc; this.cwd = cwd; this.stateFile = stateFile; this.allowWrite = allowWrite; this.now = now;
    this.tasks = new Map(); this.operations = new Map(); this.requests = new Map(); this.online = true;
    this.events = [];
    if (stateFile) {
      try {
        const data = JSON.parse(readFileSync(stateFile, 'utf8'));
        check(data.cwd === cwd, 'state_workspace_mismatch');
        this.operations = new Map(data.operations || []);
        for (const t of data.tasks || []) this.tasks.set(t.id, { ...t, status: '恢复待确认', answer: '', turnId: null, pending: [] });
      } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    rpc.on('message', msg => this.receive(msg));
    rpc.on('closed', () => {
      this.online = false; this.requests.clear();
      for (const task of this.tasks.values()) { task.pending = []; task.status = '连接中断，执行结果待核对'; }
    });
  }
  persist() {
    if (!this.stateFile) return;
    mkdirSync(dirname(this.stateFile), { recursive: true, mode: 0o700 });
    const temp = this.stateFile + '.tmp';
    // No transcript, token, prompt or approval body persisted by the bridge.
    writeFileSync(temp, JSON.stringify({ cwd: this.cwd, tasks: [...this.tasks.values()].map(({ id, threadId }) => ({ id, threadId })), operations: [...this.operations] }), { mode: 0o600 });
    renameSync(temp, this.stateFile);
  }
  snapshot() {
    this.expire();
    this.events = this.events.filter(e => e.expiresAt > this.now() && (!e.approvalId || this.requests.has(e.approvalId)));
    return { protocolVersion: 1, online: this.online, workspace: this.cwd, readOnly: !this.allowWrite, events: this.events, tasks: [...this.tasks.values()].map(t => ({ ...t, pending: t.pending.map(id => this.requests.get(id)?.view).filter(Boolean) })) };
  }
  notify(task, { kind, title, content, turnId, approvalId = null, expiresAt = this.now() + 3600000 }) {
    this.events.push({ id: randomUUID(), taskId: task.id, turnId, kind, title,
      content: Array.from(String(content).replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '')).slice(0, 350).join(''),
      approvalId, createdAt: this.now(), expiresAt });
    this.events = this.events.slice(-128); // bounded, no transcript event log written to disk
  }
  async once(key, action) {
    check(typeof key === 'string' && /^[a-zA-Z0-9-]{16,80}$/.test(key), 'idempotency_key_required');
    if (this.operations.has(key)) {
      const old = this.operations.get(key);
      check(old.result, 'previous_delivery_unknown_do_not_replay', 409); return old.result;
    }
    check(this.operations.size < 2048, 'operation_ledger_full', 409);
    this.operations.set(key, { pending: true }); this.persist(); // journal before side effect
    const result = await action();
    this.operations.set(key, { result }); this.persist(); return result;
  }
  async message({ taskId, text, requestId }) {
    check(bounded(text), 'invalid_text'); check(this.online, 'codex_unavailable', 503);
    return this.once(requestId, async () => {
      let task;
      if (taskId) {
        task = this.tasks.get(taskId); check(task, 'unknown_task', 404);
        check(!task.turnId && task.pending.length === 0, 'task_busy_stop_or_wait', 409);
        await this.rpc.request('thread/resume', { threadId: task.threadId, cwd: this.cwd, approvalPolicy: 'on-request', approvalsReviewer: 'user', sandbox: this.allowWrite ? 'workspace-write' : 'read-only' });
      } else {
        check(this.tasks.size < 16, 'task_limit', 409);
        const result = await this.rpc.request('thread/start', { cwd: this.cwd, approvalPolicy: 'on-request', approvalsReviewer: 'user', sandbox: this.allowWrite ? 'workspace-write' : 'read-only' });
        check(bounded(result?.thread?.id, 256), 'invalid_codex_thread', 502);
        task = { id: randomUUID(), threadId: result.thread.id, turnId: null, status: '准备中', answer: '', pending: [] };
        this.tasks.set(task.id, task); this.persist();
      }
      task.answer = ''; task.status = '执行中'; task.turnId = 'starting';
      try {
        const result = await this.rpc.request('turn/start', { threadId: task.threadId, input: [{ type: 'text', text }] });
        // Completion may arrive before the RPC response. Do not resurrect it.
        if (task.turnId === 'starting') task.turnId = result.turn.id;
      } catch (error) { task.status = '发送结果待核对，请勿重复提交'; throw error; }
      return { taskId: task.id, accepted: true };
    });
  }
  async stop({ taskId, requestId }) {
    return this.once(requestId, async () => {
      const task = this.tasks.get(taskId); check(task, 'unknown_task', 404);
      check(task.turnId && task.turnId !== 'starting', 'no_interruptible_turn', 409);
      await this.rpc.request('turn/interrupt', { threadId: task.threadId, turnId: task.turnId });
      if (task.turnId) task.status = '已请求停止，等待确认'; return { taskId, accepted: true };
    });
  }
  async decide({ taskId, approvalId, decision, answers, requestId }) {
    this.expire();
    return this.once(requestId, async () => {
      const r = this.requests.get(approvalId), task = this.tasks.get(taskId);
      check(r && task && r.view.taskId === taskId && task.turnId === r.view.turnId, 'stale_or_wrong_request', 409);
      let result;
      if (r.kind === 'question') {
        check(answers && typeof answers === 'object' && !Array.isArray(answers), 'answers_required');
        const questions = r.view.questions;
        check(Object.keys(answers).length === questions.length && questions.every(q => bounded(answers[q.id], 2000)), 'invalid_answers');
        result = { answers: Object.fromEntries(questions.map(q => [q.id, { answers: [answers[q.id]] }])) };
      } else {
        check(['accept', 'decline'].includes(decision), 'invalid_decision');
        check(!r.allowed || r.allowed.includes(decision), 'decision_not_available');
        result = { decision };
      }
      this.rpc.send({ id: r.rpcId, result }); this.drop(approvalId);
      task.status = '已提交回应，等待执行'; return { taskId, accepted: true };
    });
  }
  drop(id) { this.requests.delete(id); for (const t of this.tasks.values()) t.pending = t.pending.filter(x => x !== id); }
  expire() {
    for (const [id, r] of this.requests) if (r.view.expiresAt <= this.now()) {
      this.rpc.send({ id: r.rpcId, ...(r.kind === 'question' ? { error: { code: -32000, message: 'User input expired' } } : { result: { decision: 'decline' } }) }); this.drop(id);
    }
  }
  receive(msg) {
    const p = msg.params || {}, task = [...this.tasks.values()].find(t => t.threadId === p.threadId);
    if (msg.id !== undefined) {
      const kind = msg.method === 'item/tool/requestUserInput' ? 'question' : ['item/commandExecution/requestApproval', 'item/fileChange/requestApproval'].includes(msg.method) ? 'approval' : null;
      if (!task || !kind || !bounded(p.turnId, 256) || (task.turnId !== 'starting' && task.turnId !== p.turnId) || this.requests.size >= 32) {
        this.rpc.send({ id: msg.id, error: { code: -32601, message: 'Unsupported or inactive request; never auto-approved' } }); return;
      }
      task.turnId = p.turnId;
      const id = randomUUID();
      const questions = kind === 'question' ? (Array.isArray(p.questions) ? p.questions : []).slice(0, 3).map(q => ({ id: q.id, question: String(q.question || '').slice(0, 2000), options: (q.options || []).slice(0, 8).map(o => String(o.label).slice(0, 300)) })) : [];
      const view = { id, taskId: task.id, turnId: p.turnId, kind, summary: String(p.command || p.reason || p.grantRoot || 'Codex 请求确认').slice(0, 4000), questions, expiresAt: this.now() + 120000 };
      this.requests.set(id, { rpcId: msg.id, kind, allowed: p.availableDecisions, view });
      task.pending.push(id); task.status = kind === 'question' ? '等待回答' : '等待批准';
      this.notify(task, { kind, title: 'Codex ' + task.status, content: '任务 ' + task.id.slice(0, 4) + ' 需要你确认。请在Turbo IO Codex 控制台查看完整问题或操作；眼镜通知不代表批准。', turnId: p.turnId, approvalId: id, expiresAt: view.expiresAt });
      return;
    }
    if (!task) return;
    if (msg.method === 'serverRequest/resolved') {
      for (const [id, r] of this.requests) if (r.rpcId === p.requestId && r.view.taskId === task.id) this.drop(id);
      return;
    }
    if (msg.method === 'turn/started' && task.turnId === 'starting') task.turnId = p.turn.id;
    if (p.turnId && task.turnId !== p.turnId) return;
    if (msg.method === 'item/agentMessage/delta') task.answer = (task.answer + String(p.delta || '')).slice(-16000);
    if (msg.method === 'item/completed' && p.item?.type === 'agentMessage' && (p.item.phase === 'final_answer' || !task.answer)) task.answer = String(p.item.text || '').slice(-16000);
    if (msg.method === 'turn/completed' && (task.turnId === p.turn?.id || task.turnId === 'starting')) {
      task.status = ({ completed: '已完成', interrupted: '已停止', failed: '执行失败' })[p.turn.status] || '执行结束';
      if (['completed', 'failed', 'interrupted'].includes(p.turn.status)) {
        this.notify(task, { kind: p.turn.status, title: 'Codex ' + task.status,
          content: p.turn.status === 'completed' ? (task.answer || '任务已完成，请在Turbo IO查看。') : '任务 ' + task.id.slice(0, 4) + '：' + task.status + '，请在Turbo IO核对。', turnId: p.turn.id });
      }
      task.turnId = null; for (const id of [...task.pending]) this.drop(id);
    }
  }
}

export function createHandler(bridge, token) {
  check(typeof token === 'string' && /^[A-Za-z0-9_-]{32,256}$/.test(token), 'invalid_server_token');
  const expected = Buffer.from('Bearer ' + token);
  return async (req, res) => {
    const reply = (status, object) => { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(JSON.stringify(object)); };
    try {
      const actual = Buffer.from(req.headers.authorization || '');
      check(!req.headers.origin && actual.length === expected.length && timingSafeEqual(actual, expected), 'unauthorized', 401);
      if (req.method === 'GET' && req.url === '/v1/state') { reply(200, bridge.snapshot()); return; }
      const action = ({ '/v1/message': 'message', '/v1/stop': 'stop', '/v1/decision': 'decide' })[req.url];
      check(req.method === 'POST' && action, 'not_found', 404);
      check(req.headers['content-type']?.startsWith('application/json'), 'json_required', 415);
      let text = ''; for await (const chunk of req) { text += chunk; check(Buffer.byteLength(text) <= 16384, 'body_too_large', 413); }
      let body; try { body = JSON.parse(text); } catch { throw new BridgeError('invalid_json'); }
      check(body && typeof body === 'object' && !Array.isArray(body), 'invalid_body');
      // Single mutation at a time across all clients; serialize side effects.
      check(!bridge.mutating, 'bridge_busy', 409); bridge.mutating = true;
      try { reply(200, await bridge[action](body)); } finally { bridge.mutating = false; }
    } catch (error) { reply(error.status || 500, { error: error instanceof BridgeError ? error.code : 'internal_error' }); }
  };
}

async function main() {
  const args = process.argv.slice(2); const option = name => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
  const cwd = realpathSync(option('--workspace') || process.cwd());
  const tokenFile = option('--token-file'); check(tokenFile, 'token_file_required');
  check((statSync(tokenFile).mode & 0o077) === 0, 'token_file_must_be_private');
  const token = readFileSync(tokenFile, 'utf8').trim();
  const host = option('--host') || '127.0.0.1', port = Number(option('--port') || 8787);
  const cert = option('--tls-cert'), key = option('--tls-key');
  check(['127.0.0.1', '::1'].includes(host) || (cert && key), 'remote_requires_tls');
  const rpc = new CodexRPC({ cwd });
  const bridge = new TaskBridge(rpc, { cwd, allowWrite: args.includes('--allow-workspace-write'), stateFile: resolve(option('--state-file') || 'codex-bridge/artifacts/task-ledger.json') });
  await rpc.initialize();
  const handler = createHandler(bridge, token);
  const server = cert && key ? https.createServer({ cert: readFileSync(cert), key: readFileSync(key) }, handler) : http.createServer(handler);
  server.requestTimeout = 35000; server.headersTimeout = 10000;
  server.listen(port, host, () => console.log(`Companion Codex bridge listening; port=${port}; TLS=${Boolean(cert && key)}; workspaceWrite=${bridge.allowWrite}; no credentials logged`));
  const stop = () => { server.close(); rpc.close(); };
  process.on('SIGTERM', stop); process.on('SIGINT', stop);
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main().catch(() => { console.error('Bridge startup failed; check local config, private token file and Codex login.'); process.exitCode = 1; });
