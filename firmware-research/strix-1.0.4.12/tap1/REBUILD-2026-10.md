# TAP1 树 2026-10 重编说明：导航路况扩展 + 模块剔除 + 容器探查

本批对 `tap1/source` 快照的修改，用于镜上 TAP1-TEST-01 同源固件的下一版重编。
**尚未构建、尚未刷写**。

## 云 Mac 构建命令（一键脚本）

前置：OHOS LLVM 15.0.4（DevEco Studio 的 OpenHarmony native llvm/bin）、node、原厂 rollback ZIP（Release `firmware-strix-1.0.4.12-turbophoto-r3` 的 `StrixOS-1.0.4.12-ORIGINAL-rollback.zip`）。

```sh
git clone <本仓库地址> && cd Turbo-IO   # 或已有仓库 git pull
bash firmware-research/strix-1.0.4.12/tap1/build-tap1.sh \
  /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin \
  /absolute/StrixOS-1.0.4.12-ORIGINAL-rollback.zip \
  /absolute/fresh-output-dir
```

产物在输出目录 `candidate/` 下；脚本尾打印新 AP 的 SHA-256——记入下面刷机清单第 1 条。
构建器自带符号断言（无未解析符号）、AP 尺寸与分区描述符断言、15 成员清单校验。

## 改了什么

1. **导航路况扩展**（与主树 36408fe 同源）：navigation-runtime-v1 六件升级为 36 字节可选协议尾部版本；visual/view 与主树的差异是本树独有的 ETA 时钟（`tn_clock_text`/`tn_view_clock`）与扩展字段**合并共存**——text[4] 仍由时钟复用，路况柱 @(112,134)、提示行 @(400,134)/(400,158)。
2. **全剔除 didi-v1（滴滴沙箱演示）与 app-runtime-v1（我的应用/四槽运行时）**：
   - 菜单 14→12 项（`names[]` 删「滴滴出行」「我的应用」；四项同屏页码 4→3）；
   - `TNNavSlot` 删 `ride`/`apps` 字段（sizeof 56→48、quad 偏移 44→40，`_Static_assert` 已同步）；
   - 存活服务（导航/番茄/音乐/微信读书/菜单）的显示占用互斥、文件/消息分发、滚轮/事件门全部摘除对应分支；
   - 构建清单（units）与 sourceInputs 同步摘除；模块目录整删。
   - TAP1/TAX1 传输协议常量与 `tap_fs_*` 链接别名保留（无人引用即无害，删码最小化）。
3. **容器尺寸探查**：导航会话首次建视图时经 `native_log` 打一条 `[TurboNav] container=<w>x<h>`（launcher surface 真实边界），用于结案 540×180 是否为全部可视区。
4. 顺带修复：`deleted()` 事件回调清视图指针漏 `bar` 画布（扩展引入的遗漏）。

## 刷机安全清单（每次执行前逐条核对）

1. 固件 ZIP 构建产物先过脚本审计（本树 `source/official-addon/research/audit-tap1-candidate.py`，`build-tap1.sh` 第 4 步已自动执行并产出 `candidate-audit.json`）；**哈希与 TAP1-TEST-01 不同是预期的**（源码已变），但清单里仅 `nuttx_ap.bin` 一项改变的结构必须保持。
2. **升级顺序：先装新 IPA（dylib），后刷眼镜固件**。旧 dylib 发的扩展尾字节 e+34/35 从未初始化，新固件会把它当红绿灯距离渲染出假标记；两边都换新后该窗口关闭。
2. 眼镜电量充足（>50%）；手机端停止全部会话（导航/字幕/音乐/番茄/OTA 查询页）。
3. 刷写中保持蓝牙距离与静止；**禁止**同时进行 OTA 之外的任何眼镜操作。
4. 保留一份哈希核验过的原版 1.0.4.12 ZIP 与 TAP1-TEST-01 ZIP 用于回滚重刷（回滚不是救砖保证，仅最优先恢复手段）。
5. 刷后首验：菜单 12 项、无滴滴/我的应用；开一次模拟导航看路况柱/提示行；日志查 `[TurboNav] container=` 读数。
6. 任何异常（菜单空、导航拒绝、无法唤醒）→ 直接回滚重刷原版，不带病调试。

