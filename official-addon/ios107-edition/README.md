# iOS 1.0.7（230）· APP107 兼容适配

2026-10-19 · [首页更新](../../README.md#ios107-update) · [OTA 预发布](https://github.com/Turbo1123/Turbo-IO/releases/tag/ios107-app107-ota-20261019) · [上一版 NAVS3](../navs3-edition/README.md)

**用户已在 iPhone 17 Pro Max 覆盖安装 1.0.7（230）私用适配包，测试后反馈“没啥问题”。** 回读确认 APP107-PHONE-01、宿主 1.0.7/230、hooks/版本门槛通过。不是所有功能、账号、机型与后台场景的全量验收；公开脱敏版单独编译与离线检查，不冒充与私用包逐字节相同。

## 变化与版本选择

- 基于 NAVS3 保留起终点导航、矢量路网与路名、菜单排数配置及现有扩展模块。
- 精确新增 `1.0.7 / 230 / 410DEFDB-F937-39EA-ACF2-F616ABFF9D0B`，不放宽未知宿主。
- 8 个关键 native 类的 110 个既有方法签名无变化；Flutter 检查覆盖 445 个方法，关键桥接一致。静态一致不代表业务逻辑完全不变。
- **固件原样沿用 TMG2**，已有 TMG2 不必因手机升级重刷；没有新增或更换官方固件基线。
- **1.0.7 OTA 已实刷开放。** 2026-10-19，iPhone 17 Pro Max 使用 APP107-OTA-PHONE-01 经官方升级流程安装原样 TMG2 成功，重连版本匹配；刷后重启手机 App，授权归零。公开版移植同一升级逻辑，单独编译回归，不将公开包称为原样实测 IPA。
- 新版两个 Dart 查询数据记录单独验证，仅修改字符串内容，长度、缓存哈希、对象头与代码指令不变；运行时精确检查宿主版本/UUID/标记和路由。完整包、15 文件清单、待传分片仍严格校验；未授权不能刷写。

| 版本 | 手机适配 | 固件 / OTA |
| --- | --- | --- |
| APP107 / 1.0.7（230） | 最新兼容适配，继承 NAVS3 | **原样 TMG2 OTA 已实刷开放**；默认锁定，按专用教程单次授权 |
| NAVS3 / 1.0.6（218） | 前版矢量导航修正 | 精确 TMG2 候选与门禁，按其独立教程使用 |
| Android 1.0.5 | 本轮未更新 | 不与 iOS 门禁混用 |

## 公开边界

仅公开原创源码、构建/打包工具与离线测试，**不含合并/个人签名 IPA、Cookie、Key、私人服务地址、签名材料、备份、用户通知/智记/路线、微信读书网页正文适配或 Dots Bridge**。Dots UI 仍未完成；微信读书保留公开书架与本地正文路径，账号与服务自行配置。

从已脱敏 NAVS3 基线导出，合入已审核的 1.0.7 兼容及 OTA 适配，不从私人 IPA 抽取配置或素材。沿用 [PolyForm Noncommercial 1.0.0](../../LICENSE)，第三方许可不变。原厂 App、高德 SDK 须自行合法取得。

## 构建与检查（macOS / Xcode）

在本目录执行：

```bash
export TIO_AMAP_SDK_ROOT=/absolute/path/to/amap-sdk
TIO_AMAP_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 \
TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_OTA_FLASH_ENABLED=1 \
TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub

node --test package.test.mjs
python3 test.py --firmware /absolute/path/to/exact-TMG2-release.zip
```

`FLASH` 是保护模块编译开关，**不是授权**；本版打包默认带 TMG2 升级通道，初始仍锁定。不要移除校验或改 Info.plist 冒充其他版本。

固件 ZIP 从 [TMG2 原样预发布](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)获取，SHA-256 为 `6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473`；不产生新固件，也不会自动授予刷写权限。

## 自行合并与签名

需合法的 **1.0.7（230）未加密原厂 Runner.app**。可参见[原厂去签名 IPA 归档](../../official-apps/ios/1.0.7/README.md)，它没有 Turbo IO，也不是签名安装包。本工具不提取或解密；1.0.6 输入不能代替。只接受下列两种精确配对，其他去签名/重签派生文件不接受，不能通过删校验绕过。

| 输入 | SHA-256 |
| --- | --- |
| 解密 Runner | `c416d939c90745b170027171844e3275faf5e502306746176375dee5837aadcf` |
| 原厂 App.framework/App | `fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e` |
| 发布去签名版 Runner | `765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3` |
| 发布去签名版 App.framework/App | `041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d` |

```bash
node package.mjs \
  --app /absolute/original/Runner.app \
  --addon /absolute/ios107-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 --device YOUR_DEVICE_UDID \
  --out /absolute/new-private-output --bundle com.rayneo.venus.pub \
  --product iPhone18,2 --amap-sdk-root /absolute/path/to/amap-sdk \
  --firmware /absolute/path/to/exact-TMG2-release.zip
```

无需额外传 `--experimental-ota`，打包默认启用固定 TMG2 通道（显式传值也只接受 `TMG2`）。工具只修改两个已核验的 App.framework 查询数据记录，不改代码指令；签名后再次检查记录，不下载/安装/刷写，不新增官方推送或 Apple 登录权限。可选翻译模块与模型见[单独说明](../local-translation/README.md)；Watch 按 [Watch 说明](../../watch-remote/README.md)自行构建，不含作者签名包。源码含模块不代表打包器自动补齐所有第三方 SDK、模型、Watch、服务配置或应用广场资源。

先备份，再使用同一有效签名覆盖安装；签名冲突时不要盲目卸载。启动确认版本、插件入口、眼镜连接并逐项测试，编译成功不等于你的设备验收通过。

## 刷入 TMG2

按[1.0.7 升级教程](OTA.md)执行：内置校验 → 15 分钟只下载 → 官方软件就绪 → 目录校验 → 单次授权 → 官方安装 → 成功回首页后重启手机 App，确认授权归零。高风险实验，非开发者请勿刷。

## 已知限制

- 手机锁屏后导航停止/卡住仍待闭环，不用于驾驶或安全依赖。
- 路网首次加载、断网或请求预算耗尽仍可能只显示路线。
- 本版固定 TMG2，不接受原厂 ZIP 或其他候选；[原厂恢复](../../firmware-research/strix-1.0.5.5/README.md)需要独立匹配的恢复工具链，不能复用本版授权，也不保证救砖。
- 原厂登录/推送、Apple 登录、长期后台和所有功能均需独立验收。
