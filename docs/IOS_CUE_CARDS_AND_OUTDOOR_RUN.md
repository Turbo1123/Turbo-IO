# iOS 提词卡与 Apple Watch 户外跑步看板

本文记录 Turbo IO FOCUS-04 iOS 集成版中的提词卡、Apple Watch 户外跑步和眼镜运动看板。源码适配雷鸟 AI iOS 1.0.5（Build 201），手表工程目标为 watchOS 11.0；镜片端需要 Strix OS 1.0.4.12 的兼容实验候选，其中包含提词卡菜单与独立 TWK1 运动看板协议。

**状态边界：** 本次 PR 加入源码、Watch companion 构建工程与固件研究覆盖层。本分支已通过无签名编译和离线回归；没有签名 IPA、可安装 Watch 包或可刷写眼镜固件，也没有随本 PR 发布的精确候选固件 ZIP。固件覆盖层仍需生成匹配研究候选并在设备上验收。使用者需自行准备有权使用的原厂宿主副本、Apple 开发签名与兼容眼镜固件。项目许可证仍为 PolyForm Noncommercial 1.0.0。

## 提词卡

- iPhone 端可手动新建和编辑卡组、调整卡片顺序、删除卡片，并从 UTF-8 Markdown、JSON 或同结构 TXT 导入。
- 可把用户粘贴的材料交给已配置的文本模型生成卡组草稿。生成只在用户操作后发生，不调用工具、搜索或聊天历史；用户检查草稿后再保存。
- Apple Watch companion 可浏览卡组和卡片、查看当前演示、翻页，以及把一张新卡插到选中卡片之后。WatchConnectivity 不可达时不会把操作排队；新增和翻页需要手机可达。
- iPhone、手表与眼镜通过卡片快照和版本号同步当前卡片。眼镜可用按键或手势翻页；再次开始演示会从第一张打开。演示过程中新增内容会在下次开始时进入新的演示快照。
- 提词卡暂时占用眼镜显示通道时，导航、阅读、音乐和运动显示之间按模块规则结束或拒绝并发占用。

## 户外跑步心率看板

- 用户在手表主动开始室外跑步。Watch 使用 HealthKit workout session / live builder 读取本次运动数据，并在结束时请求保存到 Apple 健康，随后可由系统同步到健身 App。
- 手表经 WatchConnectivity 把实时快照送到 iPhone；手机将其编码为单独的 TWK1 文件协议，再经原生连接发送至眼镜。心率区间采用 HealthKit Watch 返回的配置和当前区间，不在手机或眼镜重新推算。
- 眼镜显示左右分区运动看板，包括心率、配速、步频、步幅、距离、活动热量、用时和可用的心率区间。缺失或过期数据按缺失处理；不会伪造为实时值。
- iPhone 是 Watch 与眼镜之间的中继。代码为后台接收和有限时长的文件传输留出路径，但长时间锁屏、不同 WatchConnectivity 状态及系统资源压力下的持续传输还需要独立验收；手表继续记录与眼镜持续显示是两个不同状态。

## 构建与安装前提

1. 使用 macOS、Xcode 和个人 Apple 开发团队分别构建 iPhone 插件与 `apps/CueCardsWatch`。Watch companion 必须签名，并与宿主的 Bundle ID、Team ID 和版本匹配；HealthKit 权限由使用者在手表上授予。
2. 在宿主插件构建中显式启用 `TIO_DISPLAY_PHONE=1` 和 `TIO_IMAGE_RX_LAB=1`，再以个人证书构建、签名和安装。Watch app 通过打包器的 `--watch-app /absolute/CueCardsWatch.app` 嵌入；不传该参数时不会把 Watch 功能带进 IPA。
3. 镜片端需要与提词卡菜单和 TWK1 对应的 Strix OS 1.0.4.12 研究候选。仓库提供源代码覆盖层，不等于可下载的固件 Release，也不建议把不同候选的手机升级门禁混用。

本 PR 没有生成或分发个人签名产物，也没有把原厂 IPA、证书、密钥、个人账号数据、模型服务凭据或固件 ZIP 加入仓库。宿主的旧 OTA 打包入口目前不包含 TWK1 更新目标；不要使用其他协议的 OTA 授权代替它。

## 本分支离线构建与回归

2026-09-28 在 macOS 的 Xcode 27.0、iPhoneOS/watchOS 27.0 SDK 下，从仓库根目录执行：

```sh
TIO_DISPLAY_PHONE=1 TIO_IMAGE_RX_LAB=1 TIO_SKIP_CODESIGN=1 bash official-addon/focus-edition/build.sh embedded com.rayneo.venus.pub
TIO_DEVELOPMENT_TEAM= TIO_WATCH_DESTINATION='generic/platform=watchOS' bash apps/CueCardsWatch/build.sh com.rayneo.venus.pub
bash official-addon/test.sh
```

