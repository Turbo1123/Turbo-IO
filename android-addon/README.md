# Turbo IO Android · TVP2 专用插件（宿主 1.0.6 / 1.0.7）

**2026-10-23：Android 插件改为只支持 TVP2 固件。** 宿主支持雷鸟 AI 1.0.6（216）与 1.0.7（230）；1.0.5 宿主、TAP1 / TMIG1 候选与旧自发包刷写流程不再支持。非官方、非商业研究源码；不是稳定版，也不是独立 Android 蓝牙 SDK。

**本轮只有离线测试与打包验证，没有真机验收。** 1.0.7 安装、TVP2 刷写、仪表盘发卡等都需要你在自己的设备上逐项确认；编译通过不等于设备可用。

## 与 iOS 1.0.7 的功能对齐进度

目标是除 AirPlay 接收器外与 [iOS 1.0.7 APP107](../official-addon/ios107-edition/README.md) 等价。分阶段推进，计划见 [对齐路线图](../docs/superpowers/plans/2026-10-23-android-ios-parity.md)。

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| 1 基础 | 宿主 1.0.7、TVP2 升级候选、TVP2 仪表盘兼容 | 已完成源码与离线测试，未真机验收 |
| 2 眼镜原生功能 | 两/三排菜单、遥控拍照、矢量路网导航、情境英语、亮度、TDC1 测试卡 | 未移植 |
| 3 诊断 | 眼镜运行状态、眼镜日志、字幕导航、A2UI / 待办协议验收 | 未移植 |
| 4 手机侧功能 | 通知历史、增强智记、滴滴沙箱、知识库与 Agent、常亮音频、录音整理 | 未移植 |
| 5 显示 | 灵活显示、单张传图、TVP2 高清投屏（安卓录屏代替 AirPlay） | 未移植 |
| 暂缓 | Dots（iOS 亦未完成）、本地翻译、Watch 遥控（Apple 专属） | — |

## 包含与不包含

| 模块 | 公开范围 |
| --- | --- |
| 模型 / Tools / TTS | 自定义模型、搜索工具、本机/可配置云端语音；无个人服务Key |
| 导航 / 音乐 / 番茄 | 原生通信、播放/歌词/封面、导航和计时控制；需 TVP2 与自己的服务配置 |
| 微信读书 | 书架、统计、封面处理、TXT和内置原创测试书；**不含网页正文和Cookie入口** |
| 仪表盘 / 应用广场 | 卡片、四槽小应用、20个离线模板与开发入口。**自定义卡片只在 TVP2 上可用**：原厂 / TMIG1 / TMG2 的 1.0.5.5 已移除安装命令，插件会在发送前停止并提示刷 TVP2 |
| 新闻 / 云端字幕 / 后台 | 配置与实现公开，服务端可用性、长期后台行为和不同机型需另行验证；无离线翻译 |
| 固件升级 | 唯一候选 **TVP2**（Strix OS 1.0.5.5 底座）：固定 ZIP/AP/16 成员、只下载、单次授权（输入 `TVP2`）、官方升级路径、2分钟预检、人工检查镜片后解除保护 |

微信读书网页适配的参考项目是 **AGPL-3.0 开源代码，不是闭源**。当前组合未解决许可证兼容，故源码移除该部分；开发者需在遵守许可和服务权限前提下自行适配，详见[边界说明](docs/INSTALL_AND_FLASH.md#微信读书为什么不含网页正文)。本机私用配置、Cookie、签名私钥和账号均不发布。

**微信读书 / 网易云音乐的登录、会员与服务权限需用户自行处理。** 不提供账号、代登录、Cookie 获取或风控绕过。普通用户请继续使用官方 App / 原厂固件，不要为这些功能盲目刷机。

## 固定输入

| 输入 | SHA-256 |
| --- | --- |
| 雷鸟 AI 1.0.6（216）APK（国内渠道） | `4c1c57ae811cb959478efb5ec510000f7f51ddcb427afff369b1582c66b60206` |
| 雷鸟 AI 1.0.7（230）APK（海外渠道） | `30239f65d910cf7008cfdf6cfacd5c068c5877068b4a637027786377a9ce4f91` |
| [TVP2 ZIP](https://github.com/Turbo1123/Turbo-IO/releases/tag/tvp2-tar2-20261023) `StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip` | `154f0f8e68a69b8fb93f869e423081ee43969bf09c5174e8dbeac192c1047c11` |

原厂来源：[雷鸟 AI Android 官方下载页](https://rayneo.cn/commonPage/venus/appDownload/index_m.html)。摘要不匹配就停止，不能仅改白名单适配新版本。

## 源码构建

依赖 JDK、Node、Python3、apktool（2.12.1）、Android SDK `platforms;android-36` 与 `build-tools;36.0.0`、C 编译器（与上游一致用 clang；Debian GCC 14 会因 `-Werror=misleading-indentation` 拒绝研究源码）。Python SDK依赖按 `dashboard-service/README.md` 安装。

```sh
# 测试输入（不要解压）：TVP2 为唯一候选；TMIG1 / 原厂 1.0.5.5 / TAP1 用于验证会被拒绝。
# official-addon/build/strix-1.0.5.5-tvp2/StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip
# official-addon/build/strix-1.0.5.5-tmig1/StrixOS-1.0.5.5-TurboIO-TMIG1-CANDIDATE-NOT-APPROVED.zip
# official-addon/build/strix-1.0.5.5-tmig1/Strix-OS-1.0.5.5-original.zip
# official-addon/build/app-ap-20260927-test-01/StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip

export ANDROID_SDK_ROOT=/path/to/Android/sdk
export TURBO_SDK_PYTHON=/path/to/python-with-dashboard-sdk-dependencies
apktool d --no-res -o android-addon/build/host-107 /path/to/RayNeo_AI_1.0.7.apk   # 或 host-106 + 1.0.6
bash android-addon/build.sh
node android-addon/package.mjs /path/to/RayNeo_AI_1.0.7.apk
node android-addon/official-ota-source.mjs android-addon/build/host-107/lib/arm64-v8a/libapp.so android-addon/build/ota-route-107
python3 android-addon/package-official-ota-preparation.py --guarded \
 /path/to/RayNeo_AI_1.0.7.apk \
 android-addon/build/TurboIO-RayNeo-1.0.7-unsigned.apk \
 android-addon/build/ota-route-107/libapp.so \
 android-addon/build/TurboIO-GUARD-107-unsigned.apk
```

之后用 Android SDK 的 `zipalign` 和 `apksigner` 及**自己的签名**签署。保持同一个密钥才能覆盖自己以前签名的版本，密钥不要提交仓库。未加 `--guarded` 的准备包不允许升级，不要和正式实验门禁混淆。

可运行 `python3 android-addon/tests/PrivateArtifactAudit.py /path/to/signed.apk` 检查扩展DEX与允许资源、凭据模式及测试替身；不代替人工审查。私有数据存在手机沙盒，不应从手机导出沙盒重新打包。

[TVP2 固件与刷写说明](../docs/TVP2_TAR2.md) · [TVP2 固件源码](../firmware-research/strix-1.0.5.5-tvp2/README.md) · [开发者SDK](../docs/DEVELOPER_ECOSYSTEM.md) · [1.0.5 / TAP1 历史安装教程（不是本版流程）](docs/INSTALL_AND_FLASH.md) · [1.0.4历史记录](docs/ANDROID_104_HISTORY.md)
