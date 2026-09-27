# Turbo IO Android · 1.0.5 完整插件与实验 OTA

**2026-09-27：公开1.0.5（201）扩展源码、去除网页正文适配的完整APK，以及实刷 TAP1-TEST-01 固件。** 非官方、非商业研究发行；不是稳定版，也不是独立 Android 蓝牙 SDK。

## 下载与安装

**[下载 APK / 固件 / SHA-256](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01) → [逐步安装与刷写教程](docs/INSTALL_AND_FLASH.md)**

**GUARD-07 刷完必须收尾：** 眼镜自然回首页后，在插件升级页底部完成「已自然回首页：允许只读回查」及「已检查显示TEST：解除结果保护」。确认`LOCKED / 授权0 / 结果保护未开始`后再测日常功能；否则手机会继续拦截官方业务。更新未结束或状态不明时不可释放。[必做步骤](docs/INSTALL_AND_FLASH.md#4-必做自然重启--只读回查--释放保护)

不必自己合并插件；公开APK已包含扩展。APK与官方签名不同，签名冲突时请先导出旧App数据，不能无损覆盖。固件是高风险实验用品，不懂刷机排错请勿尝试；不保证回滚救砖。

## 包含与不包含

| 模块 | 公开范围 |
| --- | --- |
| 模型 / Tools / TTS | 自定义模型、搜索工具、本机/可配置云端语音；无个人服务Key |
| 导航 / 音乐 / 番茄 | 原生通信、播放/歌词/封面、导航和计时控制；需匹配眼镜固件与自己的服务配置 |
| 微信读书 | 书架、统计、封面处理、TXT和内置原创测试书；**不含网页正文和Cookie入口** |
| 仪表盘 / 应用广场 | 卡片、四槽小应用、20个离线模板与开发入口 |
| 新闻 / 云端字幕 / 后台 | 配置与实现公开，服务端可用性、长期后台行为和不同机型需另行验证；无离线翻译 |
| 固件升级 | GUARD-07：固定候选、只下载、单次授权、官方升级路径、2分钟预检、人工收尾 |

微信读书网页适配的参考项目是 **AGPL-3.0 开源代码，不是闭源**。当前组合未解决许可证兼容，故源码和APK均移除该部分；开发者需在遵守许可和服务权限前提下自行适配，详见[边界说明](docs/INSTALL_AND_FLASH.md#微信读书为什么不含网页正文)。本机私用配置、Cookie、签名私钥和账号均不发布。

**微信读书 / 网易云音乐的登录、会员与服务权限需用户自行处理。** 不提供账号、代登录、Cookie 获取或风控绕过；登录成功不等于本项目已支持微信读书网页正文。普通用户请继续使用官方 App / 原厂固件，不要为这些功能盲目刷机。

Fold3 / Android15 本轮已分别获得音乐、阅读测试文本、应用示例、导航和番茄相关验收；原厂天气、云端服务、长时后台、物理按键全覆盖及故障恢复不能视为全量通过。此次OTA用户实测成功的APK是GUARD-07私用构建；公开APK移除上述正文适配和专属字幕地址，OTA源码不变，重新编译不等于再次真机刷写。

## 源码构建

依赖 JDK、Node、Python3、apktool、Android SDK platform36/build-tools36.0.0、C编译器。Python SDK依赖按 `dashboard-service/README.md` 安装。原厂输入必须是1.0.5（201），SHA-256：

`770ba0793d31609aa1e4477db2f8a7aec2c8acc4d9c6ab43d57b0dfc720d3ab3`

原厂来源：[雷鸟 AI Android 官方下载页](https://rayneo.cn/commonPage/venus/appDownload/index_m.html)。网站可能已更新，摘要不匹配就停止，不能仅改白名单适配新版本。

```sh
# 仓库根运行；先下载本Release固件（不要解压），放到下面路径：
mkdir -p official-addon/build/app-ap-20260927-test-01
# 将 TurboIO-TAP1-TEST-01.zip 复制并重命名为：
# official-addon/build/app-ap-20260927-test-01/StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip

export ANDROID_SDK_ROOT=/path/to/Android/sdk
export TURBO_SDK_PYTHON=/path/to/python-with-dashboard-sdk-dependencies
apktool d --no-res -o android-addon/build/host-105 /path/to/RayNeo_AI_1.0.5.apk
bash android-addon/build.sh
node android-addon/package.mjs /path/to/RayNeo_AI_1.0.5.apk
node android-addon/official-ota-source.mjs android-addon/build/host-105/lib/arm64-v8a/libapp.so android-addon/build/ota-route
python3 android-addon/package-official-ota-preparation.py --guarded \
 /path/to/RayNeo_AI_1.0.5.apk \
 android-addon/build/TurboIO-RayNeo-1.0.5-unsigned.apk \
 android-addon/build/ota-route/libapp.so \
 android-addon/build/TurboIO-GUARD07-unsigned.apk
```

之后用 Android SDK 的 `zipalign` 和 `apksigner` 及**自己的签名**签署。保持同一个密钥才能覆盖自己以前签名的版本，密钥不要提交仓库。未加 `--guarded` 的准备包不允许升级，不要和正式实验门禁混淆。

可运行 `python3 android-addon/tests/PrivateArtifactAudit.py /path/to/signed.apk` 检查扩展DEX与允许资源、凭据模式及测试替身；不代替人工审查。私有数据存在手机沙盒，不应从手机导出沙盒重新打包。

[安装教程](docs/INSTALL_AND_FLASH.md) · [固件范围与摘要](../firmware-research/strix-1.0.4.12/tap1/README.md) · [开发者SDK](../docs/DEVELOPER_ECOSYSTEM.md) · [1.0.4历史记录（不是本版流程）](docs/ANDROID_104_HISTORY.md)
