# Turbo IO 开发者生态：你的 Server，你的眼镜应用

2026-09-26 · 面向开发者，非商业研究。无需作者服务器、账号或 Key。

## 先看架构和交付边界

**用户自己的 Server 运行 MCP 客户端，连接用户授权的数据源；Turbo IO
SDK 把选定字段转换成卡片或应用；手机负责确认和蓝牙传输；眼镜只显示
原生有界组件。MCP 不在眼镜上运行。**

| | 仪表盘 SDK | 小应用 SDK |
| --- | --- | --- |
| 使用位置 | 桌面卡片 | “我的应用”菜单，四个槽位 |
| 协议/运行时 | TCE1 | TAP1 / TAX1 |
| 显示区域 | 256×194，四边6px安全区 | 540×180 |
| 组件 | 文本、图标、图片、进度条、柱图、折线、线、框 | 文本、图片、按钮、进度条、框 |
| 更新方式 | API 草稿、数据更新、发布、手机批准和回执 | Server 生成版本化 ZIP；手机导入预览后确认安装 |
| 运行方式 | 静态卡片 | 最多4页，单实例，切页/退出 |
| 目前未提供 | 自动订阅、自动队列恢复 | 自动后台数据刷新、按钮到 Server 的事件回流、JS/HTML执行 |

**兼容前提不能省略：** 手机必须包含对应的编辑器/App SDK 桥，眼镜必须
安装兼容的 TCE1/TAP1 研究运行时。原厂固件和较早 FOCUS-04 不自动获得这些
能力。私用 TAP1 SPACEFIX-01 的应用安装已有用户真机反馈通过；本次新模板
仍需分别真机验收。公开发行的配套完整构建/固件不能仅凭此教程视为已发布。
未具备运行时也可完成 Server、ZIP、SVG 和模拟器开发。不要因此直接刷未知包。

## 1. 十分钟离线入门

从仓库根目录开始，需要 Python 3.11+、uv；JS 示例另需 Node.js。

```sh
cd dashboard-service
uv sync --locked
mkdir -p .state/demo
uv run turbo-app gallery list
uv run turbo-app gallery build city_weather --out .state/demo/weather.zip
uv run turbo-app check .state/demo/weather.zip
uv run turbo-app preview .state/demo/weather.zip --page home --out .state/demo/weather.svg
```

这个 ZIP 可以在兼容研究版手机里导入，但显示的是明确标注的离线示例。
不需要任何第三方凭据；不会调用 MCP、自动刷机或安装。输出文件已存在会拒绝覆盖。

手机：**首页 → 应用广场 → 我的应用 → 导入应用 ZIP**。查看每页、权限和
哈希，查询当前眼镜槽位，让眼镜回首页后确认安装。相同 ID 的更新必须提高
version；最多四槽。安装成功后从手机打开，或在眼镜“我的应用”中选择。

## 2. 给 Agent 一行 Skill

审阅仓库源码后，在自己的开发电脑执行：

```sh
npx skills add Turbo1123/Turbo-IO --skill turboio-developer -g
```

选择 Codex / Claude Code 等实际使用的 Agent。该命令仅安装开发技能，不会
部署 Server、授权外部 MCP 或刷眼镜。发布前本地可用：
`npx skills add /absolute/path/to/Turbo-IO --skill turboio-developer -g`。
已安装旧版的用户需要更新 Skill；不要把旧 `turbo-io` 安装/协议技能误认为
本次专门的开发技能。

然后粘贴：

> 使用 $turboio-developer 为我做一个通勤应用。MCP 在我自己的 Server 上。
> 先用 commute 模板生成可验证的离线 ZIP，再询问必要的地图授权和起终点。
> 获取真实数据后，只转换我选择的展示字段，提供 ZIP、SHA256、预览和测试。
> 不自动安装、不刷机，不把密钥放进包或仓库。

App 每个模板也有“复制 Agent 开发提示词”；开发指南中能复制通用任务。
Skill 正文：[skills/turboio-developer](../skills/turboio-developer/SKILL.md)。

## 3. 自己的 Server 如何接 MCP

1. 在用户自己的 Server 上安装所选 MCP 服务/客户端，按**上游当前文档**授权。
2. 调用 `tools/list`，核对真实工具名、参数和权限；不要从示例猜接口名称。
3. 白名单选用只读工具。查询天气、行程、笔记等需要相应位置或账号授权。
4. 把 MCP 的结构化数据或文字结果转成下面的**展示快照**。不要直接把整段
   MCP 返回、工具描述、HTML 或第三方指令塞进应用，也不要执行其中的指令。
5. 缺字段显示“暂无数据”；记录来源时间。不要把缓存当实时结果。

