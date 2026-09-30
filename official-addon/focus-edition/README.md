# FOCUS-04 配套 iOS 插件 · 新 UI 与番茄时钟

2026-09-25。可选集成版，不覆盖主目录旧构建。只提供源码和设计素材；**没有作者的 Key、Cookie、Apple 账号、证书或签名 IPA**。你需要自己配置、编译和签名。适配雷鸟 AI **iOS 1.0.5（201）**，其他版本不要直接套用。

[FOCUS-04 固件、风险与升级说明](../../firmware-research/strix-1.0.4.12/native-navigation/focus/README.md) · [完整更新海报](../../docs/screenshots/midautumn-update-20260925.png)

## 包含什么

- Turbo IO 插件深色新 UI、首页眼镜入场动画、四张功能卡与底部导航；不修改官方原有业务页面。
- 音乐、阅读、新闻、模型/TTS、导航、诊断，以及手机本机 / 眼镜独立番茄计时入口。阅读发送进度保留包数和已发送量。
- Apple 提醒事项与日历同步：待办、定时日程、去重和完成确认规则见[同步说明](../docs/APPLE_TASK_SYNC.md)。
- TFP1 双向命令、状态回读与默认锁定的 OTA 门禁，固定绑定 FOCUS-04 Release 原样 ZIP。
- 默认本机 TTS；可自行设置模型、TinyFish、云端 TTS Endpoint/Key、地图 Key、个人身份提示词。高德需要自己的 iOS Key 和正确 Bundle ID。
- 微信读书书架/统计与封面、本地 TXT/EPUB 正文。**不提供网页 Cookie 正文适配，不等于微信读书 Skill 可以取全文**。本机导入应为有权使用、无 DRM 的文件。
- 本地翻译是可选动态模块，延用[公开翻译模块](../local-translation/README.md)；不附带模型权重。不配置模块时会提示未加载，不能把菜单入口当成已安装模型。

## 构建

在 macOS 安装 Xcode 命令行工具和 Node.js，先阅读[宿主输入与签名限制](../README.md)。需要合法可用、未加密、thin arm64 的原版 `Runner.app`；不从设备提取账号或签名，不处理解密绕过。

从仓库根目录获取固定高德依赖（脚本校验下载哈希）：

```sh
node official-addon/setup-amap.mjs --accept-sdk-terms
```

构建与 FOCUS-04 匹配的完整实验版：

```sh
TIO_AMAP_ENABLED=1 TIO_AMAP_SDK_ROOT=/absolute/Turbo-IO/official-addon/build/amap-sdk \
TIO_OTA_FLASH_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 \
TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 \
bash official-addon/focus-edition/build.sh embedded com.rayneo.venus.pub
```

产物 `official-addon/focus-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib`。上述宏启用受保护实验入口，**并不授权刷写**。勿遗漏宏后再强改校验；这是 opt-in 整合版，不与旧 addon dylib 同时加载。

### 用自己的证书打包

先按固件 README 验证下载的 Release ZIP，再运行：

```sh
node official-addon/package.mjs \
  --app /absolute/Runner.app \
  --addon /absolute/Turbo-IO/official-addon/focus-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 \
  --device YOUR_DEVICE_ID \
  --bundle com.rayneo.venus.pub \
  --amap-sdk-root /absolute/Turbo-IO/official-addon/build/amap-sdk \
  --experimental-ota TFP1 \
  --firmware /absolute/StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-EXPERIMENTAL.zip \
  --out /absolute/new-private-package
```

脚本验证宿主版本、固件精确哈希、模块符号及 profile 设备/证书/Bundle ID/有效期，复制 `TurboIOArt` 和高德资源，再用你自己的授权签名。不会合成官方推送、Apple 登录等 entitlement。需要支持设备扩展时按主打包文档显式传 `--product`，不要伪造权限。产物是本机私有 IPA；不要把它、签名报告或 provisioning profile 提交到仓库。

可选本地翻译：先按翻译教程构建模块、准备模型，然后给上面命令增加 `--translation-module-dir /absolute/module --translation-models /absolute/models`。二者必须成对，脚本验证版本与模型；不加时其余页面仍可构建。

安装使用 Xcode Devices and Simulators 或你自己的签名安装工具。安装会重启宿主，先停止眼镜任务、备份数据；这里不提供自动安装或刷写命令。自签身份和官方身份不同，官方登录/推送等系统能力不保证全部可用。

## 番茄时钟怎么用

1. 完成 FOCUS-04 固件验收后，进入 Turbo IO → 首页 → 番茄时钟。
2. 选择“眼镜独立计时”，刷新确认回执，再选 15/25/45 分钟；更多设置支持 5–120 分钟、短休息/长休息与 30 秒验收。
3. 手机可开始、暂停、继续、结束；眼镜短按暂停/继续，长按停止并退出。不是轻触即执行，也不需要手机在线才能停止。
4. 前 3 秒完整显示，之后小提示，约 10 秒释放亮屏保持，再按系统规则息屏。抬头查看需原厂头控设置支持；不是始终亮屏。到时空闲才提醒，重启眼镜会中断这一轮。

“手机本机”是独立本地计时，切后台再回来不会重置，但**不提供手机后台提醒，也不发送眼镜命令**。不要把两种模式当成相同后台能力。

## 验证与限制

公开脱敏版已在本机编译；固件公开源码重建 AP 与用户实刷确认的 FOCUS-04 一致，构建包含生命周期/输入/内存回归。新加入的公开打包路径做了正反向校验测试；公开版去掉私人配置和网页正文模块后，**没有再安装到用户设备进行整包回归**。使用者仍需验收权限、签名、连接和实际镜片显示，不能宣称“零风险一键使用”。

宣传海报和番茄设计稿是效果示意；并非每个数字、控件位置与实机像素一致。首页截图来自无私人配置的模拟环境。所有默认配置为空，Cookie/服务 Key 应仅通过自己的本机界面配置。
