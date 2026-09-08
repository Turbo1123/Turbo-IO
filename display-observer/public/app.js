const $ = id => document.getElementById(id);
let current = null, filter = 'all', previewMode = 'live', menuIndex = 0;
export const menuApps = [
  {name:'录音',icon:'record'}, {name:'实时字幕',icon:'caption'}, {name:'实时提示',icon:'hint'},
  {name:'待办',icon:'todo'}, {name:'提词器',icon:'prompter'}, {name:'全天智记',icon:'memory'}, {name:'勿扰模式',icon:'moon'}
];
const aliases = {'字幕':'实时字幕'};
export function menuFromPage(page) {
  const name = aliases[page.app] || page.app;
  const named = menuApps.findIndex(a => a.name === name);
  if(named >= 0) return {index:named, inferred:false};
  // The user supplied a 1-based menu order. This is explicitly a layout mapping,
  // not reverse engineering the unknown app name or unrelated business messages.
  if(page.scene === 1 && Number.isInteger(page.index) && page.index >= 1 && page.index <= 7)
    return {index:page.index-1,inferred:true};
  return {index:-1,inferred:false};
}
export function previewModel(snapshot,mode='live',index=0) {
  if(mode !== 'live') return {kind:mode,demo:true,index:Math.max(0,Math.min(6,index)),source:'样式演示 · 非实时数据'};
  if(!snapshot?.connected) return {kind:'unknown',demo:false,source:'等待真实连接'};
  if(['recording','processing','displaying'].includes(snapshot.phase))
    return {kind:'chat',demo:false,source:'依据 App 语音阶段重绘 · 非镜片确认'};
  const p = snapshot.page || {};
  if(!Number.isFinite(p.at) || p.action === 2) return {kind:'unknown',demo:false,source:'等待下一条页面回报'};
  if(p.scene === 0) return {kind:'home',demo:false,source:'眼镜回报：仪表盘 · 内容重绘'};
  const menu = menuFromPage(p);
  if([1,2].includes(p.scene) && menu.index >= 0) return {kind:'menu',demo:false,...menu,
    source:menu.inferred ? '菜单索引回报 · 按你提供的顺序映射' : `眼镜回报：${p.scene===1 ? '菜单选中':'已进入'} ${menuApps[menu.index].name}`};
  return {kind:'unknown',demo:false,source:'未知页面 · 不猜测内容'};
}
const labels = { received:'眼镜 → App', submitted:'App → SDK · 已提交', connection:'连接事件', loss:'接收异常' };
const phases = { disabled:'待命关闭', idle:'等待唤醒', recording:'正在聆听', processing:'生成回答', displaying:'回答已提交', waitingForConnection:'等待连接' };
const time = value => Number.isFinite(value) ? new Date(value*1000).toLocaleTimeString('zh-CN',{hour12:false}) : '—';
function node(tag,text,cls) { const e = document.createElement(tag); if (text !== undefined) e.textContent = String(text); if (cls) e.className = cls; return e; }
function icon(name,cls='') {
  const paths = {
    record:['M24 34V54 M40 24V64 M56 12V76 M72 24V64 M88 34V54'],
    caption:['M20 20H92V70H62L44 86V70H20Z','M32 36H52 M32 52H46 M65 34L58 55 M65 34L73 55 M61 48H70 M77 38H84'],
    hint:['M22 20H90V69H60L43 85V69H22Z','M56 31L59 41L69 44L59 47L56 57L53 47L43 44L53 41Z'],
    todo:['M38 20H89V88H23V20H38','M41 14H71V27H41Z','M35 44L40 49L49 39 M58 44H76 M35 66L40 71L49 61 M58 66H76'],
    prompter:['M19 20H93V69H19Z','M34 34H77 M34 45H70 M34 56H61 M56 69V87 M37 88H75'],
    memory:['M26 36C26 18 48 14 56 29C68 13 87 24 83 41C100 50 86 76 71 72C66 91 40 89 34 72C15 73 12 45 26 36Z','M45 40V64 M56 33V73 M67 43V62'],
    moon:['M74 18C49 15 28 34 28 56C28 79 50 95 73 85C47 84 40 55 55 39C60 32 69 28 79 29Z'],
    battery:['M18 35H84V70H18Z M85 45H92V60','M28 44V61 M40 44V61 M52 44V61 M64 44V61'],
    cloud:['M25 73H84C108 70 101 43 82 45C78 16 38 18 32 47C12 43 7 70 25 73Z'],
    calendar:['M22 27H90V88H22Z M22 42H90 M39 17V34 M73 17V34'],
    chat:['M17 23H95V74H49L32 88V74H17Z','M35 49H36 M55 49H56 M75 49H76']
  };
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  for(const [k,v] of Object.entries({viewBox:'0 0 112 104',fill:'none',stroke:'currentColor','stroke-width':'4','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',class:cls})) svg.setAttribute(k,v);
  for(const d of paths[name] || paths.hint) { const p=document.createElementNS(svg.namespaceURI,'path'); p.setAttribute('d',d); svg.append(p); }
  return svg;
}
let lastLensKey = '';
function renderLens(snapshot) {
  const model=previewModel(snapshot,previewMode,menuIndex);
  const minute = new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false});
  const key=JSON.stringify([model,snapshot?.question,snapshot?.answer,snapshot?.includesText,minute]);
  $('preview-source').textContent=model.source;
  $('preview-source').className=model.demo ? 'demo-source':'live-source';
  $('menu-controls').hidden=previewMode !== 'menu';
  $('view-kind').textContent={home:'HOME / 首页',chat:'CONVERSATION / 对话',menu:'APP MENU / 单页应用',notification:'NOTIFICATION / 通知',unknown:'WAITING / 等待回报'}[model.kind];
  $('lens-caption').textContent=model.demo ? 'STYLE DEMO · 样式演示':'STATE RECONSTRUCTION · 状态重绘';
  $('preview-boundary').textContent=model.demo ? '样式演示：示例文字、09:30、95% 与 28°仅用于布局查看。翻页不会发送到眼镜。' : '实时状态重绘，不是镜片截图。首页时钟使用电脑时间，天气/电量未接入；语音文字仅表示 App 已提交。';
  $('menu-position').textContent=`${String(menuIndex+1).padStart(2,'0')} / 07`;
  for(const b of document.querySelectorAll('[data-menu-index]')) { const selected=Number(b.dataset.menuIndex)===menuIndex; b.classList.toggle('selected',selected); b.setAttribute('aria-pressed',String(selected)); }
  for(const b of document.querySelectorAll('[data-mode]')) b.setAttribute('aria-pressed',String(b.dataset.mode===previewMode));
  if(key===lastLensKey) return; lastLensKey=key;
  const lens=$('lens'); lens.className=`lens optical-${model.kind}`; lens.replaceChildren();
  if(model.kind==='unknown') {
    const empty=node('div',undefined,'optical-empty'); empty.append(icon('hint'),node('div','等待页面回报'),node('small','可切换「样式演示」查看布局，不会控制眼镜')); lens.append(empty);
  } else if(model.kind==='menu') {
    const app=menuApps[model.index]; const center=node('div',undefined,'single-app');
    center.append(icon(app.icon,'app-icon'),node('div',app.name,'app-title')); lens.append(center);
  } else if(model.kind==='chat') {
    const box=node('div',undefined,'conversation-box');
    const question=model.demo ? '《欢迎来龙餐馆》电影的口碑怎么样？' : snapshot.includesText ? snapshot.question || '正在聆听…' : '文字观察未开启';
    const answer=model.demo ? '《欢迎来龙餐馆》整体口碑很不错，豆瓣稳定 8.7 分，购票平台分数也很高，是暑期口碑黑马。' : snapshot.includesText ? snapshot.answer || '等待回答…' : '请在Turbo IO开启「包含本轮发送文字」。';
    const content=node('div',undefined,'conversation-scroll'); content.append(node('div',question,'optical-question'),node('div',answer,'optical-answer')); box.append(content,node('div','✦','assistant-star')); lens.append(box);
  } else if(model.kind==='home') {
    lens.append(node('div','日程','optical-heading'));
    const home=node('div',undefined,'home-grid'), clock=node('div',undefined,'home-clock');
    const date=model.demo ? '8月21日 周五' : new Date().toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'short'});
    clock.append(node('div',date,'home-date'),node('div',model.demo ? '09:30':minute,'home-time'));
    const meta=node('div',undefined,'home-meta'); meta.append(icon('battery'),node('span',model.demo ? '95%':'—%'),icon('cloud'),node('span',model.demo ? '28°':'—°')); clock.append(meta);
    const schedule=node('div',undefined,'schedule-card');
    for(const [title,detail] of model.demo ? [['项目复盘会议','14:00–15:30　·　503 室'],['视觉设计评审会','16:00–16:30　·　503 室']] : [['暂无日程回报','仅页面状态已接入，不填入虚构日程']]) {
      const item=node('div',undefined,'schedule-item'), name=node('div'); name.append(icon('calendar'),node('span',title)); item.append(name,node('small',detail)); schedule.append(item);
    }
    home.append(clock,schedule); lens.append(home,node('div','━ · ·','home-pages'));
  } else if(model.kind==='notification') {
    lens.append(node('div','通知','optical-heading')); const box=node('div',undefined,'notification-box');
    const title=node('div',undefined,'notification-title'); title.append(icon('chat'),node('span','Turbo IO'));
    box.append(title,node('div','Codex 已完成任务，测试结果已准备好。','notification-content'),node('small','关闭 (15s) · 样式示意','notification-close')); lens.append(box);
  }
}
function render(state) {
  current = state;
  const s = state.snapshot;
  $('transport').textContent = {online:'● USB 观察在线',offline:'○ 观察接口失联',unpaired:'○ 等待连接',connecting:'◌ 正在连接'}[state.transport] || '○ 观察页失联';
  $('transport').className = 'pill' + (state.transport === 'online' ? ' online':'');
  $('error').textContent = state.error || '';
  $('glasses').textContent = s ? (s.connected ? '已认证':'未连接') : '未知';
  const p = s?.page || {}, hasPage = s?.connected && Number.isFinite(p.at);
  $('scene').textContent = hasPage ? (p.app || p.name) : '尚未收到';
  $('scene-age').textContent = hasPage ? `${p.name} · 回报于 ${time(p.at)}（最后观察）` : '不使用发送记录推定当前页面';
  $('screen').textContent = s?.screenRaw === undefined ? '—' : String(s.screenRaw);
  $('phase').textContent = s ? (phases[s.phase] || '未知状态') : '—';
  $('freshness').textContent = s ? `快照 ${time(s.sampledAt)} · 最后上行 ${time(s.lastInbound)}` : '等待实时数据，不展示旧快照';
  renderLens(s);
  $('page-tag').textContent = hasPage ? '眼镜原始回报' : '未观察';
  const details = $('page-details'); details.replaceChildren();
  const values = [['数据源','Launcher / type 24 / glass_preview'],['页面',hasPage ? p.name:'尚未收到'],['应用',p.app || '—'],['索引原值',p.index ?? '—'],['动作原值',p.action ?? '—'],['回报时间',hasPage ? time(p.at):'—']];
  for (const [key,value] of values) details.append(node('dt',key),node('dd',value));
  const all = s?.events || [], events = all.filter(e => filter === 'all' || e.kind === filter).slice().reverse();
  $('event-count').textContent = `${all.length} 条 / 80`;
  const list = $('events'); list.replaceChildren();
  if (!events.length) list.append(node('div','暂时没有事件。连接后在眼镜打开菜单或切换页面。','empty'));
  for (const e of events) {
    const row = node('article',undefined,`event ${e.kind === 'submitted' ? 'submitted':''}`);
    const header = node('div',undefined,'event-header'); header.append(node('b',labels[e.kind] || '未知事件'),node('span',time(e.at)),node('span',`#${e.id}`));
    row.append(header,node('p',e.detail)); if (e.text) row.append(node('pre',e.text+(e.textTruncated ? '\n…（事件文字截断，仅预览前256字节）':''))); list.append(row);
  }
}
async function post(path,body) {
  const result = await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  if (!result.ok) throw new Error((await result.json()).error || '连接失败');
}
function boot() {
$('connect-form').addEventListener('submit',async e => { e.preventDefault(); const token = $('token').value.trim(); $('token').value = ''; try { await post('/api/connect',{token}); await refresh(); } catch(error) { $('error').textContent = error.message; } });
$('disconnect').addEventListener('click',async () => { try { await post('/api/disconnect',{}); await refresh(); } catch { $('error').textContent = '观察服务不可达'; } });
for (const button of document.querySelectorAll('[data-filter]')) button.addEventListener('click',() => { filter=button.dataset.filter; for(const b of document.querySelectorAll('[data-filter]')) b.classList.toggle('selected',b===button); if(current) render(current); });
for(const b of document.querySelectorAll('[data-mode]')) b.addEventListener('click',()=>{ previewMode=b.dataset.mode; for(const other of document.querySelectorAll('[data-mode]')) other.classList.toggle('selected',other===b); renderLens(current?.snapshot); });
for(const [index,app] of menuApps.entries()) {
  const dot=node('button',undefined); dot.dataset.menuIndex=index; dot.setAttribute('aria-label',`${index+1}. ${app.name}`); dot.title=app.name;
  dot.addEventListener('click',()=>{menuIndex=index;renderLens(current?.snapshot);}); $('menu-dots').append(dot);
}
$('menu-prev').addEventListener('click',()=>{menuIndex=(menuIndex+6)%7;renderLens(current?.snapshot);});
$('menu-next').addEventListener('click',()=>{menuIndex=(menuIndex+1)%7;renderLens(current?.snapshot);});
setInterval(refresh,1000); void refresh();
}
let loading = false;
async function refresh() { if(loading) return; loading=true; try { const result=await fetch('/api/state',{cache:'no-store',signal:AbortSignal.timeout(2500)}); if(!result.ok) throw Error(); render(await result.json()); } catch { render({transport:'offline',snapshot:null,error:'电脑观察服务不可达；未继续显示旧内容。'}); } finally { loading=false; } }
if(typeof document !== 'undefined') boot();
