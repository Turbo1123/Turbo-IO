# Norman IO → Hermes 桥接

## 电脑任务模式（v2）

IO 使用独立的真实 Hermes 会话，复用本机模型、人设、记忆配置、技能及 WhatsApp 的有效工具集合。通过官方 TUI gateway 的私有 stdio 连接调用工具，不接管 WhatsApp 对话，也不修改其配对。已在 Hermes 0.18.2（upstream `7b5ba205`）验证。

已有桥接状态无需重新初始化。先正常退出旧的 IO bridge，再从仓库根目录启动：

```sh
node agent-bridge/server.mjs --tasks --python "$HOME/.hermes/hermes-agent/venv/bin/python" --workspace "$PWD"
```

默认仍为 `127.0.0.1:8788`；沿用原独立令牌和 Tailscale HTTPS 8443 地址。新安装才需要先执行下面旧版章节的 `--init`。不要在旧进程仍运行时移除运行锁。

手机安装任务版后，在“会话 → 模型设置”选择 Hermes，点击“检查已保存的桥接”。首次初始化工具可能需要数十秒。文字提交或用“小雷小雷”/旋钮唤醒后说任务，手机任务卡显示状态、工具进度和结果；“Hey Norman”切换仍未实现。

普通文件操作、终端命令及已配置工具可以真实执行。依赖 WhatsApp 渠道上下文的功能不伪造渠道身份；应用控制还取决于电脑已有工具和系统权限。长期记忆复用同一配置，外部记忆服务原有的渠道隔离策略仍适用。

### 生命周期与恢复

- 接收后立即回执，电脑任务没有旧版 25/30 秒总时限。Mac、桥接和网络服务仍需保持运行。
- 手机息屏、离开页面、结束收音只影响展示，不能代替“停止电脑任务”。回到 App 可核对同一任务。
- 最后一段正文不等于执行结束；桥接等 Hermes 的运行线程退出才显示终态。
- 明确停止先显示“正在停止”，收到实际退出证据后才确认。停止本轮不会回滚已经产生的操作，也不意味着终止用户另行要求创建的后台服务。
- iPhone 的端点绑定任务编号保存在 App 私有目录，文件和目录同步后才提交请求/确认；不保存模型密钥。原地址的令牌可以修正，同时保留任务编号。
- Mac 的 `task-ledger-v2.json` 只登记 ID、摘要哈希、会话归属及状态，权限 0600；完整对话由 Hermes 正常保存。重启后从专用 IO 会话找回已完成结果，不重放原操作。
- 无法证明执行结果时显示“待核对”。只有用户在电脑检查后，才能解除重启遗留的占用。未收到任何回执的请求也保留编号，可明确停止以阻止迟到提交。

同时只执行一项 IO 任务；已有任务时新语音不会另建任务，手机可以回答明确追问。审批只提供本次允许/拒绝，绑定当前任务及具体请求；语音、模型正文和重复请求不能批准操作。密码、sudo 和登录由用户在 Mac 处理，此入口不收集这些信息。

### v2 API

全部要求原独立 Bearer 令牌，拒绝浏览器 Origin，不允许任意 RPC 或客户端指定工作目录/模型/凭据。

- `GET /v2/health?conversationId=<UUID>`：创建或恢复该 IO 会话，实际检查初始化；返回 `{ok:true,agent:"hermes",mode:"tasks",protocolVersion:2,ready:true}`。
- `POST /v2/tasks`：`{requestId,conversationId,text}`，文本最多 8192 UTF-8 字节。
- `GET /v2/tasks/:requestId`：状态快照。
- `POST /v2/tasks/:requestId/stop`：`{conversationId}`。
- `POST /v2/tasks/:requestId/decision`：`{conversationId,promptId,decisionId,choice:"once"|"deny"}`，或用 `text` 回答追问。
- `POST /v2/tasks/:requestId/acknowledge`：`{conversationId}`，仅用于用户明确核对过的重启遗留不确定任务，不停止或重放任务。

快照含 `requestId,conversationId,status,answer,summary,revision,prompt`；状态为 running/waiting/stopping/completed/failed/cancelled/unknown。`prompt` 为 null 或 `{id,kind,title,options}`。回答最多 32768 UTF-8 字节；眼镜使用更短的显示预算。最多保留 512 个请求登记、16 个 IO 会话、每任务 128 个确认记录，登记文件读写上限统一为 16 MiB，达到容量会明确拒绝。

恢复时的聊天展示按 JSON 编码大小保留不超过 512 KiB 的最新完整消息，不裁剪 Hermes 实际使用的模型历史。旧任务的标记或完整结果不在展示范围时，仍保留已登记的终态，正文可能为空；不会用其他轮的回答替代。停止请求失败时可以点击“再次请求停止”；收到确认前仍显示“正在停止”。

任务模式拒绝旧 `/v1` 请求，防止旧版“仅对话”客户端无提示地获得工具能力。适配器对安装版本做结构兼容检查；Hermes 升级后需要重新验证，不能把健康检查当作所有工具的验收。

### 验证

```sh
sh scripts/run_hermes_tasks.sh
```

自动测试使用隔离夹具，不读取实际模型配置或发送消息。真实验收脚本和结果保存在本次 `artifacts/hermes-tasks/`，只对仓库测试目录执行了文件与前台进程操作。

## 旧版仅对话模式（v1，保留兼容）

