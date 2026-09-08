# 从源码配置与启动

## 1. 选择正确的入口

- 只看 UI、本机文件/待办/书库与逻辑：本地版，不需要眼镜、云 Key 或厂商 framework。
- 连接真实眼镜：设备版，使用现有通信依赖、自己的 Apple 签名和设备。当前不是从零自主重写的 SDK。
- 不提供 IPA、预签名 App 或开发者密钥。每位使用者自行配置与编译。

先安装/配置 Xcode、XcodeGen、Node.js，并在 Xcode 准备一个可用 iOS 模拟器。App 最低部署 iOS 16；工具链需满足各 Package.swift，自主传输包要求 Swift 6.2+。Node 需支持 fetch、ESM 和 node:test，尚未定义经过完整验证的最低版本。

本次验证使用 Xcode 27.0、XcodeGen 2.45.4、Node.js 26.3.0。系统开发工具不作为源码附件分发；厂商 framework、Opus、VAD 和 ZIPFoundation 均已提供。Codex / 其他 Agent 运行环境及 USB 观察需要的 iproxy 是按需安装的外部工具，不属于 App 编译依赖。

## 2. 本地版启动

在源码根目录执行：

```sh
node scripts/start.mjs --local
```

脚本检查工具、使用 `apps/RayNeoCompanion/project-source.yml` 生成工程并打开 Xcode；选择 `RayNeoCompanion` 和模拟器，点击 Run。公开交付中 ZIPFoundation 0.9.20 已附带为本地源码依赖，不需要另行下载。脚本不自动安装到手机、不配对、不读系统提醒事项，也不调用模型。

命令行构建：

```sh
xcodegen generate --spec apps/RayNeoCompanion/project-source.yml
xcodebuild -project apps/RayNeoCompanion/RayNeoCompanion.xcodeproj \
  -scheme RayNeoCompanion -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath apps/RayNeoCompanion/build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

保留 ad-hoc 签名用于实际 Keychain 运行；`CODE_SIGNING_ALLOWED=NO` 仅适合编译检查，不代表钥匙串正常。不要用模拟器状态演示冒充连接成功。

## 3. 设备版依赖与签名

设备构建配置为 `project-device.yml`（研究工作区原配置名为 `project.yml`），复用 `core-probe/Sources`。本次源码交付附带下列现有编译依赖，逐文件哈希见根目录 `DEPENDENCIES.json`：

| 路径 | 作用 |
| --- | --- |
| `core-probe/Frameworks/RayneoNet.framework` | 厂商通信核心 |
| 同目录 CocoaAsyncSocket / OpenSSL / RayneoLog / SwiftProtobuf / CocoaLumberjack / SSZipArchive framework | 匹配的运行依赖 |
| `core-probe/RecoveredInterface/RayneoNet.swift` | 恢复的声明源码；启动脚本用本机工具链生成仅声明的 swiftmodule，不编译/链接占位实现 |
| `core-probe/Vendor/opus-ios/libopus.a` 与 opus-1.5.2/include | Opus 解码依赖 |
| `core-probe/Vendor/py-webrtcvad-2.0.10/cbits` | 本地 VAD C 源码与头文件 |
| 各第三方 COPYING / LICENSE | 原归属与许可，不受本项目 MIT 覆盖 |

不要从不明来源随意下载同名库，不要假定别的版本 ABI 相同。缺依赖时启动脚本列出准确缺项并退出，不用空文件伪造成功。

```sh
node scripts/start.mjs --device
```

在 Xcode 选择 `RayNeoCompanionDevice`、自己的 Signing Team 与明确的 iPhone，运行。Bundle ID 默认 `io.turboio.companion`；自己的项目若需改 ID，应同步所有相关配置并理解数据/钥匙串/绑定隔离影响。已有安装升级时不随意改 ID 或卸载。

公开版使用中性的 Bundle ID 与服务命名空间，与维护者原测试安装隔离；不会自动读取原测试 App 的钥匙串。自行签名时应选择自己可用的标识符。不要在两个不同客户端之间复制绑定数据库。

配对前确认眼镜当前归属；已有绑定优先重连，不重置。新配对按设备实际步骤进入蓝灯闪烁状态，选择目标并确认系统提示，等待 App“已认证”。当前研究测试机已越狱；普通签名及公共 API 不替代非越狱设备专门验收。

## 4. 云对话：只填自己的服务

真机打开“会话 → 模型设置 / 配置 ASR 和模型密钥”：

1. 填自己的阿里云 ASR Host，只填主机名，不带 `https://`、端口、路径、用户名或查询参数。当前只允许 aliyuncs.com 子域，并要求服务支持 DashScope WebSocket 流式任务协议。
2. 服务端应提供 `qwen-audio-3.0-asr-flash-streaming`。音频为 16 kHz、mono、PCM16，使用云端 VAD；换模型/协议不是只改密钥就可兼容。
3. 填 ASR API Key 与 DeepSeek API Key。Key 仅进入自己的 App Keychain，不写源码或环境脚本。
4. 当前 DeepSeek 执行器使用固定官方 HTTPS chat/completions、`deepseek-v4-flash`、关闭思考、stream=true、max_tokens=1024。其他模型草稿页不替换该执行器。
5. 选择仅保存，或明确启用默认待命/持续插话。连接后说一条短句，核对 ASR 与回答；不以设置保存成功为接口验收。

