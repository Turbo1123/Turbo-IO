# Turbo IO

RayNeo iO 的自有 iOS 客户端：眼镜语音 → 自己的 ASR/模型，录音 → 本地归档与手动转写，Codex → 电脑任务与结果通知。

**发布源码与明确列出的构建依赖，不发布 IPA、预签名 App 或开发者服务密钥。用户自行配置、签名与编译。** 现阶段是研究驱动的开发版，不是所有设备/固件都已验收的通用 SDK。

> 本项目仅面向懂 iOS 开发、签名、API 配置与基本调试的技术用户，用于互操作研究。如果希望开箱即用、不熟悉这些操作，请使用官方 App。部分功能仍在验证，欢迎一起研究和补充实测，不承诺替代官方 App 的全部功能。

## 可以做什么

- 使用自己的服务完成眼镜语音识别、流式 AI 回答与会话内插话；保存聊天文字时间轴。
- 接收眼镜录音、保存本机，手动触发云端转写，导出音频与文字。
- 下发待办、提词器内容和天气；导入 TXT / EPUB 作为本地书稿。
- 发送自定义通知，把电脑任务结果主动推到眼镜。
- 以眼镜作为 Agent 的语音输入与结果显示入口。目前实际打通的是 **Codex**，其他 Agent 需要开发适配器，状态见下表。
- 通过 USB + Web 观察协议回报的页面/状态，辅助研究双向交互；这不是眼镜截图。

## Agent 接入：已实现与可扩展

| Agent | 当前状态 | 接入思路 |
| --- | --- | --- |
| Codex | 已实现，有眼镜发起任务、查询结果及完成通知的实测记录 | 手机工具调用 → 本项目 HTTP bridge → Codex app-server → 任务事件 → 眼镜 |
| Claude Code | 未实现适配、未测试 | 可研究通过 Claude Agent SDK 或 CLI 子进程实现电脑侧适配 |
| Hermes Agent | 未实现适配、未测试 | 可研究其程序化入口/消息网关，转换为手机侧统一任务与事件接口 |
| OpenClaw | 未实现适配、未测试 | 可研究 Gateway 协议适配，包括认证、任务、事件与权限处理 |
| WorkBuddy | 理论上可研究接入，未测试 | 需先确认其可用 API / 扩展或自动化入口，不能保证当前已有可用接口 |

