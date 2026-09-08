# 用技能引导安装 Turbo IO

仓库提供标准 Agent Skills 目录 `skills/turbo-io`，供 Codex 与 Claude Code 读取。用途是非商业学习研究的环境检查、源码获取、Web 预览、iOS 编译配置和 Codex bridge 接入，不包含密钥、IPA，也不会绕过签名与用户授权。许可见 [LICENSING.md](LICENSING.md)。

## 一行安装

前提：已安装 Node.js/npm，以及准备使用的 Codex 或 Claude Code。以下命令使用第三方开源安装器 Vercel Skills，固定版本；请先检查本仓库技能内容再安装。

```sh
DISABLE_TELEMETRY=1 npx --yes skills@1.5.24 add Turbo1123/Turbo-IO --skill turbo-io -g -a codex claude-code --copy
```

`-g` 是用户级安装，`--copy` 复制完整技能及参考文档，安装器保留目标确认。若已有同名技能，先备份或比较，别盲目覆盖。只用一个助手时将 `-a codex claude-code` 改为 `-a codex` 或 `-a claude-code`。去掉 `-g` 则安装到当前项目，适合不想更改全局配置的用户。

新开助手会话，输入：

> 使用 turbo-io 技能，帮我以非商业学习用途安装并启动 Turbo IO。先检查环境，跑不需要眼镜和 Key 的 Web 预览，确认可访问后告诉我下一步如何编译 iOS。

Claude Code 可显式使用 `/turbo-io`；Codex 可在技能选择器选中它或显式提及 `turbo-io`（CLI 也可用 `$turbo-io`）。如果未发现技能，重启助手后再检查。

## 手动安装

不使用安装器也可以克隆仓库，将 **整个** `skills/turbo-io` 文件夹复制到以下其中一处；目标已存在时先比较，不覆盖个人修改：

| 助手 | 当前项目 | 用户级 |
| --- | --- | --- |
| Codex | `.agents/skills/turbo-io` | `~/.agents/skills/turbo-io` |
| Claude Code | `.claude/skills/turbo-io` | `~/.claude/skills/turbo-io` |

参考文档、许可与通知也要一起复制，不只复制 SKILL.md。技能目录不是源码工程目录，实际运行会另行获取完整仓库。

## 它会做什么，不会做什么

1. 核对当前目录与已有改动；没有源码时克隆到新目录，不覆盖旧工程。
2. 默认先启动 `node display-observer/server.mjs --no-proxy`，验证 `http://127.0.0.1:8790/`。不需要眼镜、iproxy 或云端 Key。演示画面不冒充真实镜片画面。
3. 明确要 iOS 时再检查 macOS、Xcode、XcodeGen，调用现有启动脚本；模拟器与真机分开验收。
4. 真机由使用者提供自己的签名 Team；切换官方绑定时先官方解绑、蓝牙忽略、蓝灯配对，日常重连不重复重置。
5. 按需配置 ASR、模型与电脑 bridge，Key 在自己的 App 中填写，不粘贴到聊天、源码或提交中。

**技能安装成功不等于 App 已装到 iPhone，更不等于眼镜已认证、云接口已通过。** 助手应明确报告每一步实际结果与用户签名、凭据或物理操作门槛。技能不提供自动批准电脑高风险操作的权限。

Claude Code 可以用这个技能帮助开发运行项目，但“眼镜语音调用 Claude Code 后端”仍未实现；当前已打通的电脑 Agent 后端是 Codex。不要把两种集成混为一谈。

## 更新和验证

更新前检查上游变化并备份自己的技能修改，再重新运行安装命令。技能结构校验与隔离项目级安装不代表两个助手都已完成自动真机安装；硬件/云配置仍按 [配置文档](CONFIGURATION.md) 单独验收。

格式和安装方式参考：[Codex Skills](https://learn.chatgpt.com/docs/build-skills)、[Claude Code Skills](https://code.claude.com/docs/en/skills)、[Vercel Skills 安装器](https://github.com/vercel-labs/skills)。
