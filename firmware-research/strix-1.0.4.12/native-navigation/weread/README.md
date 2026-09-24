# TWR1 · 四本书架与原生阅读页

2026-09-24 发布。基于 **Strix OS 1.0.4.12**，新增第十一项“微信读书”，保留原有菜单、显示、导航和音乐；原动画在这份固件中缩减为一帧。

> **高风险试验用品，非开发者请勿刷。** 这是验证眼镜端应用、封面显示、文本排版和双向协议的研究，不是稳定阅读产品。不保证回滚或救砖；断电、中断、版本不符或 AP 错误都可能导致无法启动、失去 OTA。只改 AP 不等于只传/只写 AP，也不等于没有风险。

[下载 TWR1 实验固件与校验文件](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-twr1) · [实现思路与效果图](../../../../docs/WEREAD_RESEARCH.md) · [双向协议](PROTOCOL.md) · [发布清单](release-manifest.json)

## 本次包含什么

| 内容 | 发布范围 |
| --- | --- |
| 原创 AP 模块 | 四本书架、64×88 灰度封面、原生文本窗口、手动/自动滚动、双缓冲、生命周期与旋钮过滤 |
| 构建与验证 | 精确版本基线、源代码覆盖层、ARM 模拟、ASAN/UBSAN、ZIP/清单/负载校验 |
| 原创手机模块 | 书架/统计网关、封面缩图、阅读 UI、TXT/EPUB 导入、文本窗口、传输与回执源码 |
| 实刷固件 | 与用户确认更新完成并回到首页的 WEB-03 ZIP 内容完全一致，仅重命名发布附件 |
| 不包含 | 网页正文适配、Cookie 导入/配置入口、用户书籍/书架缓存、Key、账号、签名或私用 IPA |

**不是完整公开手机产品交付：** `phone/` 是独立导出的源码模块，已做单元测试和 iOS 语法编译，但未接入主仓库默认构建、菜单及 TWR1 OTA 打包门禁。当前主仓库 `official-addon/package.mjs` 不能直接打包 TWR1；不要用 TMU1/TNV1 的打包参数或修改校验常量来凑合。没有自己的匹配手机集成时，只做离线构建/协议研究，**先别刷**。本次不提供成品 IPA。

公开手机源码只支持用户自行导入有权使用的 TXT/EPUB 正文；书架 Key 仅用于书架与统计，不会自动取得章节全文。网页适配参考项目与许可边界见[研究说明](../../../../docs/WEREAD_RESEARCH.md)。

## 实测范围与已知问题

- 2026-09-24 用户确认该精确固件更新完成并回到首页；此前书架同步有实机成功反馈。
- 手机端四张封面处理通过；最新版所有封面在镜片显示、正文跨章、长期阅读和所有旧功能回归尚未全部验收。
- **已知问题：长按旋钮返回书架可能异常，尚未修复。** 可先尝试手机退出阅读，不通过重复刷机代替诊断。
- 音乐菜单旋钮过于灵敏的问题仍存在；阅读过滤改动不代表音乐也已修好。
- 系统/LVGL/DMA 在离线测试中使用替身；模拟无泄漏不等于真实系统永不泄漏。App 被系统终止后的恢复没有保证。
- 效果图不是实机验收证据，也不是第三方官方合作声明。

## 1. 下载后只读校验

在仓库根目录运行，需 Python 3；校验脚本不连接设备、不刷写、不修改 ZIP。

```sh
mkdir -p firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads
gh release download firmware-strix-1.0.4.12-twr1 --repo Turbo1123/Turbo-IO \
  --dir firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads
python3 firmware-research/strix-1.0.4.12/native-navigation/weread/verify.py \
  firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads/StrixOS-1.0.4.12-TurboWeRead-TWR1-EXPERIMENTAL.zip
```

- ZIP：9,291,197 B；SHA-256 `a7a1e98dd22bd45a87bba5f8c19862d5fa3a5f0d5877ed4330cca8face75575c`。
- AP：9,544,840 B；SHA-256 `66c88f54c12ad129d8d568261e399350201df47e0ce9904cf8440e03e1f90ab4`。
- AP MD5：`e252514f01d48765136e7a437f6d06ca`。
- 14 个负载中仅 `nuttx_ap.bin` 改变，另外13项与原厂基线相同；清单仅改变 AP 的 Size/MD5，BurnMode/BurnAddr/BurnPath 不变。

MD5/CRC 是校验，不是授权或安全签名。校验成功也不等于已经批准升级。

## 2. 从公开源码复现 AP

macOS + Xcode 命令行工具、Node.js、Python，以及 OHOS clang 15.0.4（LLVM 提交 `39bec79f56c3b5a629e4bacac1dc022e1da552d0`）。可使用 DevEco Studio 随附的对应工具链；其他版本不能当作本次实刷等价物。

