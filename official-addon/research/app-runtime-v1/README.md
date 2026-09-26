# TAP1 App SDK · 原创协议与手机模块

2026-09-26。本目录是可测试的协议/解码/内存/手机参考模块，**不是独立 App 或完整可刷固件工程**。完整开发入口见 [开发者教程](../../../docs/DEVELOPER_ECOSYSTEM.md)。

## 可以直接运行

在仓库根目录：`uv run --directory dashboard-service pytest -q`。
Python/JS 工具可生成 ZIP、校验、SVG 预览；C 模块由实际编译器执行 ASan/UBSan 测试；Objective-C 编解码与后端约束测试需 macOS。无蓝牙、无账号、无官方 IPA 或硬件写入。

## 手机模块如何接入

`AppUI` 提供 `TAPAppsController()`，接入自己插件首页“应用广场”；`AppGallery.inc` 提供20模板详情/导出/复制提示词。`AppPackage` 严格校验 ZIP，`AppTransport` 编码 TAX1，`AppBridge` 管理已配对设备、会话、文件完成与设备回执。

1. 将 AppUI / AppPackage / AppTransport / AppBridge 的 `.m/.h`、`AppGallery.inc`，以及 `app.c`、`app_command.c`、`app_runner.c`、`app_store.c`、`app_view.c` 和对应 `.h` 加入现有 iOS 插件目标。沿用宿主已有 `ProtocolContext`、`ExperimentalOTAFlash`、`ResearchUI`；接口头可在 `official-addon/focus-edition/` 找到。链接 Foundation、UIKit、UniformTypeIdentifiers、Security、zlib。不要把新门禁函数改为常量“允许”。
2. 在 `dashboard-service/` 用 `uv run turbo-app gallery export --out NEWDIR` 生成资源，将目录原样作为 `TurboIOGallery/` 放入 App bundle，保留目录结构。用 `uv run python -m turbo_dashboard.app_examples --out NEW_BUILTINS_DIR` 生成四个基础示例资源，将四个 `TurboAppSDK*.zip` 放到 bundle 根目录。
3. 现有宿主插件提供当前配对设备与 Flutter 方法调用；在**实际文件事件路由**中把事件交给 `TAPObserveEvent(event)`。不能只接按钮而漏掉文件完成回调。每次传输必须同时等文件完成及匹配 request/session 的 TAX1 回执。
4. 眼镜必须已经具有匹配 TAP1/TAX1 的接收、存储和 LVGL 运行时。这里的 portable 模块本身不向官方固件植入入口；公开旧 FOCUS-04 没有这些功能。缺少匹配运行时应停在主机预览，不发送未知文件或改其他分区。
5. OTA 期间禁止发送；结果未知不盲重试；换设备、旧会话、缓存回执均不能当成功。保留查询 → 预览 → 人工确认 → 精确包安装的门禁。

手机 UI 已在隔离模拟器通过20模板预览、四个基础示例、12个桥接场景；真实蓝牙未由模拟器验证。当前未实现 TAE1 后端事件权限绑定，因此不向服务器转发该类事件。

## 公开范围

发布原创协议模块、四槽存储/单实例/视图资源所有权及测试、手机模块。LVGL ABI 参考头只是测试/集成接口，不是官方 SDK 源码。未包含私人配置、API Key、Cookie、签名、IPA、官方 Runner 或实验 OTA。许可证沿用仓库 LICENSE；第三方 MCP 仅链接引用，需单独遵守其许可和授权。
