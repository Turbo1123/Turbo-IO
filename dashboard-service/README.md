# Turbo IO Developer SDK · 用户自托管后端

2026-09-26。独立、自托管，不依赖作者的服务、模型 Key 或项目管理系统。

**从这里开始：[完整开发指南](../docs/DEVELOPER_ECOSYSTEM.md) · [20 个 MCP 应用模板](../app-gallery/README.md) · [Agent Skill](../skills/turboio-developer/SKILL.md)。MCP 运行在用户自己的 Server，不在眼镜上运行。**

已有卡片 API / Python SDK / MCP、手机批准桥接及 JS → ZIP → 手机预览/安装协议 → AP 原生运行时。用户已验证私用 SPACEFIX-01 的基础小应用安装和启动；这不代表公开仓库的旧固件自动兼容 TAP1，也不代表第三方 MCP、后台刷新、按钮后端回流已全部验收。公开源码可独立构建和测试；真机须使用匹配 TCE1/TAP1 的手机与固件。下列测试边界不替代具体设备验收。

## 当前交付范围

| 模块 | 已实现 | 未完成 |
| --- | --- | --- |
| Dashboard API | 模板、Schema、校验、SVG 预览、草稿、revision、数据更新、不可变发布快照；iOS 前台手动桥接测试版 | API 到镜片完整联合验收、自动数据源订阅 |
| 通用服务 | SQLite、设备范围 Token、幂等键、过期状态、显式手机批准和回执 | 自动重试、队列恢复、Token 管理界面 |
| Python SDK / MCP / Skill | 共用 API；12 个 MCP 工具；可安装的仓库 Skill | 未自动配置任何 Agent 或第三方服务 |
| App 工具链 | JS 构建模板、两页任务示例、ZIP 校验、SVG 预览、原生记录编码 | JSX/HTML 语法、用户资源上传界面 |
| App 运行时 | 四槽双文件、单实例、TAP1/TAX1 协议；私用版基础安装启动经用户确认 | 公开完整运行时打包另行发布；真实掉电和全部模板实机验收 |
| App 手机 | 我的应用 / 应用广场 / 开发指南；4 个基础示例与 20 个 MCP 方向模板；ZIP 导入和安装协议 | 第三方服务由用户配置；后端事件回流、自动恢复未接入 |

## 本机启动 API

以下命令在本目录执行，需要 Python 3.11+ 和 `uv`。不会部署公网服务，不会连接手机或眼镜。

```sh
uv sync --locked
mkdir -p .state
uv run turbo-dashboard grant --role writer --device my_glasses --out .state/writer.token
uv run turbo-dashboard serve
```

服务默认 `http://127.0.0.1:18796`，只监听本机。Token 自动随机生成，写入权限 0600 的新文件，不在输出中显示。相同输出文件存在时拒绝覆盖。数据库只存 Token 哈希。另一个终端：

```sh
TURBOIO_TOKEN_FILE="$PWD/.state/writer.token" uv run python examples/backend_metrics.py
```

示例只把 CPU 演示数据写入草稿，**不读取你的真实账户，不自动发布**。后端作者可替换成自己的数据获取代码；无需把第三方 Key 发给眼镜。

权限分为 `reader`、`writer`、`phone`，每个 Token 只能操作其所属 device。Token 目前长效，本版尚无撤销命令和用户体系，仅用于单所有者本机预览。不要对公网裸露此服务；远程使用须由用户配置 HTTPS、访问控制和完整凭据管理。SDK 拒绝远程明文 HTTP、URL 内凭据及跨站重定向。

`GET /health` 不要求认证。其他接口包括 OpenAPI 均要求 `Authorization: Bearer <token>`；不通过查询参数传 Token。默认不输出 HTTP 访问日志；状态错误不回显用户文档或密钥。

## 仪表盘 API