```sh
gh release download firmware-strix-1.0.4.12-turbophoto-r3 --repo Turbo1123/Turbo-IO \
  --pattern StrixOS-1.0.4.12-ORIGINAL-rollback.zip \
  --dir firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads
python3 -m venv firmware-research/strix-1.0.4.12/native-navigation/.venv
firmware-research/strix-1.0.4.12/native-navigation/.venv/bin/pip install \
  -r firmware-research/strix-1.0.4.12/requirements.txt
firmware-research/strix-1.0.4.12/native-navigation/.venv/bin/python \
  firmware-research/strix-1.0.4.12/native-navigation/weread/build.py \
  --stock firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads/StrixOS-1.0.4.12-ORIGINAL-rollback.zip \
  --llvm /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin \
  --out firmware-research/strix-1.0.4.12/native-navigation/work/twr1-rebuild-01
```

`--out` 必须不存在，脚本不覆盖旧结果。构建基于相邻 `../src` 加本目录 `src` 的冻结覆盖层，不修改 TMU1/TNV1 的源码或固件。输出 `candidate/payload/nuttx_ap.bin` 必须匹配上面的 AP SHA-256；ZIP 时间戳可能不同，但15个成员须完全匹配。重建 ZIP 不自动获得手机门禁授权；改过源码的新固件必须重新验收。

脚本验证94组原生菜单场景、阅读开关/渲染忙/父对象销毁、导航/音乐/诊断/静态显示回归和独立 AP-only 审计，再执行1000轮缓冲/滚动/回收与视图分配失败测试。最终校验失败即停止，不能改常量跳过。

## 3. 手机模块与本地测试

`phone/ReaderUI.m` 是无网页取正文依赖的公开派生版本；不会影响作者已安装的私用 App。自己的集成可按以下接口接线：

1. 在主线程打开 `TWReaderController()`，配置自己的书架 Key，或者添加原创测试书/导入 TXT/EPUB。
2. 将宿主的文件与业务事件交给 `TWReaderConsume(event)`；它区分设备、SID、回执与文件任务，不要只凭 SDK 提交成功就发下一包。
3. 在语音、音乐、导航、OTA 互斥入口先调用 `TWReaderPauseForOTA()` 并等待真正关闭；语音入口可使用 `TWReaderPauseForVoice()`。不得绕过 OTA 默认锁定。
4. `ReaderBridge` 使用主项目 `ProtocolContext`，`ReaderTransport` 复用已公开显示诊断接口；需要主项目和 `../music/phone` 的依赖，不是可单独装进官方 App 的插件文件。
5. 移植完成后先测原创短文、四本分页、返回、断线与缓冲回收，再验证自己的内容。没有集成完成前不要刷固件期待自动同步。

```sh
python3 firmware-research/strix-1.0.4.12/native-navigation/weread/test-phone.py
python3 firmware-research/strix-1.0.4.12/native-navigation/weread/test-verify.py \
  firmware-research/strix-1.0.4.12/native-navigation/work/twr1-downloads/StrixOS-1.0.4.12-TurboWeRead-TWR1-EXPERIMENTAL.zip
```

手机测试使用原创合成正文，验证 TXT/EPUB spine、UTF-8换行、有界窗口、统计缺值、SDK提前回调、ACK＋文件终结、退出后新SID；实际传输源文件单独编译。可传 `--trace /absolute/new-trace.json` 输出合成包，再用重建目录 `weread-v1/test_reader_arm.py CANDIDATE --phone-trace TRACE` 回放；运行时将对应 OHOS LLVM bin 加入 PATH。不请求账号，不联网，不操作手机或眼镜。

## 许可归属与发布边界

| 内容 | 许可归属 |
| --- | --- |
| 原创 AP 阅读模块、双向协议、手机书架/本地阅读、构建与测试 | 仓库 [PolyForm Noncommercial 1.0.0](../../../../LICENSE)；仅非商业学习研究 |
| `finlater/weread.koplugin` 参考项目及其网页正文移植 | 保留上游 AGPL-3.0，**不在本次源代码或固件内发布该适配**，不套用本项目非商业条款 |
| 原厂固件、LVGL及其他第三方代码/资源 | 保留各权利人版权及原有许可；发布的是原创补丁和研究用固件，不声称拥有原厂系统源码 |
| 用户凭据、书籍缓存、聊天、签名和私用 IPA | 不发布；下载方使用自己的内容、配置与签名 |

本固件只接收手机已准备的封面/文本，不登录微信读书，不携带章节获取代码或账号会话。公开 ZIP 未经重新编译或改字节“脱敏”；它与实刷成品相同，隐私扫描针对附加模块与完整归档，原厂 PEM 类型识别字符串不是维护者的私钥。原厂内容与公开素材的既有许可不变。
