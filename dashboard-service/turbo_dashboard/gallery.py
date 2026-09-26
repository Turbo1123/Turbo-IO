"""Original, offline-installable MCP application recipes; no third-party clients.

MCP executes in the user's backend. Only whitelisted display snapshots enter ZIPs.
"""
import argparse
import hashlib
import json
import math
from datetime import datetime
from pathlib import Path
from .app_examples import c, t, button, page, document
from .app_package import build_package, read_package
from .contracts import Fault, canonical, exact

GH='https://github.com/'
# id, title, category, SF symbol, source repo, operation, setup, sample rows
RECIPES=[
 ('city_weather','城市天气','出行','sun.max','baidu-maps/mcp','查询城市实时天气与预报','自己的百度地图服务端 AK', ['北京 · 晴 26°C','湿度 42% · 东北风 2级','最低 19°C · 最高 28°C']),
 ('rain_watch','降雨提醒','出行','cloud.rain','caiyunapp/mcp-caiyun-weather','查询所在地分钟降雨预报','自己的彩云天气令牌和经纬度',['未来两小时有小雨','预计 20 分钟后开始','出门记得带伞']),
 ('commute','通勤助手','出行','arrow.triangle.turn.up.right.diamond','baidu-maps/mcp','只读规划通勤路线，提取距离和时间','自己的地图 AK；用户提供起终点',['驾车预计 32 分钟','全程 18.6 公里','路线摘要 · 非实时导航']),
 ('nearby','附近好去处','出行','mappin.and.ellipse','baidu-maps/mcp','按用户位置只读查询附近 POI','自己的地图 AK；用户授权位置',['附近咖啡店 · 300 米','城市书店 · 650 米','选择目的地后在手机查看']),
 ('traffic','道路路况','出行','car.side','baidu-maps/mcp','只读查询指定道路路况','自己的地图 AK 和道路名称',['东向西 · 畅通','主路平均速度 42 km/h','仅供参考，以实际路况为准']),
 ('train_board','火车余票','出行','tram','Joooook/12306-mcp','查询车次、出发到达时间和余票，不下单','按上游文档配置；指定日期/车站',['G101 · 07:00 出发','北京南 → 上海虹桥','二等座：有票 · 示例']),
 ('train_transfer','换乘方案','出行','arrow.triangle.swap','Joooook/12306-mcp','只读检索中转换乘方案','按上游文档配置；指定起终站',['第一程 09:20 → 11:00','站内换乘 · 预留 45 分钟','第二程 11:45 → 13:10']),
 ('flight_board','航班动态','出行','airplane','variflight/variflight-mcp','按航班日期查询起降状态','飞常准平台申请的 API 凭据',['航班 AB1234 · 示例','计划起飞 16:20','登机口待定 · 请看机场大屏']),
 ('calendar','今日日程','效率','calendar','larksuite/lark-openapi-mcp','读取用户授权范围的今日日历','飞书应用凭据和日历只读授权',['10:00 · 产品评审','14:00 · 项目沟通','16:30 · 专注时间']),
 ('work_tasks','工作待办','效率','checklist','larksuite/lark-openapi-mcp','查询授权任务列表，不修改任务','飞书应用凭据及任务只读权限',['审阅方案 · 今天','补充验收记录 · 今天','整理反馈 · 本周']),
 ('knowledge','知识便签','阅读','doc.text','yuque/yuque-mcp-server','只读检索知识库并提取短摘要','语雀 Token；仅授权自己的知识库',['产品原则 · 先验证价值','设计原则 · 信息层次清楚','今日复习 · 一次只做一件事']),
 ('reading_notes','阅读摘记','阅读','book','freestylefly/mcp-server-weread','读取用户自己的笔记和划线，不获取全文','用户自己的微信读书 Cookie 留在后端',['今天记住一个新观点','写下它和工作的联系','摘要为原创演示，不是书籍正文']),
 ('video_digest','视频速览','阅读','play.rectangle','huccihuang/bilibili-mcp-server','只读检索视频标题和简介，不下载视频','依上游要求配置授权；遵守限流',['智能眼镜开发入门','本地模型实践分享','只显示标题摘要，不播放视频']),
 ('trending','热点一览','阅读','flame','qinyuanpei/mcp-server-weibo','只读查询热搜，附来源与时间','依上游要求配置自己的访问凭据',['今日科技话题 · 示例','城市生活观察 · 示例','只展示摘要，真实性需核验']),
 ('repo_tasks','代码待办','开发','chevron.left.forwardslash.chevron.right','oschina/mcp-gitee','读取仓库 Issue/PR 状态，不提交代码','Gitee 只读 Token 与仓库范围',['待审查 PR · 3 项','未解决 Issue · 8 项','今天合入 · 2 项']),
 ('build_status','构建看板','开发','hammer','aliyun/alibabacloud-devops-mcp-server','只读查询云效流水线状态，不启动构建','阿里云效凭据；只读流水线权限',['主分支构建 · 通过','单元测试 · 128 项通过','最近部署 · 示例环境']),
 ('service_health','服务健康','开发','waveform.path.ecg','aliyun/alibabacloud-observability-mcp-server','只读查询监控指标，不执行运维动作','阿里云只读监控角色；限定资源',['错误率 0.2% · 示例','P95 延迟 180ms','可用率 99.9%']),
 ('holiday','节假日日历','生活','calendar.badge.clock','zackchewa/china-mcp-servers','查询中国法定节假日和调休日期','按项目说明运行节假日服务；无需用户账号',['今日安排 · 示例','下一个假期 · 待接入数据','调休信息以官方通知为准']),
 ('news_digest','资讯简报','阅读','newspaper','BochaAI/bocha-search-mcp','只读搜索指定主题并输出带来源短摘要','自己的博查 API Key',['AI 工具观察 · 示例','开源项目进展 · 示例','保留文章来源和查询时间']),
 ('nutrition','餐品营养','生活','fork.knife','M-China/mcd-mcp-server','只读查询餐品营养，不下单不支付','自己的平台授权 Token；选择只读工具',['所选餐品 · 示例','能量 300 kcal · 演示','过敏原和营养以官方信息为准']),
]