| 方法/路径 | 用途 |
| --- | --- |
| `GET /v1/capabilities` | 卡片 Schema、模板与真实集成状态 |
| `GET /v1/identity` | 当前 Token 的 role / device；手机绑定时核验 |
| `POST /v1/cards/validate` | `{"document": …}`，返回字节/像素预算 |
| `POST /v1/cards/preview` | 同上，返回 SVG 布局预览 |
| `GET /v1/cards`、`GET /v1/cards/{id}` | 当前 Token 设备范围内草稿 |
| `PUT /v1/cards/{id}` | `expectedRevision` + `document`，新建为 revision 0 |
| `PATCH /v1/cards/{id}/data` | `expectedRevision` + `updates`，不能改位置或组件类型 |
| `POST /v1/cards/{id}/publish` | `revision`、`hash`、`idempotencyKey`、`ttlSeconds` |
| `GET /v1/jobs`、`GET /v1/jobs/{id}` | 查询真实阶段，不伪造已显示 |
| `POST /v1/phone/jobs/{id}/approve` | 手机角色确认 exact `hash`，获得一次 receiptToken |
| `POST /v1/phone/jobs/{id}/receipt` | 手机角色提交 receiptToken、state、code |

布局沿用现有 TCE1：256×194 内容区域，最多 12 组件、4 图片/图标、2 图表，图片像素预算 32 KiB。该预算不是全部 LVGL 内存。支持文字、图标、小图片、进度条、柱/折线、分隔线、边框。SVG 使用电脑字体，系统图标仅以编号方框标识；不是实际镜片截图。

`publish` 只进入 `awaiting_phone_approval`。通过手机预览并批准后才进入 `sending`。测试版手机经现有 TCE1 传输并读取配置后报告 `device_accepted`，不等于像素内容或用户视野已验证。当前测试回执来自模拟器，没有真实蓝牙验收；服务也不能凭源码存在判断手机在线。

### iOS 后端连接测试版

源码：`../official-addon/research/dashboard-editor-v1/EditorBackend*`。入口：**我的仪表盘 → 数据源**。

1. 用户在自己的 HTTPS 入口前配置受控访问；不把默认本机服务直接暴露公网。电脑端仍可通过回环 HTTP 调试，手机只接受 HTTPS，不忽略证书错误。
2. 为同一 device 单独签发 `phone` Token，模型仍用 `writer` / `reader`。手机配置时需连接目标眼镜，验证角色后把服务 device 绑定到这副眼镜。Token 仅存本机钥匙串。
3. 后端发布卡片后，在手机刷新任务、检查静态预览，并确认已经安装 **TCE1** 配套固件，再手动发送。旧 TDC1 不可替代 TCE1；此入口不会自动刷机。
4. 发送期间保持前台，禁止 OTA 会话并核对设备未变化。批准绑定预览 hash；拒绝重定向，网络响应限制128 KiB。结果未知或回执保存失败时不自动重发。

签发手机专用凭据（自行在本机读取并填入手机，不发送到聊天）：

```sh
uv run turbo-dashboard grant --role phone --device my_glasses --out .state/phone.token
```

首版每项快照都需要手机确认，**还不是自动后台刷新**。Token 撤销、App 被系统挂起后的任务恢复、自动订阅及密钥轮换工作流仍需完善。

任务默认不会自动重试。发送中超时变为 `outcome_unknown`，阻止下一项直到手机核对并完成回执。发布快照不随草稿后续修改而变化。重复幂等键+不同内容拒绝；旧 revision 拒绝覆盖。每设备草稿上限 128、任务记录上限 1000；达到后拒绝新增，不静默删除历史。

## MCP 与 Skill

MCP 固定使用 `mcp>=1.28,<2` 的 v1 SDK，依赖版本锁定于 `uv.lock`。本轮已用真实 stdio 初始化、列出工具及调用，访问本机临时 HTTP 服务；非设备测试。

配置由使用者主动添加到自己 Agent，示意如下（替换路径）：

```json
{
  "command": "/absolute/path/dashboard-service/.venv/bin/turbo-dashboard-mcp",
  "env": {
    "TURBOIO_API_URL": "http://127.0.0.1:18796",
    "TURBOIO_TOKEN_FILE": "/absolute/path/dashboard-service/.state/writer.token"
  }
}
```

只给模型 writer / reader Token，**不给 phone Token**。工具没有手机批准、任意蓝牙或刷固件入口。Skill 已迁移到仓库根目录的 `skills/turboio-developer/`，可用 `npx skills add Turbo1123/Turbo-IO --skill turboio-developer -g` 安装；这不等于完成蓝牙连接或公网服务部署。

### MCP 应用模板 → 自己的 Server → ZIP

```sh
uv run turbo-app gallery list
uv run turbo-app gallery prompt city_weather
uv run turbo-app gallery build city_weather --out weather-demo.zip
uv run turbo-app check weather-demo.zip
uv run turbo-app preview weather-demo.zip --page home --out weather.svg
```

