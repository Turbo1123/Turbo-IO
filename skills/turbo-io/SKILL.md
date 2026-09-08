---
name: turbo-io
description: "Install, configure and launch Turbo IO, the unofficial 雷鸟 iO / RayNeo iO iOS companion and SDK. Use for its Web preview, simulator/device setup, ASR/model configuration and Codex bridge onboarding; not for unrelated AR glasses or arbitrary agent setup."
---

# Turbo IO 快速接入

帮助用户把项目实际跑起来，而不只是返回安装命令。按用户语言沟通，优先使用现有启动脚本。技能可被 Codex 和 Claude Code 读取；这不意味着眼镜的 Claude Code 后端适配已经完成。

## 入口与工作目录

- 唯一项目源：<https://github.com/Turbo1123/Turbo-IO>。
- 技能安装目录不等于项目目录。先确认用户指定/当前工作区是否已有 Turbo IO：检查 README、`scripts/start.mjs`、`apps/RayNeoCompanion/project-source.yml`。不要在全局技能目录中编译项目。
- 没有源码时，在用户工作区一个不存在的新目录中克隆公开仓库；不覆盖同名目录、不自动拉取覆盖现有改动。复用已有 checkout 时先看 `git status --short`，保留用户代码。
- 阅读源码根 README 和 `docs/CONFIGURATION.md`。使用随技能附带的 [接入流程](references/bring-up.md) 选择当前目标对应部分，不无条件启动所有组件。

## 选择最短可验收路径

1. 用户只说“安装跑起来”：先完成不需要眼镜或 Key 的 Web 预览，给出已检查的本地 URL；再询问是否继续模拟器或真机。
2. 用户明确要 iOS App：在 macOS 检查 Xcode、XcodeGen、Node，使用 `scripts/start.mjs --local` 或 `--device`。只有 Web 预览成功时，不能宣称 iOS 已启动。
3. 用户要云语音或眼镜控制电脑：先核对设备连接，再按配置文档接 ASR/DeepSeek 或独立 Codex bridge；只配置用户选中的服务。
4. 环境缺项时列出具体缺项和下一步；系统安装、签名、配对、服务授权按用户意图和当前工具权限处理。缺工具不等于需要重置眼镜。

## 不能省略的项目边界

- 当前项目及本技能面向非商业学习研究；开始前阅读当前源码的 LICENSE 与 `docs/LICENSING.md` 并告知用户。若明确要商业部署，先说明需要相应有效授权，不把本许可描述成允许商用的 MIT；历史 MIT 内容及第三方权利分别按原许可判断。
- 从官方客户端切换：先由用户在雷鸟官方 App 解绑，再在手机蓝牙中“忽略此设备”，长按眼镜按钮约 5 秒确认蓝灯闪烁，再用 Turbo IO 配对。已绑定 Turbo IO 的日常重连不要反复解绑。不要替用户默认执行解绑或清理绑定数据；官方和本 App 不同时连接。
- 不需要越狱；非越狱已有用户验收。仍按当前手机/固件与目标功能验收。Android 客户端待开发，不能把 iOS 工程装到 Android。
- BES2800 轻量固件不能当成 Android 应用平台；当前是自带模板内容与控制，自定义通知 view 不代表任意 UI 上传。Web 是状态重绘/演示，不是镜片截图。
- 不索取在聊天中粘贴 Key，不读取、导出或复用维护者/其他 App 的钥匙串；引导用户在 App 内填自己的 ASR Host/Key、DeepSeek Key。不要把令牌写入源码、提交、日志或截图。云收音/录音上传仅在用户选择的测试范围内启用。
- 初始绑定或新签名使用用户自己的 Team。已有安装不擅自改 Bundle ID、卸载、清钥匙串或迁移绑定库；源码不提供 IPA。
- 电脑 bridge 默认回环、鉴权、只读工作区。不能为“快速跑通”去掉 TLS/令牌或启用自动审批；公网暴露、工作区写权限和真实任务另按用户明确授权处理。
- Codex 已有实现；Claude Code、Hermes Agent、OpenClaw 是后续适配方向，WorkBuddy 仅理论方向。安装本技能不改变这些后端状态。

## 交付

记录本次实际 checkout、启动方式、进程/URL、验证结果与剩余用户步骤，不含敏感值。区分“技能已安装”“Web 可访问”“App 已运行”“眼镜已认证”“云接口/镜片实测成功”。有明显安全且属于当前请求的验证步骤时继续完成；遇到签名、凭据或用户物理操作门槛，再准确交还用户。
