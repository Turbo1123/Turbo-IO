使用 Turbo IO 的 turboio-developer Skill，为我开发「代码待办」眼镜小应用。
先阅读仓库 docs/DEVELOPER_ECOSYSTEM.md 和 dashboard-service/README.md。
模板 ID：repo_tasks；参考 MCP 项目：https://github.com/oschina/mcp-gitee。
目标：读取仓库 Issue/PR 状态，不提交代码。配置需求：Gitee 只读 Token 与仓库范围，密钥仅在我自己的后端保存，不写进 ZIP/GitHub。
先在我的电脑完成 MCP tools/list，核对当前工具名称、输入和权限，仅调用我授权的只读工具；不要假设上游文档中的字段始终不变。
把实际结果映射为 headline、lines（1–4条、每条最多80 UTF-8字节）、observedAt（带时区ISO时间），只保留我要展示的字段。
先用离线样例跑通，再用我的真实结果构建快照：turbo-app gallery build repo_tasks --data snapshot.json --version 2 --out my-app.zip。
执行 turbo-app check、preview；提供 ZIP、SHA-256、来源、数据时间和映射测试。
TAP1 是 540×180 的有界原生组件，ZIP解压总计20KiB，最多4页；不在眼镜执行JS/HTML/MCP。
当前 App v1 为快照安装，不承诺后台实时刷新、按钮事件回流、音频播放或自动安装。修改已安装同ID包必须递增version。
给出手机「应用广场 → 我的应用 → 导入ZIP → 预览 → 查询 → 确认安装」步骤；不要刷固件或自动调用付款/下单/发消息等写工具。
如果缺少真实授权，只交付明确标注示例的版本并说明缺项，不伪造联网成功。