20 个包都是原创、可安装的**离线示例**，不是 20 项已登录服务。复制提示词给 Agent，让它在自己的 Server 发现并调用授权的只读 MCP 工具，把结果映射为 `headline / lines / observedAt`，再用 `--data snapshot.json --version 2` 构建真实数据快照。凭据不进入 ZIP。ZIP 每次更新需递增 version、手机手动确认；不能用频繁重装冒充实时导航或音乐播放。

新增接口：`GET /v1/apps/gallery`（认证后读目录）、`POST /v1/apps/package`（writer 从 document 构建）、`POST /v1/apps/gallery/{id}/package`（writer 从 snapshot/version 构建）。返回 ZIP Base64、SHA256 和 `installed: false`，没有服务器直接安装眼镜的假接口。对应 MCP 工具：`app_gallery`、`app_build_package`、`app_build_snapshot`。

## App SDK：JS 模板 → ZIP

JS 仅在开发电脑构建时运行，只执行信任的源码。眼镜目标是原生渲染有界数据，不运行 Node、浏览器、DOM 或任意 JS。现阶段不是完整 HTML/JSX 框架。

```sh
mkdir -p .state/examples
node examples/tasks.mjs --out .state/examples/tasks.json
uv run turbo-app build .state/examples/tasks.json --out .state/examples/tasks.zip
uv run turbo-app check .state/examples/tasks.zip
uv run turbo-app preview .state/examples/tasks.zip --page home --out .state/examples/home.svg
```

输出必须是新文件，以免覆盖原作。模板提供两页任务列表、查看详情、退出及后端事件声明；演示事件目前只在主机状态模型中返回，不代表已送到业务后端。

包内只有 `app.json`、`manifest.json`，manifest 固定名称和 SHA256。总解压大小 ≤20,480 字节，ZIP ≤24,576 字节。资源为内联 `mono1-msb` 图片，不携带 API Key、Cookie、系统路径、可执行程序或脚本。拒绝未知文件、路径穿越、重复项、符号链接、加密压缩项、格式/尺寸/哈希不符。

应用当前支持：540×180，最多4页、每页12组件；文字、按钮、图片、进度条和边框；图片8–128像素且宽为8的倍数，单页解码图片≤32 KiB。声明式按钮动作只有切页、发事件、退出。长按是系统退出，触摸不是旋钮滚动。原生事件中的组件数字索引由手机用同一已验证包映射回稳定组件 ID 和事件名。

原生 `app_store` 提供最多4槽，每槽两份有界文件；版本递增、校验后切换、读取校验、运行中拒绝覆盖。`app_runner` 保持一个活动实例；渲染忙时保留缓冲，待渲染完成再清理。文件API/LVGL已接线编入TAP1候选；**模拟不代表真机持久化或掉电安全**。手机与Python的ZIP→TAP1/TAX1编码逐字节对照通过。

HTTP：`POST /v1/apps/validate` 接收 `document`；`POST /v1/apps/package/validate` 接收 `zipBase64`。这里只校验，不提供假装成功的安装接口。当前 JSON HTTP 请求总上限32 KiB，接近 ZIP 上限的 Base64 上传可能需使用本机 CLI，后续二进制上传接口另做。

## 测试与设备边界

```sh
uv run pytest -q
```

2026-09-26 本机 47 项测试通过，覆盖 API、隔离、并发、重复发布、超时、持久化、恶意包、JS 打包、HTTP/MCP stdio、Python/Objective-C 文档及编码一致性、原生 C ASan/UBSan。20 个模板共 40 页另做原生内存测试；UIKit 验证 12 个桥接场景、4 个基础示例、20 个模板预览与三分区。macOS 专用测试在其他平台会跳过；模拟不是蓝牙、掉电或所有上游服务的实机验收。

原生协议、包解码与内存测试源码位于 `../official-addon/research/app-runtime-v1/`。公开参考模块不是完整可刷 OTA，不附带硬编码私人配置或修改官方固件的自动命令。本轮只改手机应用广场与主机 SDK，没有刷写或改变 AP。

后续需完成 App 后端事件/字段回流、队列恢复，以及各用户自己服务器的授权与设备联合验收。`capabilities` 的物理标记不是设备探测结果，保持保守值；服务不能因代码存在就宣称手机在线。
