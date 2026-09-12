# 可选：Codex 只读知识库参考服务

这是 V2 手机 `knowledge_query` / `knowledge_query_status` 的参考实现，不是 V1 `codex-bridge` 的即插即用替代。当前发布含合成测试；手机 HTTPS → Codex → 镜片完整链路尚未完成验收。不开启此功能不影响独立的模型/搜索配置。

## 安全默认值

- 服务只绑定 `127.0.0.1`，不自动建隧道，不开放原始 Codex RPC。
- 独立随机令牌，文件权限0600；所有业务路由先鉴权，拒绝浏览器 Origin、非预期路径及方法。
- 必须显式配置三类来源目录。初始目录为空，不自动扫描桌面、微信数据库、用户目录或维护者的知识库。
- Codex 以本机已配置的登录运行独立临时只读会话，限定检索工具和最多4次检索；不续写桌面开发会话，不执行资料中的指令。
- 默认关闭 shell、联网及其他集成，查询资料视为不可信数据。但 Codex 版本、机器全局配置会影响执行环境：**这不是隔离多租户或防恶意本机管理员的安全沙箱。** 应使用专用普通系统账户和只读资料副本，不用于不可信公网用户服务。
- 片段会发送给 Codex 对应的模型服务；答案和来源元数据交回手机自有模型。不是全本地推理，也不是全量微信实时覆盖。

## 启动

需要 Node.js 22.16+、已安装并登录的 Codex。接口来自 [Codex App Server 官方文档](https://learn.chatgpt.com/docs/app-server)：初始化、thread/start、turn/start、动态工具调用与 turn/completed。实验接口随版本变化；遇到模型/协议不匹配先检查当前 CLI 生成的 schema，不修改鉴权来强行通过。

```sh
node official-addon/knowledge-bridge/server.mjs --init /absolute/new-private-knowledge
```

在本机私有目录中编辑生成的 `config.json`：

- `command`：自己安装的 Codex 可执行文件绝对路径；默认给出 Mac 桌面应用的常见位置，路径存在不代表已登录或模型可用。
- `cwd`：专用空工作目录，避免加载不可信项目配置。
- `roots.projects`、`roots.learning`：自己授权的 Markdown 资料副本目录。
- `roots.wechat`：已自行归档的消息目录，格式如下。不读取实时微信库、不提供提取/解密程序。
- `directory`：私有查询任务目录。任务含问题、答案、来源摘要；不要提交或上传它。
- `tokenFile`：初始化生成的专用令牌；不要贴到 issue、聊天或命令参数里。

```sh
node official-addon/knowledge-bridge/server.mjs --config /absolute/new-private-knowledge/config.json
```

没有来源时返回空结果，不填充演示内容。启动仅监听本机，不会打开模型查询。用自己的受信任 HTTPS 反向代理/VPN TLS 服务连接手机；只转发 `/api/turbo-knowledge/`，保留 Bearer 鉴权，不将整个知识库目录或 Codex app-server 暴露到网络。

手机 **TurboIO → 模型 → 知识库与来源 → 连接配置** 填 `https://your-host.example/api/turbo-knowledge` 以及自己的专用令牌，再开启知识库工具。手机输入的 localhost 指向手机自己，不是 Mac。

## 支持的消息副本格式

```text
roots.wechat/
  run-20260901/
    report.json
    messages.jsonl
```

`report.json` 含 `status`（`completed`、`success` 或 `review`）及 `completedAt`（ISO 时间）；`messages.jsonl` 每行是具有 `content`、`conversation`、可选 `conversationName` / `senderName`、`createTime`（Unix秒/毫秒）的 JSON。格式不符会跳过，不推断源库。父目录可选 `preferences.json` 的 `ignoredConversations:[{id:...}]`，id 为 conversation 字符串 SHA256 前24位；损坏的偏好文件会阻止来源读取。

只扫描最近7个归档目录；读取有数量、大小、深度上限，索引缓存30秒。返回来源更新时间与覆盖提示；“没有命中”不等于事情不存在。它是关键词检索供 Codex 多次改写查询，不是向量数据库。

## API

每条请求都需要 `Authorization: Bearer <自己的令牌>`，以下只有结构，不是真实配置：

| 路由 | 用途 |
| --- | --- |
| GET `/api/turbo-knowledge/sources` | 来源可用性、数量、更新时间；不是 Codex 登录成功证明 |
| POST `/api/turbo-knowledge/query` | JSON `{query, source, requestId}`；source为all/wechat/projects/learning，requestId为随机UUID；返回202和任务编号 |
| GET `/api/turbo-knowledge/jobs/<id>` | queued/running/completed/failed/interrupted；完成时有answer、results和coverage |

请求体最大4096字节、问题2–200字、每分钟30请求、一个模型任务执行中最多排队3个。最多保留100个任务文件，到达上限拒绝新任务，不自动删除历史。重启遗留任务标为 interrupted，不自动重放。手机取消不代表撤销已经接受的 Mac 任务；超时应按原编号查结果，而非盲目重新创建。

目前没有 APNs、事件投递箱、多用户权限和通用写入 API。不要将“任务完成”视作眼镜已显示。Claude Code、Hermes、WorkBuddy、OpenClaw 的菜单项不调用这个 Codex 执行器冒充其他 Agent。

```sh
node --test official-addon/knowledge-bridge/turbo-knowledge.test.mjs
```

测试仅使用临时合成资料和 mock 执行器，不访问真实消息或调用付费模型。