def recipe(ident):
    for row in RECIPES:
        if row[0]==ident:return row
    raise Fault('recipe_not_found','Unknown gallery recipe',404)

def icon(index):
    """Original 48px geometric icons, encoded in the device's native mono format."""
    import base64
    paths=[[(8,28),(14,14),(34,14),(40,28),(8,28),(8,36),(40,36),(40,28)],
           [(8,10),(22,14),(24,38),(24,14),(40,10),(40,34),(24,38),(8,34),(8,10)],
           [(8,8),(40,8),(40,40),(8,40),(8,8)],
           [(7,25),(16,25),(20,12),(27,37),(32,25),(41,25)],
           [(6,34),(14,25),(21,30),(32,14),(40,20)]]
    def segment(x,y,a,b):
        dx,dy=b[0]-a[0],b[1]-a[1];q=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy or 1)))
        return math.hypot(x-a[0]-q*dx,y-a[1]-q*dy)<1.5
    buf=bytearray(48*48//8);path=paths[index%5]
    for y in range(48):
        for x in range(48):
            lit=any(segment(x,y,a,b) for a,b in zip(path,path[1:]))
            # Four distinct small status markers make variations identifiable.
            lit|=y in (3,4) and 6<=x<6+(index//5+1)*8
            if lit:buf[y*6+x//8]|=128>>(x%8)
    return dict(format='mono1-msb',width=48,height=48,pixels=base64.b64encode(buf).decode())

def snapshot_doc(ident,snapshot=None,version=1):
    r=recipe(ident);demo=snapshot is None
    if demo:snapshot=dict(headline=r[1],lines=r[7],observedAt='2026-09-26T00:00:00+00:00')
    exact(snapshot,['headline','lines','observedAt'])
    if not isinstance(snapshot['lines'],list) or not 1<=len(snapshot['lines'])<=4:raise Fault('snapshot','Expected 1–4 display lines')
    for s in [snapshot['headline'],snapshot['observedAt'],*snapshot['lines']]:
        if not isinstance(s,str) or not s.strip() or len(s.encode())>80 or any(ord(c)<32 or 127<=ord(c)<160 for c in s):raise Fault('snapshot','Display strings must be nonempty, <=80 UTF-8 bytes and control-free')
    try:
        observed=datetime.fromisoformat(snapshot['observedAt'].replace('Z','+00:00'))
        if observed.tzinfo is None:raise ValueError()
    except ValueError:raise Fault('snapshot_time','observedAt must include an ISO timezone') from None
    short=lambda s:s if len(s)<=21 else s[:20]+'…'
    rows=snapshot['lines'];badge='离线示例 · 非实时' if demo else '数据快照 · 非实时'
    home=[c('icon','image',18,48,48,48,asset='icon'),t('title',r[1],18,8,300,24),t('badge',badge,338,12,185,16)]
    home += [t('line_'+str(i),short(s),86,48+i*26,434,18) for i,s in enumerate(rows[:3])]
    home += [button('detail','详情与时间',18,140,244,'detail'),button('exit','退出',278,140,244,'system')]
    detail=[t('title',short(snapshot['headline']),18,6,504,20)]
    detail += [t('row_'+str(i),s,18,34+i*22,504,16) for i,s in enumerate(rows)]
    detail += [t('time',('演示数据' if demo else '快照时间')+' '+observed.strftime('%m-%d %H:%M %z'),18,124,504,14),button('back','返回概览',18,146,244,'home'),button('exit','退出',278,146,244,'system')]
    doc=document('mcp_'+ident,r[1]+' · 示例' if demo else r[1],[page('home',*home),page('detail',*detail)],{'icon':icon(RECIPES.index(r))})
    doc['version']=version;read_package(build_package(doc));return doc

def prompt(ident):
    r=recipe(ident)
    return f'''使用 Turbo IO 的 turboio-developer Skill，为我开发「{r[1]}」眼镜小应用。
先阅读仓库 docs/DEVELOPER_ECOSYSTEM.md 和 dashboard-service/README.md。
模板 ID：{ident}；参考 MCP 项目：{GH+r[4]}。
目标：{r[5]}。配置需求：{r[6]}，密钥仅在我自己的后端保存，不写进 ZIP/GitHub。
先在我的电脑完成 MCP tools/list，核对当前工具名称、输入和权限，仅调用我授权的只读工具；不要假设上游文档中的字段始终不变。
把实际结果映射为 headline、lines（1–4条、每条最多80 UTF-8字节）、observedAt（带时区ISO时间），只保留我要展示的字段。
先用离线样例跑通，再用我的真实结果构建快照：turbo-app gallery build {ident} --data snapshot.json --version 2 --out my-app.zip。
执行 turbo-app check、preview；提供 ZIP、SHA-256、来源、数据时间和映射测试。
TAP1 是 540×180 的有界原生组件，ZIP解压总计20KiB，最多4页；不在眼镜执行JS/HTML/MCP。
当前 App v1 为快照安装，不承诺后台实时刷新、按钮事件回流、音频播放或自动安装。修改已安装同ID包必须递增version。
给出手机「应用广场 → 我的应用 → 导入ZIP → 预览 → 查询 → 确认安装」步骤；不要刷固件或自动调用付款/下单/发消息等写工具。
如果缺少真实授权，只交付明确标注示例的版本并说明缺项，不伪造联网成功。'''

def catalog():
    result=[]
    for r in RECIPES:
        blob=build_package(snapshot_doc(r[0]))
        result.append(dict(id=r[0],name=r[1],category=r[2],symbol=r[3],source=GH+r[4],purpose=r[5],setup=r[6],status='offline-template',resource='Gallery_'+r[0],zipBytes=len(blob),sha256=hashlib.sha256(blob).hexdigest(),prompt=prompt(r[0])))
    return result

def export(directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=False)
    items=catalog()
    for item in items:
        (directory/(item['resource']+'.zip')).write_bytes(build_package(snapshot_doc(item['id'])))
        (directory/(item['id']+'.json')).write_bytes(canonical(snapshot_doc(item['id'])))
        (directory/(item['id']+'.md')).write_text(item['prompt']+'\n')
    (directory/'catalog.json').write_bytes(canonical(dict(schema=1,mode='bundled-offline',sourceIndex=GH+'zackchewa/awesome-china-mcp',entries=items)))
    return items

def cli(args):
    if args.gallery_command=='list':print(json.dumps(catalog(),ensure_ascii=False,indent=2));return
    if args.gallery_command=='export':print(f'Exported {len(export(args.out))} offline templates');return
    if args.gallery_command=='prompt':print(prompt(args.id));return
    snapshot=None
    if args.data:
        with args.data.open('rb') as f:raw=f.read(8193)
        if len(raw)>8192:raise Fault('snapshot_size','Snapshot input exceeds 8 KiB')
        snapshot=json.loads(raw)
    blob=build_package(snapshot_doc(args.id,snapshot,args.version))
    with args.out.open('xb') as f:f.write(blob)
    print(json.dumps(dict(zipBytes=len(blob),sha256=hashlib.sha256(blob).hexdigest(),installed=False,demo=snapshot is None)))
