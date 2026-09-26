// node examples/tasks.mjs --out /path/to/tasks.json
// Only run source you trust. Output contains declarative data, no JS code.
import { writeFileSync } from 'node:fs';
import { app, page, text, button } from './app-sdk.mjs';
const taskApp = app('tasks', '我的任务', [
  page('home', [text('title', '今日任务 · 示例', 16, 8, 500, 24),
    button('first', '阅读 20 分钟', 16, 50, 500, { type: 'page', target: 'detail' }),
    button('quit', '退出到眼镜首页', 16, 98, 500, { type: 'exit', target: 'system' })]),
  page('detail', [text('title', '阅读 20 分钟', 16, 8, 500, 24),
    button('done', '向我的后端报告完成', 16, 50, 500, { type: 'emit', target: 'task_done' }),
    button('back', '返回任务列表', 16, 98, 500, { type: 'page', target: 'home' })])
], ['backend.events']);
if (process.argv[2] !== '--out' || !process.argv[3]) throw new Error('Pass --out NEW_FILE.json');
writeFileSync(process.argv[3], JSON.stringify(taskApp), { flag: 'wx', mode: 0o600 });
