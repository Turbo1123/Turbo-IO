# NAVS3 · 起终点直达矢量导航 / TMG2 配套 iOS 插件

2026-10-19 · **实验预发布，不提供合并或签名 IPA。** 宿主限定 RayNeo AI iOS 1.0.6（218），配套 [TMG2 原样固件](../../firmware-research/strix-1.0.5.5-tmg2/README.md)。

## 更新了什么

选择起点 → 选择目的地 → 开始模拟导航（或真实导航），眼镜自动进入新版矢量小地图，不再要求用户寻找固定演示或旧字幕投屏。起点默认当前位置，可手动搜索；自定义起点用于模拟，真实导航从设备当前位置开始。

- 手机负责高德规划、定位与坐标转换；OSM 道路从 WGS-84 转换至高德坐标系，眼镜接收有界矢量场景和轻量位置更新，不传连续整屏截图。
- 周边路网提前请求，最多保留两块区域，新数据未到不清旧道路；旧道路按真实地理位置裁剪，不随车辆平移或补造。
- 路名从真实道路段选择可见锚点，考虑航向、裁剪和遮挡；保留比例尺、时间/预计到达等信息，不轮流显示“导航常亮”提示。
- 菜单支持默认三排或可选两排；现有音乐、阅读、番茄、仪表盘、小应用、情境英语、Watch 手机桥接及遥控拍照等集成代码保留。

**实际边界：手机锁屏后眼镜导航停止/卡住仍未闭环。** NAVS3 修正的是路网缓存与路名锚点，不把“安装加载成功”说成锁屏或持续导航已通过。不要依赖本实验进行驾驶或安全导航。

## 验证与资源限制

私用 NAVS3 已安装并在 iPhone 17 Pro Max 回读确认加载；用户此前确认 TMG2 刷入成功。公开版删除私人配置及网页阅读适配后单独编译，**未另装公开派生包做全功能硬件验收**。固件保持原样，公开源码重建 AP/ZIP 字节一致。

离线回归包括60个合成移动/航向样本、180帧公开地图回放、坐标转换与路径对齐、会话回执、菜单协议、OTA门禁与拍照测试。测试地图不是个人行程。

- 每次会话图源最多6次请求、间隔至少60秒，约1.2km区域；首次下载、断网、超出覆盖或预算耗尽仍可能仅显示路线。
- 最多两个区域、每区5000个 feature / 40000点，单响应上限2MiB。发给眼镜的场景不超过4096字节、96条路径、768点、4个路名。
- 网络图源默认须用户授权，区域范围会发往图源；服务可用性与地区覆盖不保证。OSM 数据遵循 [ODbL 与署名](tests/maps/README.md)，高德 SDK 另遵其协议。
- 红绿灯倒计时、完整离线地图、全城市数据预取不在本版交付范围。

## 构建与签名

需要 macOS、Xcode iPhoneOS SDK、Node.js、Python 3，以及自己的高德 Key / 签名证书 / profile。安装后在导航设置填写自己的高德配置；没有作者的 Key 或云租户。

```sh
node official-addon/setup-amap.mjs --accept-sdk-terms
TIO_AMAP_ENABLED=1 TIO_AMAP_SDK_ROOT=/absolute/Turbo-IO/official-addon/build/amap-sdk \
TIO_OTA_FLASH_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 \
TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_CLASSIC_BINDINGS=1 \
bash official-addon/navs3-edition/build.sh embedded com.rayneo.venus.pub
```

输出 `official-addon/navs3-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib`。请只加载一份扩展，不与历史版本叠加。

使用合法取得、未加密的原厂 **1.0.6（218）Runner.app** 输入；可参照[去签名原厂输入说明](../../official-apps/ios/1.0.6/README.md)。不能使用含个人配置或已打补丁的私用 App。打包器限制宿主哈希、机型/证书/profile、扩展符号及固定 TMG2 固件，保留官方升级流程和门禁。

```sh
node official-addon/navs3-edition/package.mjs \
  --app /absolute/Runner.app \
  --addon /absolute/Turbo-IO/official-addon/navs3-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 --device YOUR_DEVICE_ID \
  --bundle com.rayneo.venus.pub --product iPhone18,2 \
  --amap-sdk-root /absolute/Turbo-IO/official-addon/build/amap-sdk \
  --experimental-ota TMG2 \
  --firmware /absolute/StrixOS-1.0.5.5-TurboIO-TMG2-CANDIDATE-NOT-APPROVED.zip \
  --out /absolute/new-private-package
```

`--product` 填自己的实际机型。打包工具不下载、不安装、不刷机，也不合成官方推送/Apple登录/App Groups权限。Watch App 与可选翻译动态模块仍按各自文档另行构建签名，不能仅凭手机有入口判断它们可用。不要上传打包输出、签名报告或描述文件。

本次默认不把离线地图回归样本打进 App，实际按所选起终点加载路网。若已有 TMG2，NAVS3 只需更新手机端；否则必须遵守[配套固件完整刷写与收尾步骤](../../firmware-research/strix-1.0.5.5-tmg2/README.md#开发者刷写顺序)，不使用旧安装器强刷。

## 离线测试

```sh
python3 official-addon/navs3-edition/test.py \
  --firmware /absolute/StrixOS-1.0.5.5-TurboIO-TMG2-CANDIDATE-NOT-APPROVED.zip
NAVS3_TEST_FIRMWARE=/absolute/StrixOS-1.0.5.5-TurboIO-TMG2-CANDIDATE-NOT-APPROVED.zip \
node --test official-addon/navs3-edition/package.test.mjs
```

仅本机回归，不接触手机/眼镜，不调用网络服务。设备验收应选择自己的起终点、保持手机亮屏，观察连续移动和转弯时周边道路与路名；锁屏另列问题，不用固定演示冒充真实导航。

## 包含与排除

保留通知归档和增强智记的集成源码：只在本机用户开启后保存，真实内容发送模型前须预览确认；本次不附带记录或模型配置，也不声称官方智记已能直接接收通知。情境英语见[授权说明](context-english-v1/README.md)。

微信读书公开版仅书架、统计、封面及有权使用的 TXT/EPUB，不含网页正文适配和 Cookie 导入入口；不是把该适配的第三方许可重新授权为本仓库许可。音乐登录、服务权限自行配置。本机 TTS 保留，作者专属云 TTS 地址移除。Dots 仍未完成，无私人 Bridge、订阅或认证。

不公开个人 Cookie、Key、Apple账号、设备标识、签名材料、私用 IPA、通知/智记/会话或真实路线日志。原创部分沿用仓库非商业许可，第三方权利不变。自定义固件是试验用品，可能无法启动或损坏设备，不保证稳定、回滚与救砖。