手机命令生成本地未签名 arm64 插件；Watch 命令使用 `CODE_SIGNING_ALLOWED=NO`，生成未签名的 arm64/arm64_32 Watch app。两个构建均完成。测试脚本通过了原有插件回归，并补测无 Watch 参数的打包、合成的合法/不匹配 Watch 元数据、提词卡越界和翻页、Watch 消息字段与时效路由。固件测试在临时目录把 13 项提词菜单、TWK1 协议和 14 项运动菜单依次覆盖到 FOCUS 源码，再编译生成的原生协议与运动看板模拟界面，核对 TNV1/TWK1 互斥、文件名/魔数路由、实时数值和过期占位显示。新增测试没有使用证书、健康数据或设备，也没有生成固件镜像或 OTA ZIP。

## 验收范围

此前的设备验收记录包括：提词卡新增内容保存有效、手机/手表/眼镜翻页同步、眼镜启动提词卡、运动期间眼镜心率和右侧数据更新，以及室外跑步出现在健身 App。上述记录是本项目已有的用户设备反馈，不代表本 PR 分支重新编译、安装或复测。

本分支现已完成上节的无签名构建和离线测试。仍需用本分支的签名 iPhone/Watch 包和匹配固件，逐项检查三端翻页、结束与运动保存、锁屏后台传输、断连恢复及眼镜显示；本轮没有安装或刷写当前提交。离线测试中的 Watch 元数据为合成输入，尚未验证真实证书、描述文件与嵌入后的 IPA。

## 变更记录

### 2026-09-28 · 提词卡与户外跑步看板

- **涉及模块：** iPhone 提词卡 UI/Core、WatchConnectivity、Watch companion、HealthKit 户外跑步、TWK1 手机中继与眼镜渲染、提词卡/TWK1 固件研究覆盖层、Watch app 签名打包校验。
- **修改前后差异：** FOCUS-04 集成版没有提词卡和 Apple Watch 户外跑步入口；现在增加卡组管理、Watch 新增/翻页、三端同步、HealthKit 跑步采集、TWK1 眼镜看板和 Watch app 的嵌入校验。
- **原因与依据：** 用户需要在 Turbo IO 中公开可复用的提词卡和户外跑步眼镜看板源码；现有 Watch 用户验收反馈作为历史设备证据，见上文。
- **影响范围：** 仅 `TIO_DISPLAY_PHONE` 可选集成构建、Watch companion 和 Strix 1.0.4.12 研究源码路径；不改变旧 addon 默认构建、Android/HarmonyOS、既有提醒事项同步 Issue/PR 或现有 OTA 发布。
- **验证结果：** 对本 PR 的源码与变更进行静态核对；没有在本分支运行构建或测试，也没有安装 IPA/Watch app 或生成固件包。
- **未决项：** 精确 TWK1 固件候选 ZIP、公开可下载的个人签名安装产物、锁屏期间持续传输和不同配置的设备回归。

### 2026-09-28 · PR #38 审查修复与离线验证

- **涉及模块：** iOS 打包器、Watch companion 校验、提词卡与 Watch 消息路由、阅读占用判断、手机/Watch 构建脚本及固件研究覆盖层测试。
- **修改前后差异：** 打包入口调用了未导入的 Watch helper，普通无 Watch 打包也会在输出目录创建前抛出 `ReferenceError`；现由明确导入的预检函数统一处理有/无 Watch 路径，校验失败时输出目录仍不存在。提词卡启动所需的阅读空闲判断此前未定义，现按阅读会话、传输和加载状态返回结果。新增实际路由使用的 Watch 命令校验、提词卡页码边界和协议/菜单覆盖层回归，并提供显式跳过临时签名的构建开关。
- **原因与依据：** [Turbo1123 对 PR #38 的审查](https://github.com/Turbo1123/Turbo-IO/pull/38#pullrequestreview-5338883761)指出了打包阻断项，并要求无 Watch/Watch 元数据、提词翻页、消息路由、TNV1/TWK1 互斥、固件覆盖层及可复现构建记录；实际无签名编译又发现阅读空闲函数缺失。
- **影响范围：** iOS FOCUS-04 可选集成分支及本地构建/测试入口；正常构建仍执行原有临时签名，只有 `TIO_SKIP_CODESIGN=1` 跳过。Watch 与眼镜固件研究范围保持本页所述边界。
- **验证结果：** `node --test official-addon/package.test.mjs` 10/10 通过；`bash official-addon/test.sh` 通过，包含新增提词卡核心和固件覆盖层测试；上述 Xcode 27.0 手机/Watch 无签名构建成功。未在当前提交上安装 IPA、Watch app 或刷写固件。
- **未决项：** 真实签名/描述文件的 Watch 嵌入打包、精确固件候选构建与校验、三端翻页和结束保存、前后台及断连恢复的本分支设备验收。
