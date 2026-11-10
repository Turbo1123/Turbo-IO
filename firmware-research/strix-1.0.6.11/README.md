# Strix OS 1.0.6.11 · TMIG2-VIDEO-R1

2026-11-10 实验预发布。TMIG2 将 Turbo IO 眼镜功能迁到 Strix OS 1.0.6.11，VIDEO-R1 修复全屏视频在建立连接时直接超时的问题。iPhone 配套测试环境为 iPhone 17 Pro Max、雷鸟 AI 1.0.21（构建 1）。[本版下载](https://github.com/Turbo1123/Turbo-IO/releases/tag/strix-10611-tmig2-video-r1)

## 下载和校验

| 文件及下载 | SHA-256 |
| --- | --- |
| [RayNeo_AI_1.0.21_1_decrypted_unsigned_original.ipa](https://github.com/Turbo1123/Turbo-IO/releases/download/strix-10611-tmig2-video-r1/RayNeo_AI_1.0.21_1_decrypted_unsigned_original.ipa) | `e935d2cb45dc524c65bdf13e5bae095123a7c95d99c6d48840779c96afafbfd6` |
| [TMIG2-VIDEO-R1-1.0.6.11-lab.zip](https://github.com/Turbo1123/Turbo-IO/releases/download/strix-10611-tmig2-video-r1/TMIG2-VIDEO-R1-1.0.6.11-lab.zip) | `c03321061605aba186b44e7b90d86d3b13a2f75e081687fc684680e2800a4e8a` |
| [Strix-OS-1.0.6.11-original.zip](https://github.com/Turbo1123/Turbo-IO/releases/download/strix-10611-tmig2-video-r1/Strix-OS-1.0.6.11-original.zip) | `e403d73b84c20277f183788d778beb7a0ad8336af27efb112c66b7169fcaa320` |

自定义和原厂 ZIP 都是完整 OTA 包。IPA 是单独的手机端研究输入。下载所需文件后运行 `shasum -a 256 文件名`，逐字比对上表。如果已下载全部三项和 Release 中的 `SHA256SUMS`，可在同一目录运行 `shasum -a 256 -c SHA256SUMS`。解密和去签名的具体核验见 [iOS 输入审计](../../official-apps/ios/1.0.21/README.md)。

## 这次适配了什么

- **固件底座和菜单。** 在新版基址上重新编译 90 个 ARM 单元，重定向 40 处原厂指令，适配启动器对象、菜单布局、仪表盘和文件注册入口。保留新版原厂导航和更新组件。清单共 16 个载荷，只有 `nuttx_ap.bin` 和清单中的对应大小、摘要有变化，另外 15 个载荷逐字节与原厂一致。完整 OTA 由官方安装流程决定写入哪些分区。
- **全屏视频和高清投屏。** 新版原厂收包记录的末四字节改为释放函数。旧视频入口将其解释为模式和填充，手机发出 32 字节握手后等 3 秒超时，接收帧数为零。R1 在视频入口为合法包建立只读兼容视图，沿用原厂内存释放。保留眼镜 540 × 220 窗口、旋钮短按暂停或继续，以及高清分块投屏。R1 的 AP 为 **8,196,152 字节**，比 TMIG2 增加 112 字节，项目上限为 9,600,000 字节。AP SHA-256 为 `066f43d76dee15ee9c267903982eaddd3f0835066e03ea43827f84d7e764cf5f`。
- **抬头唤醒。** TMIG2 增加诊断记录，用于对应前台应用、头势监听和传感器占用情况。抬头偶发失效的根因仍待故障现场确认。
- **已知问题。** TBV3 独立蓝牙大包测速仍会按旧格式丢掉握手。R1 上离线回放已复现，暂勿用这个工具的零速率判断眼镜带宽。

## 测过什么

| 范围 | 截至本次发布的证据 |
| --- | --- |
| 官方升级 | iPhone 17 Pro Max、雷鸟 1.0.20（309）从 1.0.5.5 升至官方 1.0.6.11，日志记录安装成功并在重连后确认版本。 |
| 自定义 TMIG2 | 用户反馈已通过 1.0.21 刷入基础版。随后全屏视频握手超时，促成本次 R1。 |
| TMIG2-VIDEO-R1 | 配套 App 已在 17 Pro Max 启动，通过官方「只下载」流程并回读全部 17 个解压文件。发布时尚无本次 R1 真机连续播放、暂停和恢复的完整反馈。 |
| ARM 离线验证 | 视频握手、最大帧像素与 CRC、坏帧拒绝、暂停和释放通过。高清投屏、拍照、IMU、Watch 遥控、菜单排数的握手或查询有回执。另验证文件回调、队列深复制与释放。无线、系统调度和显示硬件需要真机验证。 |

## 已有匹配插件时怎样刷写和验收

1. **先核对环境。** 打开雷鸟 1.0.21（1），在 TurboIO → 设置 → 诊断与实验固件确认显示 `TMIG2-VIDEO-R1-PHONE-01`。Release 中的原厂 IPA 单独安装不会出现这个入口。本次没有发布个人签名的合并 IPA，公开的 APP107 与 Android 打包器面向各自已有版本。缺少匹配入口时请使用官方更新流程。
2. 让眼镜回首页，结束录音、导航、音乐、视频等任务，电量至少 50%。保持蓝牙连接。关闭官方自动更新，等插件显示「内置候选校验通过」。
3. 开启「15 分钟只下载验收」，返回官方固件页检查并下载，停在「软件就绪」。回诊断页核对官方解压目录。两包对外版本号相同，必须确认 **17 个文件**都匹配 R1 候选，才可排除同版本缓存。
4. 点「允许一次 TMIG2-VIDEO-R1 新版固件试刷」，输入 `TMIG2-VIDEO-R1`，回官方页点「开始安装」。等眼镜自行回首页、手机确认安装结果并完成重连。传输期间保持供电和连接。
5. 打开全屏视频，选 4 级灰阶、24 帧。确认画面连续变化、累计帧数上升，再短按旋钮暂停、再次短按恢复，长按退出。若超时，记录手机最后提示、已提交字节和已确认帧数，有助于定位。

## 原厂恢复

请从[原厂归档与恢复说明](stock/README.md)核对适用条件。日常使用优先选择官方固件，对刷机排错不熟悉的用户请保留官方版本。实验刷写风险和责任说明见[首页](../../README.md#使用前必读)。

## 从源码复现

本目录提供实际参与构建的源码、链接脚本、动画资源、补丁清单、视频兼容层和[离线重建结果](verification.json)。Python 3、带 ARM 目标的 clang、ld.lld、llvm-nm 和 llvm-objcopy 用于重建。发布时使用 macOS 上 DevEco Studio 附带的 LLVM 工具链，最终产物按 SHA-256 比对。更换工具链可能生成不同的机器码。

从本目录运行，输出目录须为新路径：

```sh
python3 build.py --stock stock/Strix-OS-1.0.6.11-original.zip --llvm-bin /path/to/llvm/bin --out /tmp/turbo-r1-rebuild
python3 build.py --stock stock/Strix-OS-1.0.6.11-original.zip --audit /tmp/turbo-r1-rebuild/TMIG2-VIDEO-R1-1.0.6.11-lab.zip
```

源码重建所得完整 ZIP 与本次发布文件哈希相同。仓库原创扩展沿用仓库许可。原厂程序、固件载荷及第三方组件的权利和许可归各自权利人。手机端 AirPlay 接收模块的 GPLv3 说明见[接收模块目录](../../official-addon/tar2-airplay/README.md)。