源码不带开发者默认 ASR 租户。缺 Host/Key 时不会自动云收音；更换 Host 使用独立服务 Keychain 标识，不沿用旧主机密钥。已有测试安装升级到此配置版，需要先填写自己的 Host；填回原 Host 可按原 service 找到已有钥匙串内容，不删除旧 Key。

普通录音手动 ASR 共用这个用户配置，并在开始时捕获 Host 与对应 Key，避免解码期间改配置把旧 Key 发给新地址。录音不会因为接收到文件就自动转写。

## 5. 天气、通知、录音

- 天气：工具中填写自己的和风 Host / Key、城市；先查询并确认镜片候选图标，再启用已验图标自动下发。首页天气与卡片是不同业务。
- 系统通知：系统蓝牙配件设置允许共享通知；App 通知中心设置来源。自定义通知使用业务通道，可手动发送随机码，不需要制造手机系统通知。
- 录音：先开启眼镜录音接收，再在眼镜录制/保存；接收开关当前重开后需复核。录音归档中手动转写、分享；系统分享完整流程仍有待验项。
- 待办：本机编辑/发送可用，但眼镜完成未同步 App 是已知问题，不要重复下发旧未完成状态覆盖眼镜。
- NAS/Obsidian：当前先导出音频/Markdown/ZIP，没有配置即自动上传和远端索引承诺。

## 6. Codex bridge（可选）

电脑需要已有可用 Codex 登录和兼容 app-server。此项目启动独立子进程，不控制当前桌面聊天。可通过 `RAYNEO_CODEX_BINARY` 指定 binary 路径，当前桥接使用已验的 `--stdio` 参数，版本升级需核对 CLI/schema。

在私有路径创建随机令牌文件（32–256 位 Base64URL，权限0600），不要复用云服务密钥或把令牌放命令行。运行：

```sh
node codex-bridge/bridge.mjs \
  --workspace /absolute/your/allowed/project \
  --token-file /absolute/private/token-file \
  --state-file /absolute/private/ledger.json
```

默认 `127.0.0.1:8787`、只读工作区。供 iPhone 访问时使用自己的可信 HTTPS 代理，或提供 `--tls-cert` / `--tls-key`；非回环监听要求 TLS。手机保存 HTTPS 根地址（无 `/v1` 后缀）与独立令牌，检查连接，然后按需允许语音工具和主动提醒。初次联调先用不读写文件的随机码任务。

| 接口 | 用途 |
| --- | --- |
| GET /v1/state | 状态、任务和事件 |
| POST /v1/message | requestId、text、可选taskId；返回accepted不等于完成 |
| POST /v1/stop | requestId、taskId；请求停止 |
| POST /v1/decision | requestId、taskId、approvalId及decision/answers；用户手机确认 |

所有请求 Bearer 授权，POST JSON。模型仅有 message/status/stop 三个工具，不能自动审批。写权限只在主机用户明确选择 `--allow-workspace-write` 时增加。请求结果不确定不要换 requestId 重发。

主动提醒是 App 运行时轮询和眼镜通知，不是 APNs；强退、挂起、长期离线不能保证送达。不要直接裸露 app-server 或把 bridge token 放网页。

## 7. USB 显示观察（可选）

Mac 配好 iproxy，USB 连接可信手机：

```sh
node display-observer/server.mjs --udid YOUR_TEST_DEVICE_UDID
```

手机“工具 → 显示观察”开启本轮接口，浏览器打开 `http://127.0.0.1:8790/`，填本轮临时令牌。默认不含文字，单独同意才观察新发生文字；30分钟到期，需重新开启。Mac8790 / 转发18766 / 手机18765均为回环地址，别对外暴露。

这是页面/状态重绘，不是镜片像素截图。切样式不会控制眼镜；停止时清除内存，不伪造实时状态。

## 8. 检查

```sh
node scripts/check-source.mjs
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
```

源码扫描不等于完整安全/许可审计；运行后生成的本地构建和数据不用于发布。App 单元/UI测试使用自己已有的模拟器与新 xcresult 路径。非越狱、后台、声学效果与镜片操作需要另做实际验收。
