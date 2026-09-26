# 应用广场 · 20 个 MCP 小应用模板

2026-09-26。**MCP 在你的 Server 上运行；眼镜只显示有界原生组件。** 这些 ZIP 使用原创演示内容，不附带第三方服务代码、授权、账号或密钥。不是 20 个已经联网的成品 App。

手机入口：**TurboIO → 应用广场**，分为“我的应用 / 应用广场 / 开发指南”。每个模板都有预览、参考项目、配置要求、Agent 提示词和 ZIP 导出。已有四个基础示例继续保留。TAP1 眼镜最多安装四个应用，广场里的 20 个模板不等于安装了 20 个应用。

先看[完整开发指南](../docs/DEVELOPER_ECOSYSTEM.md)，将表格中的提示词复制给 Codex / Claude Code 等 Agent。上游项目来自 [awesome-china-mcp](https://github.com/zackchewa/awesome-china-mcp) 的发现线索，实际工具名称、字段、授权与许可证须以对应项目为准。我们不复制上游实现、不代理上游服务。

| 方向 | 可复制提示词与接入要求 | 离线 ZIP | MCP 参考项目 |
| --- | --- | --- | --- |
| 城市天气 | [说明](city_weather.md) | [下载](Gallery_city_weather.zip) | [百度地图](https://github.com/baidu-maps/mcp) |
| 降雨提醒 | [说明](rain_watch.md) | [下载](Gallery_rain_watch.zip) | [彩云天气](https://github.com/caiyunapp/mcp-caiyun-weather) |
| 通勤助手 | [说明](commute.md) | [下载](Gallery_commute.zip) | [百度地图](https://github.com/baidu-maps/mcp) |
| 附近好去处 | [说明](nearby.md) | [下载](Gallery_nearby.zip) | [百度地图](https://github.com/baidu-maps/mcp) |
| 道路路况 | [说明](traffic.md) | [下载](Gallery_traffic.zip) | [百度地图](https://github.com/baidu-maps/mcp) |
| 火车余票 | [说明](train_board.md) | [下载](Gallery_train_board.zip) | [12306](https://github.com/Joooook/12306-mcp) |
| 换乘方案 | [说明](train_transfer.md) | [下载](Gallery_train_transfer.zip) | [12306](https://github.com/Joooook/12306-mcp) |
| 航班动态 | [说明](flight_board.md) | [下载](Gallery_flight_board.zip) | [飞常准](https://github.com/variflight/variflight-mcp) |
| 今日日程 | [说明](calendar.md) | [下载](Gallery_calendar.zip) | [飞书](https://github.com/larksuite/lark-openapi-mcp) |
| 工作待办 | [说明](work_tasks.md) | [下载](Gallery_work_tasks.zip) | [飞书](https://github.com/larksuite/lark-openapi-mcp) |
| 知识便签 | [说明](knowledge.md) | [下载](Gallery_knowledge.zip) | [语雀](https://github.com/yuque/yuque-mcp-server) |
| 阅读摘记 | [说明](reading_notes.md) | [下载](Gallery_reading_notes.zip) | [微信读书](https://github.com/freestylefly/mcp-server-weread) |
| 视频速览 | [说明](video_digest.md) | [下载](Gallery_video_digest.zip) | [哔哩哔哩](https://github.com/huccihuang/bilibili-mcp-server) |
| 热点一览 | [说明](trending.md) | [下载](Gallery_trending.zip) | [微博](https://github.com/qinyuanpei/mcp-server-weibo) |
| 代码待办 | [说明](repo_tasks.md) | [下载](Gallery_repo_tasks.zip) | [Gitee](https://github.com/oschina/mcp-gitee) |
| 构建看板 | [说明](build_status.md) | [下载](Gallery_build_status.zip) | [阿里云效](https://github.com/aliyun/alibabacloud-devops-mcp-server) |
| 服务健康 | [说明](service_health.md) | [下载](Gallery_service_health.zip) | [阿里云可观测](https://github.com/aliyun/alibabacloud-observability-mcp-server) |
| 节假日日历 | [说明](holiday.md) | [下载](Gallery_holiday.zip) | [中国 MCP 服务](https://github.com/zackchewa/china-mcp-servers) |
| 资讯简报 | [说明](news_digest.md) | [下载](Gallery_news_digest.zip) | [博查搜索](https://github.com/BochaAI/bocha-search-mcp) |
| 餐品营养 | [说明](nutrition.md) | [下载](Gallery_nutrition.zip) | [麦当劳 MCP](https://github.com/M-China/mcd-mcp-server) |

## 从示例到真实数据

1. 在自己的 Server 部署所选 MCP，完成授权；查询 `tools/list`，选择只读工具，不默认开放付款、发消息、下单或运维操作。
2. 将授权结果提取成 `headline`、1–4 条 `lines`、带时区的 `observedAt`。每串最多 80 UTF-8 字节。只挑要展示的字段，不透传完整响应、Token、Cookie。
3. 运行 SDK：

```sh
cd dashboard-service
uv sync --locked
uv run turbo-app gallery build city_weather --data snapshot.json --version 2 --out my-weather.zip
uv run turbo-app check my-weather.zip
uv run turbo-app preview my-weather.zip --page home --out weather.svg
```

4. 手机导入 ZIP → 预览 → 查询眼镜槽位 → 确认安装。需要兼容的 TAP1 运行时；不是向旧固件直接发送 ZIP。相同 ID 更新必须增加 version。

当前是**手动安装快照**，并非后台实时订阅。阅读摘记不提供书籍全文，视频速览不播放视频，通勤不替代实时导航。来源 API 可能变更；模板不保证上游服务始终可用。

## 目录与可复现生成

[`catalog.json`](catalog.json) 包含模板 ID、相对资源名、ZIP 大小、SHA256、来源及提示词；同名 `.json` 是可编辑的 App 文档，`.md` 是提示词。图标为 SDK 自有的 48px 单色几何资源，手机列表另用系统图标，不附带平台商标。

重新生成到一个**新目录**：`uv run turbo-app gallery export --out /path/to/new-gallery`。生成器在 `dashboard-service/turbo_dashboard/gallery.py`。同源生成应产生相同哈希；20 个模板均通过 ZIP/Schema/原生编码和 C 内存检查。模拟器页面通过不代表各第三方服务的真机联网验收。

GitHub 可以托管无密钥的公共模板目录与小 ZIP；发布真实用户数据请用自己的受控 Server。手机本版使用内置目录，不会偷偷拉取并自动安装 GitHub 上的新代码。下载或更新时应固定版本、校验 SHA256、预览内容再批准。