扩展方向依据各项目公开入口提出，**不等于本仓库已经内置或验证这些适配**。参考：[Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview)、[Hermes Agent](https://github.com/NousResearch/hermes-agent)、[OpenClaw Gateway](https://docs.openclaw.ai/gateway/protocol)。各服务账号、权限、费用和适用条款由用户自行配置与确认；不能只把名称换成另一个 Agent 就直接运行。

## 不可以做什么

- **不能修改眼镜任何内置 UI 的布局、组件或模板，也不是刷机/自定义桌面工具。** 当前唯一开放的自定义 UI 入口是我们使用的通知 view，用来发自定义通知；不代表支持任意页面、HTML、Canvas 或第三方 App 渲染。
- 对话、待办、提词器、天气等可以修改或下发内容，但只能使用眼镜自带的 UI 模板，不能自由改变模板排版与交互。Web 预览样式也不会变成镜片固件 UI。
- **不能与官方 App 同时连接同一副眼镜。** 使用 Turbo IO 时停止官方 App 的连接；切换客户端需正确处理已有绑定，不要同时抢连接。
- 不能保证完整离线录音、任意长度的无损补传、长期后台永不掉线、强退后可靠推送或所有固件都兼容。
- 不提供官方历史数据迁移、镜片像素级截图、语音自动批准高风险电脑操作；NAS / Obsidian 自动入库尚未完成。

未完成或仍有问题的功能会继续标注，不把成功回执当作镜片验收。欢迎提交脱敏日志、复现步骤和 PR；请勿上传自己的 Key、录音、聊天、设备标识或他人的私人数据。

## 快速开始

准备 macOS、Xcode、XcodeGen、Node.js 和一个可用模拟器，在源码根目录运行：

```sh
node scripts/start.mjs --local
```

选择 `RayNeoCompanion` + 模拟器，在 Xcode 点击 Run。这条路径不需要厂商库/眼镜/云 Key，可使用本机页面、文件、待办和书库。ZIPFoundation 0.9.20 已以本地源码依赖附带；Xcode/运行时由使用者安装。

实际连接眼镜使用：

```sh
node scripts/start.mjs --device
```

设备版所需的现有厂商 framework、Opus 静态库/头文件和 WebRTC VAD 编译源码已经随工程提供，版本清单见 `DEPENDENCIES.json`。脚本预检依赖并重新生成恢复接口声明模块；缺文件会明确列出。在 Xcode 选择 `RayNeoCompanionDevice`，设置自己的 Team，连接自己的 iPhone 编译运行。具体步骤与 API 配置见 [配置与启动](docs/CONFIGURATION.md)。

## 配置后怎么使用

1. 在设备页连接/认证自己的眼镜；已有绑定优先重连，别反复重置。
2. 在语音服务页填写自己的 ASR Host / Key 与 DeepSeek Key，再选择启用待命。
3. 唤醒后识别文字与模型回答流式显示，会话内有效新句可以插话。
4. 录音先保存本机，手动点转写才上传到自己的 ASR。聊天文字在“会话 → 对话时间轴”。
5. Codex、天气和 USB 观察分别按需配置；不要把另一项的 Key 当通用令牌。

源码无默认开发者租户或凭据；用户提供的服务必须支持当前已实现的协议/模型，不承诺随意换一个 API 名称就兼容。iPhone 当前目标 iOS16+，独立公共传输包需要Swift6.2+工具链。

## 能力与边界

| 能力 | 状态 |
| --- | --- |
| 独立 App 绑定/认证/连接恢复 | 厂商库复用路线有真机记录；非越狱设备仍需专门验收 |
| 云 ASR/VAD、DeepSeek 流式、持续插话 | 真机通过；新配置入口需在自己的服务验收，自有 TTS未完成 |
| 普通录音→WAV、手动ASR→Markdown | 短录音真机通过；无线无损、长录音及完整离线开录不保证 |
| 聊天时间轴、本机待办、TXT/EPUB | 已实现；不导入官方历史，系统提醒事项单向复制 |
| 眼镜待办反向同步 | 当前有完成状态未回到 App 的问题 |
| 提词、天气、通知 | 已接入，部分镜片验收；所有图标/旋钮/排版仍未全覆盖 |
| Codex 发任务/查结果/主动提醒 | 有真机记录；无 APNs，语音自动批准未开放 |
| 全天智记 | 限时实验，原包/电脑解码/ASR对照；非正式全天产品链 |
| 显示观察 | 真实页面状态→USB→Web；不是镜片截图 |
| NAS/Obsidian自动入库 | 未完成，已有本地导出基础 |

## 怎么做出来的

先分析官方 App 结构和真实交互，区分连接认证与业务消息；复用通信核心快速打通独立客户端，再把可确定逻辑拆成 protocol、session、transport、display、archive 等 Swift 包。眼镜做输入/显示，手机做连接/音频/状态，云端做识别和模型，电脑执行 Codex。

完整解释及踩坑：[实现思路](docs/ARCHITECTURE.md)。它说明证据如何建立、为什么不能把发包成功当镜片显示成功，以及为何当前不急于把通信底层全部重写。

## 源码布局

| 路径 | 内容 |
| --- | --- |
| apps/RayNeoCompanion | SwiftUI客户端与测试，技术名称为兼容保留 |
| core-probe/Sources | 当前设备版复用的研究通信/语音适配源码 |
| rayneo-* | 纯Swift协议、会话、传输、显示、归档和容器检查模块 |
| codex-bridge | 电脑端受限HTTP桥接与测试 |
| display-observer | USB只读观察服务与Web预览 |
| scripts/start.mjs | 开发工具检查、依赖预检、打开Xcode |
| scripts/check-source.mjs | 不打印敏感值的发布候选扫描 |
| docs | 启动、架构、发布边界 |

## 测试

```sh
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
xcrun swift test --package-path rayneo-session
```

更多步骤见[配置文档](docs/CONFIGURATION.md)。本地通过、普通签名、真实镜片与非越狱验收分别记录；不使用含开发者录音或账号的fixture。

本次源码交付的编译与测试记录见 [交付验证](docs/VALIDATION.md)。

## 隐私与许可

自己的Key保存在自己的iOS钥匙串；云对话会上传音频/识别文字，录音转写由用户手动触发。音频/Markdown留在自己的App容器，不覆盖原件，不自动上传NAS。Hash/CRC不是加密，也不构成全程端到端加密承诺。

本项目自行编写的代码采用 [MIT](LICENSE)。第三方组件及厂商通信库不因随工程使用而改为MIT，具体归属见 [第三方说明](THIRD_PARTY_NOTICES.md)。本工程与设备厂商无官方隶属关系。

发布不包含个人录音、聊天、凭据、绑定数据库、原始日志、私有临时隧道配置、IPA或预签名App。详见[源码发布说明](docs/SOURCE_RELEASE.md)。
