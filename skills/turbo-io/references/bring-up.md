# Turbo IO 接入流程

这些命令在项目源码根目录执行，而不是在已安装的技能目录执行。以 checkout 内最新 README 和配置/实现为准；下面是引导，不是强制对所有用户执行全部步骤。

## 取得源码与检查

若用户工作区没有项目，先确定不存在的新目录，再克隆：

```sh
git clone --depth 1 https://github.com/Turbo1123/Turbo-IO.git <new-directory>
```

进入新 checkout，记录提交版本。不要用同名已有目录作为覆盖目标。克隆失败时报告网络/权限问题，不改 Git 全局配置或关闭证书校验。

- Web：Node.js；不需要 Xcode、眼镜、ASR Key 或 iproxy。
- iOS：macOS、Xcode、XcodeGen、Node.js；模拟器需要可用的 iOS runtime，设备需要用户自己的签名。已验证工具版本及最低部署目标见 `docs/CONFIGURATION.md`。
- 当前无需 `npm install`：Web 与 bridge 使用 Node 内置模块，App 的 ZIPFoundation 已随仓库附带。不要凭经验引入 npm 依赖。
- 检查 `DEPENDENCIES.json` 与实际依赖；真机启动脚本还会检查 framework、Opus、VAD 和恢复声明文件。缺依赖先补全同一仓库版本，不要下载不匹配的同名库。

## A. Web 预览（默认快速路径）

```sh
node display-observer/server.mjs --no-proxy
```

使用宿主的后台/终端会话机制保持进程，给用户记录会话或 PID。访问 `http://127.0.0.1:8790/`，检查标题 Turbo IO / 显示观察台，实际切换首页、对话或菜单样式；浏览器可用时检查页面，否则用 HTTP 内容检查并说明未视觉验收。

这是无手机演示；“接口未连接”是预期现象，不能伪造实时状态。不需要填写临时令牌。8790 被占用时先只读确认监听者，不能杀掉未知进程；若是用户已有 Turbo IO 服务，复用并说明。关闭时只停止自己本次启动的进程。

要真实观察时才阅读 `docs/CONFIGURATION.md` 的 USB 部分：用户指定手机，iproxy 转发，手机开启临时观察接口。不要擅自开启正文观察。

## B. iOS 模拟器

```sh
node scripts/start.mjs --local
```

脚本生成工程并打开 Xcode，还不等于 App 已运行。选 `RayNeoCompanion` 和用户已有的模拟器，运行并检查设备/会话/工具页面。若使用命令行，先通过 `xcrun simctl list devices available` 选择真实存在的模拟器；用新 DerivedData，构建并安装/启动该模拟器 App。不使用硬编码设备 ID，不安装到真实手机来冒充模拟器验收。

模拟器不连接眼镜；其 Keychain 测试需要 ad-hoc 签名。不要为了绕开签名错误关闭所有签名并声称运行正常。只做编译检查时才使用 `CODE_SIGNING_ALLOWED=NO`，并如实标明。

## C. 真机与眼镜

```sh
node scripts/start.mjs --device
```

选择 `RayNeoCompanionDevice`、用户自己的 Signing Team、目标 iPhone。启动脚本重新生成仅声明的 RayneoNet 模块，不能把声明里的占位实现编译链接进去，也不能改用 `--local` 掩盖缺厂商依赖。

确认用户要首次配对还是日常重连。官方 → Turbo IO 切换必须完成官方解绑、系统忽略、蓝灯配对；日常重连不要重复这些步骤。App 显示连接不等于业务可用：至少核对已认证、唤醒初始化和一个用户可观察的短文本/通知测试。没有用户观察时不要编造镜片结果。

## D. 语音与电脑 Agent（仅按需）

- 云语音：阅读 `docs/CONFIGURATION.md` 第 4 节，让用户在 App 安全输入自己的 ASR Host / Key 和 DeepSeek Key。当前服务协议/模型由执行器决定，不是任意 OpenAI 兼容 URL 都能替换。先短句识别，再流式回答，再测试插话与收尾。保存配置不是调用成功。
- Codex：阅读第 6 节以及 `codex-bridge/bridge.mjs`。使用用户已有的 Codex 登录，先核对安装的 CLI 支持的 app-server 参数与桥接实现；不要擅自修改用户全局 Codex 配置。bridge 会启动独立子进程，不是接管当前聊天。
- bridge 的目标工作区由用户选择。令牌应为新生成的独立随机值，保存在仓库外的私有文件（0600），不要放进命令行、源码或聊天；手机端通过安全输入配置。默认回环/只读；手机连接使用用户可信的 HTTPS/TLS 入口，不能直接公开裸服务或去掉鉴权。
- 用用户同意的无文件读写随机码任务验证：任务 accepted → completed → 手机接收 → 眼镜通知，各步分别确认。模型只有 message/status/stop，不能自动批准写操作。遇到不确定响应沿用 requestId，不重复创造任务。
- Claude Code 使用这个技能帮助安装项目，和“眼镜已经接通 Claude Code 后端”是两件事。后者尚需实现适配。

## 验证与交还

Web/bridge 变更可运行 `node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs`。构建或硬件测试按请求风险选择，不为一次 Web 预览跑完整设备测试。不能把历史测试数字当成本次结果。

最后给出实际完成项、可访问 URL/工程、保留的后台进程和用户尚需完成的步骤；明确源码、Apple 开发工具、签名和服务 Key 是不同层级的依赖。