## 已知边界

- 本机已验证：导航 codec/visual/view gcc 测试全绿（四树矩阵）、被改 C 文件三组括号配平零差、弯引号零命中、构建脚本 python 语法通过、模块外引用零残留。
- **未验证**：OHOS clang 真实编译、arm 测试（test_service_arm 等）、镜像链接（云 Mac）、真机（一切以肉眼为准）。
- 手机侧插件不带 `TIO_APP_SDK` 宏构建即无应用广场入口，无需改手机端代码。

## 2026-10-14 本机复检（构建前必读）

复检发现并修复/待办如下，云 Mac 构建前逐项确认：

1. **已修·构建脚本**：`build-tap1.sh` 原在 `cd $OUT/...` 后用相对级数反推仓库根（仅当输出目录恰埋在仓库内两层深才碰巧正确）——已在进入输出目录前捕获 `$PWD`；并补参数个数检查。
2. **已修·菜单滚轮几何**：`menu10.c` 剔除两模块时帧几何仍按 14 项（`clamp(index,0,13)`、帧上限 419/405、滑条 14.0f、`app_id` 残留 12/13→TurboRide/TurboApps），滚轮可滚进两个空白死位。已按 9 项树同款公式改为 12 项（帧上限 359=15+30×11+14，滑条 12.0f，app_id 止于 11）。
3. **已修·menu10.c 编译断点**：`m8_hook_names` 开头整段 `TAPMenu *a=apps(app)…"我的应用"` 行残留（apps()/TAPMenu 已随 app-runtime-v1 删除，引用即编译失败）——已整行摘除。
4. **已修·_Static_assert 误改**：`focus_menu_native.c` 的 `offsetof(TNNavSlot,quad)` 断言被从 44 改成 40；实际 32 位目标下删字段后 quad 偏移仍是 44（10 指针 40B + back_until），只有 sizeof 56→48。已用 `-m32` 模型实证并改回 44/48。
5. **已修·缺失头文件**：`diagnostics-v1/` 五个头（command/diagnostics/diagnostics_service/native_light/stock_abi）与 `dashboard-editor-v1/editor.h` 从未进过 git，已按字节相同的 .c 消费方分别从 focus 树与主树拷回。
6. **已解除·遗失文件（2026-10-15 改为摘除）**：`dashboard-v1/card.h` 与 `icons.inc` 全仓库及 git 历史均不存在（67ac6e2 引入 .c 时即未提交）。复查确认该模块是**作者自用的 TDC1 模板卡拦截器**（"Codex Pro/Claude Max"服务监控卡：surface 名字面量无源、图标为设计产物、任何用户卡都不会命中该分支），重建既不可能也无收益——已整模块摘除（目录删除、构建清单移除），`dc_text` hook 的 TCE1 前置分流（`tce_owns → tce_native → stock`）已并入 `dashboard-editor-v1/editor_native.c`，**用户的 TCE1 仪表盘渲染不受影响**。阻塞解除，可执行构建。
7. **已修·报告元数据**：构建器 `menuProfile` 仍为 `native-fourteen-TAP1`，已改 `native-twelve-TAP1`（全仓无其他引用）。
8. **已解除·独立审计（2026-10-16）**：新增本树专用 `tap1/source/official-addon/research/audit-tap1-candidate.py`（kind 锁 `TAP1-developer-runtime-experimental-candidate`、菜单锁 `native-twelve-TAP1`、`focusProfile.menuIndex==11`；字节级复核 changes 白名单/模块零填充分区/build-info 原文/7+6 入口跳板与回跳/trampoline 回读/ELF 无未定义符号/14 行清单 13 项不变/ZIP 回读；**剔除验证**：sourceInputs 不得含 didi-v1/app-runtime-v1/dashboard-v1，focus_menu.c、focus_menu_native.c、menu10.c、nav_view.c 四个 12 项/路况关键源按 SHA-256 钉住）。`build-tap1.sh` 第 4 步自动执行并产出 `candidate-audit.json`。审计只证字节，不替代云 Mac ARM 模拟与真机验收。
9. **新增本机验证基线**：上述修复后，全构建单元通过 `gcc -m32 -fsyntax-only`（构建器同款 -D 宏组合；host gcc 非目标 clang，仅作语法/断言级证据）。2026-10-15 摘除 dashboard-v1 并并入 TCE1 分流后复跑：**29/29 通过**（清单少两件属预期）。