使用本机已安装的 Hermes，读取它的模型配置、SOUL 人设及已启用的内置 MEMORY / USER 记忆。已在 Hermes 0.18.2（upstream `7b5ba205`）验证。没有安装另一套模型配置或复用 DeepSeek 的人设冒充 Hermes。

目前仅支持 macOS。工具、MCP、项目插件、外部记忆插件及记忆写入均关闭；普通回答可使用已有内置记忆。桥接不操作文件、不发消息、不接管桌面现有会话。新对话的最近三轮保存在内存，Mac 桥接重启后清空。iPhone 现有对话时间轴仍按 App 原有设置保存本机对话。

## 启动

从仓库根目录执行，使用 Hermes 安装自带的 Python，不安装全局依赖。把 Python 路径替换为自己的实际路径。

```sh
node agent-bridge/server.mjs --init
node agent-bridge/server.mjs --python /absolute/path/to/hermes-agent/venv/bin/python
```

初始化只执行一次，新建 `.private/agent-bridge/`（0700），其中 `bridge.token` 为独立随机令牌（0600），不会打印。重复初始化拒绝覆盖；不要将令牌发到聊天、提交 Git 或填进模型供应商网站。已有 Hermes 凭据由 Hermes 自身加载，桥接不显示或复制它们。

默认只监听 `127.0.0.1:8788`。另开终端启用 Tailscale Serve：

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=8443 http://127.0.0.1:8788
```

首次需在 Tailscale 管理页登录并启用 Serve/HTTPS。使用命令返回的完整 `https://<机器名>.<tailnet>.ts.net:8443` 地址。iPhone 和 Mac 需在同一可互通的 Tailscale 网络中，且 Mac 保持运行。该命令以前台方式运行，退出即停止本次转发；没有启用公网 Funnel，也没有安装开机服务。

## iPhone

1. 在“会话”页关闭待命，并结束当前文字提问。
2. 在回答后端中选择 Hermes，打开 Hermes 配置。
3. 填入 Tailscale 返回的 HTTPS 根地址，以及本机 `bridge.token` 的内容，保存并检查连接。
4. 先使用文字入口验证两轮对话，再开启眼镜语音待命，用“小雷小雷”或旋钮唤醒。

令牌按 HTTPS 地址分别保存在 iPhone Keychain；更换地址不会自动把旧令牌发往新主机。没有 ASR 配置或没有连接眼镜，也能进行文字提问。待命或任务运行时不能切换后端。

当前手动选择 Hermes 后，会继续使用 Hermes，直到关闭待命并主动改回 DeepSeek。`Hey Norman` 语音切换尚未实现。首版 Hermes 回答完成后显示，不把工具日志伪装成流式正文。

## API 和限制

所有路由都要求 `Authorization: Bearer <独立令牌>`，拒绝浏览器 Origin，不允许客户端指定 shell、工作目录、供应商或任意远端 URL。

- `GET /v1/health`：接口版本及固定能力标签，不调用模型。
- `POST /v1/tasks`：`{agent:"hermes",workspaceId:"conversation",requestId,conversationId,text,mode:"read-only"}`。
- `GET /v1/tasks/:requestId`：累计回答与状态快照。
- `POST /v1/tasks/:requestId/stop`：`{conversationId}`。

两个 ID 都是客户端生成的小写 UUID。回复包含 `taskId`、`requestId`、`conversationId`、`agent`、`status`、`answer`、`revision`、`summary`、`updatedAt` 及 `approval:null`。taskId 与 requestId 相等。

停止未知 ID 会先建立取消记录，后来的 POST 不会启动任务。确认停止前等待工作进程退出。停止时已经完成的任务仍可返回 completed；iPhone 丢弃该轮迟到的文字。网络中断导致停止无法确认时，iPhone 明确提示未知状态，Mac 最长 30 秒终止该次工作进程。

一次仅运行一个模型任务；最多八个内存对话、128 个请求记录；输入/输出各最多 8192 UTF-8 字节。iPhone 等待上限为 25 秒。达到限制时失败，不自动切换模型。`task-ledger.json` 只保存 ID，不保存提示词、回答或令牌；服务重启后，旧 ID 的重新提交返回 `delivery_unknown`，不会自动重放。

当前 App 每次重新打开、重新保存 Hermes 配置都会创建新的会话 ID，首次提问时占用一个会话名额。这是本轮原型的容量限制，尚未加入自动回收或长期会话管理。

工作进程的 macOS 沙箱只允许写入新建的私有 worker 目录，只允许执行选定的 Python；没有修改 Hermes 的文件或安全设置。Hermes 日志及 JSON 会话快照被关闭，外部 ACP/Codex app-server 模型传输不受支持。若 Hermes 升级改变接口或底层凭据需要写入刷新，受限入口可能失败；需要先在正常 Hermes 中完成维护，再重新验证桥接。

正常停止桥接使用所在终端的 Ctrl+C，它会停止当前模型并清除运行锁。若异常退出留下 `running.lock`，先确认该 bridge 和 worker 进程均已停止，再移除这次运行锁；不要在进程仍运行时强行重启第二个服务。达到请求记录上限后也应停止并核对状态，再由操作者归档旧账本、开启新的桥接会话。

## 测试

```sh
node --test agent-bridge/*.test.mjs
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s agent-bridge -p test_worker.py
xcrun swift test --package-path rayneo-session --scratch-path artifacts/hermes-integration/swift-build
```

Node 沙箱测试需要 macOS；Python 单元测试仅使用标准库，不读取实际 Hermes 配置或调用云模型。测试临时文件均在仓库 artifacts 下。