`snapshot.json` 只允许三个字段，拒绝多余字段，避免整个认证响应误入包：

```json
{
  "headline": "北京天气 · 百度地图",
  "lines": ["晴 26°C", "湿度 40%", "东北风 2 级"],
  "observedAt": "2026-09-26T13:00:00+08:00"
}
```

1–4 行，每个字符串最多80 UTF-8字节，不允许控制字符；时间必须带时区。
示例时间/数据需换成用户 Server 的实际结果。构建为高版本包：

```sh
uv run turbo-app gallery build city_weather --data snapshot.json --version 2 --out .state/demo/weather-v2.zip
uv run turbo-app check .state/demo/weather-v2.zip
```

**首次是静态快照，不是持续推送。** 再次更新提高版本并导入新包。高频
动态场景需后续实现事件/数据通道，不应定时重装 ZIP；地图逐秒导航仍应使用
现有专用导航应用，不能把这个模板描述成实时导航替代品。

## 4. 独立后端 API / Python SDK / MCP

在 `dashboard-service/`：

```sh
mkdir -p .state
uv run turbo-dashboard grant --role writer --device my_glasses --out .state/writer.token
uv run turbo-dashboard grant --role phone --device my_glasses --out .state/phone.token
uv run turbo-dashboard serve
```

默认只监听 `127.0.0.1:18796`。远程手机访问须自行设置 HTTPS 反向代理及
访问控制，不关闭证书校验，不把此开发服务直接暴露公网。Token 在本地文件
0600保存，数据库存哈希；目前无完整多用户/撤销界面。只给模型 writer/reader，
phone Token 留给手机确认端。凭据用本地文件或 Secret Manager，不发聊天。

新增接口（除 `/health` 外均需 Bearer Token）：

| 接口 | 输入 | 返回 |
| --- | --- | --- |
| GET `/v1/apps/gallery` | 无 | 20项目录、提示词、哈希；不是在线 MCP 状态 |
| POST `/v1/apps/package` | `document`，writer | 已校验 ZIP Base64、SHA256、大小 |
| POST `/v1/apps/gallery/{id}/package` | `snapshot`、`version`，writer | 用模板渲染的 ZIP；snapshot=null为离线演示 |
| POST `/v1/apps/validate` | `document` | 预算校验 |
| POST `/v1/apps/package/validate` | `zipBase64` | ZIP完整性、格式与预算 |

请求上限32KiB；JSON包接近上限时用本机 CLI。API不声称已连接或安装眼镜。
`health/capabilities` 的连接标记不是对你私人眼镜的远程探测。

Python（Server 获取 MCP 结果后调用；本例读取映射好的 snapshot.json）：

```python
import base64, hashlib, json, os
from pathlib import Path
from turbo_dashboard.client import Client

client = Client(os.getenv("TURBOIO_API_URL", "http://127.0.0.1:18796"),
                Path(os.environ["TURBOIO_TOKEN_FILE"]).read_text().strip())
try:
    snapshot = json.loads(Path("snapshot.json").read_text())
    result = client.app_snapshot("city_weather", snapshot, version=2)
    raw = base64.b64decode(result["zipBase64"], validate=True)
    assert hashlib.sha256(raw).hexdigest() == result["sha256"]
    with open("weather-v2.zip", "xb") as f:
        f.write(raw)
finally:
    client.close()
```

MCP配置示例，替换绝对路径，由用户确认后添加：

```json
{
  "mcpServers": {
    "turboio": {
      "command": "/absolute/Turbo-IO/dashboard-service/.venv/bin/turbo-dashboard-mcp",
      "env": {
        "TURBOIO_API_URL": "http://127.0.0.1:18796",
        "TURBOIO_TOKEN_FILE": "/absolute/Turbo-IO/dashboard-service/.state/writer.token"
      }
    }
  }
}
```

12个工具：`capabilities/cards/card_get/card_validate/card_save/card_update_data/`
`card_request_publish/delivery_status/app_validate/app_gallery/app_build_package/app_build_snapshot`。
这套 MCP 是你自己的 SDK 服务，与上游数据源 MCP 分开；应用快照工具不帮你
暗中获取账号、部署第三方 Server 或调用任意工具。

## 5. 仪表盘完整流程

模板、字段与所有 API 见 [服务 README](../dashboard-service/README.md)；
机器可读 Schema：[card.schema.json](../dashboard-service/turbo_dashboard/card.schema.json)。

最小卡片（`card.json`）：

```json
{"schema":1,"id":"turbo_ui_card_weather","name":"天气卡片","components":[
  {"id":"title","kind":"text","x":8,"y":8,"w":232,"h":28,"text":"北京 · 晴 26°C","font":24,"align":"left"},
  {"id":"humidity","kind":"progress","x":8,"y":48,"w":232,"h":8,"value":40},
  {"id":"note","kind":"text","x":8,"y":72,"w":232,"h":24,"text":"湿度 40% · 数据快照","font":18,"align":"left"}
]}
```