10. **2026-10-16 增补·构建断链修复 + 智记共存（TLC1 移植）**：
    - **构建断链（阻塞级）**：`build-tap1.sh` 原裸调构建器，`nav_*` 17 个符号（nav_top_app/nav_business_idle/nav_monitors 等）无别名注入，链接必失败（此前 30/30 仅为语法级，未链接）。修复：heredoc 内 `import menu10_profile; mod.native_menu=menu10_profile`（对齐作者 build_candidate.py 手法），链接闭合已用 gcc -m32 编译 + nm 逐符号验证（唯一残项 umoddi3 为 host -O0 伪影，clang 常量强度削减消除，TAP1-TEST-01 同行已真机跑通）。
    - **菜单弹簧 14→12**：`menu10_profile.py` PATCHES 原为 14 项常量（13.0/13.4667），与 12 项菜单不符（滚轮可入两个空白死位）。按作者 count-1 公式改 11.0/11.4667；11.0 的 VMOV 立即数编码 `f2ee067a` 由 6.0=0x18/7.0=0x1c/8.0=0x20/13.0=0x2a 四锚点反推公式验证。
    - **智记共存（TLC1 移植）**：原厂 `LauncherAPI::isBussinessIdle`(0x106d334c..0x106d33f6) 把"全天智记开关开启"当忙碌，导航/音乐/读书/番茄全部拒绝打开（用户痛点：开导航前必须退所有任务）。按作者 TLC1（lifelog-coexist，2026-09-30 真机验证）方案：构建器把该函数重定位进本模块为 `nav_business_idle`（`display-idle.S`，仅略过 0x106d336e 的 `bl 0x106d308c`(isLifeLogEnabled) 拒绝分支，外部跳转/字面量按 TLC1 build.py 同款重定位），四服务别名自动指向宽松副本；**诊断服务拆到严格门**（diagnostics_service.c 改 extern diag_business_idle → 原厂函数，与 TLC1 的 DIAGNOSTICS 保留集一致）。相对 TLC1 的 AP 补丁式做法，本方案模块内自含、AP 零新增补丁点。前台占用/折叠/配对/助手活动检查全部保留；录音前台占用仍会拒绝（设计如此）。首次构建即验证重定位副本（断言逐指令）。
    - **审计同步**：`audit-tap1-candidate.py` 改 import menu10_profile（钩子/补丁集与真实构建一致）。
11. **2026-10-16 增补·刷机链路闭环（iOS 门禁认领本固件）**：既有链路三处钉死 FOCUS-04（dylib 候选描述/内嵌 TurboWeReadCandidate.zip/打包脚本硬编码校验），自建 TAP1 ZIP 无一端认领会刷不进去。修复：①`make-ota-candidate.py` 从构建产物自动生成候选描述（zip/AP/15 pins/AP md5 全取实产物，flash_check 结构自校验，合成目录烟测通过）；②`build-tap1.sh` 第 4.5 步自动产出 `candidate-ota.json`（confirmToken=TAP1-2026-10）；③`build-local.sh` 支持 `TAP1_FW`+`TAP1_CANDIDATE` 环境变量（透传 TIO_OTA_CANDIDATE 给 dylib 构建、注入新固件、候选校验），不设时回落 FOCUS-04 原流程；④`focus-adhoc-package.mjs` 可选第 5 参候选 JSON（按其 zip.size/sha256 校验，缺省保持 TFP1 兼容）。刷机入口更正：客户端构建一直用根目录 `build-local.sh`（等价 CI 勾选 focus+amap+app_sdk），`focus-edition/build.sh` 只是其内部第 4 步。