`client.save(document, expected_revision=0)` 创建；返回 `revision/hash`。
用最新 revision 调用 `client.update(id, {"title":{"text":"北京 · 多云"}}, revision)`，
仅更新数据，不改几何。修改布局需重新 save。409 冲突先读取最新草稿，不强盖。

用户确认后 `client.publish(id, revision, hash, idempotency_key)` 得到 job。
手机「仪表盘 → 数据源」绑定同 device 的 phone Token，刷新任务、查看快照、
确认发送。查看 `client.job(job_id)`：`awaiting_phone_approval → sending →
device_accepted/failed/outcome_unknown`。接收回执不等于看见了像素；未知结果
先回读核对，禁止盲目重试。Server 不代替手机批准。

预算：最多12组件、4图标/图片、2图表；文档≤6000字节，wire≤2048字节；
坐标为偶数、x/y≥6、x+w≤250、y+h≤188。字体14/16/18/20/24/28；
图标/图片16/24/32/48正方形；总像素缓冲≤32768字节，不含全部LVGL堆。
两种 SDK 的尺寸和图标格式不能混用。

## 6. 从零编写应用、图标、ZIP

JS 是**开发电脑的构建语言**，不是眼镜脚本运行时：

```sh
node examples/tasks.mjs --out .state/demo/tasks.json
uv run turbo-app build .state/demo/tasks.json --out .state/demo/tasks.zip
uv run turbo-app check .state/demo/tasks.zip
uv run turbo-app preview .state/demo/tasks.zip --page home --out .state/demo/tasks.svg
```

该任务示例包含 `backend.events` 声明，用于展示协议语法；按钮事件尚无
端到端 Server 回流，不能当成“点击已修改待办”。纯演示模板都不申请此权限。

ZIP根目录必须**仅有** `app.json` 和 `manifest.json`。不要手工 zip 一个文件夹；
打包器生成规范化JSON、manifest SHA256、固定ZIP元数据。限制：

- schema=1，ID `[a-z][a-z0-9_]{0,23}`，version 1–65535；同ID升级严格递增。
- 解压两个文件总计≤20,480字节，ZIP≤24,576字节；最多4页、每页12组件。
- 文本≤96 UTF-8字节；字体14/16/18/20/24/28；文本高度≥font+4。
- 图片资源最多8项，原生8–128px、宽8倍数，`mono1-msb` 行对齐：每字节
  bit7是最左像素，1亮0暗，Base64；图片组件尺寸必须等于资源尺寸。
- 图片单页解码预算≤32KiB；框、进度条、文本与图片之外不支持任意绘图。
- 按钮只允许page/exit/emit；无网络、麦克风、文件路径或可执行代码。
- 拒绝多余文件、路径穿越、符号链接、加密成员、重复项、哈希或预算不符。

资产必须原创或有分发许可。手机压缩、裁剪后再单色化；不要把彩色PNG/JPEG
直接放ZIP。图库提供原创48px几何图标，手机显示使用系统图标，未复制上游商标。

## 7. GitHub 分发与社区提交

运行 `uv run turbo-app gallery export --out .state/gallery` 可生成目录、20份ZIP、
原始JSON及每项提示词。官方内置目录在 [app-gallery](../app-gallery/README.md)。
首版直接随手机打包，离线可浏览；**不自动联网下载或执行远程包**。

社区可在自己GitHub仓库或Release发布：源码、ZIP、SHA256、预览、版本、许可、
所需运行时与测试记录。小型公开目录可存Git；版本化ZIP可用Release assets，
客户端应固定commit/tag而非静默跟随main，并验证大小、SHA256及完整包后让用户确认。
个人日程、位置、笔记、MCP凭据、Cookie、Token绝不能发布到公共GitHub。
本版不提供公开包托管的鉴权代理，也不把目录看成可信任自动更新服务。

提交模板需包含来源、只读工具映射、空数据/错误/过期测试和最大长度样本，
不能夹带上游代码改许可证。第三方MCP各自遵守其许可证；这里只原创模板和引用。

## 8. 验收清单

```sh
uv run pytest -q
```

先校验20KiB、图片预算、重复ID、坏ZIP、字段映射；再查本机Server鉴权、
跨设备隔离、revision冲突；最后才用自己的手机/眼镜验证安装、返回、重启和内存。
Linux可跑Python/API测试，macOS专用Objective-C与模拟器测试需要Xcode。
构建成功、模拟器成功和真实眼镜成功必须分别标注，不用上游项目存在来证明已联网。
