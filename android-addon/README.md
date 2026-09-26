# Turbo IO Android 扩展

在 Android 官方雷鸟 App 内加入自有模型、搜索、录音导出与眼镜导航。**这是给开发者使用的非商业研究源码，不是现成 APK，也不是已经完成的独立 Android SDK。** 不熟悉 Android 构建、签名与排错，请继续使用官方 App。

[返回项目首页](../README.md) · [验证记录](docs/VALIDATION.md) · [非商业许可](../LICENSE)

**获取 Android 官方 App：[雷鸟 AI Android 官方下载入口](https://rayneo.cn/commonPage/venus/appDownload/index_m.html)**。将此链接、仓库地址和[首页提示词](../README.md#让-claude-code--codex-帮你接入)一起交给 Claude Code / Codex，即可按本教程引导检查、构建与配置。页面可能提供更新版本，仍需通过下方SHA校验；不是不经验证就能合并。详见[完整AI接入说明](../docs/AI_SETUP.md)。

## 1. 可以做什么

| 能力 | 当前状态 |
| --- | --- |
| 保留官方配对、连接和语音识别；普通问答换成自有模型 | Root 研究设备已确认回复显示正常 |
| OpenAI 兼容 Chat Completions、SSE 流式回答、会话内插话、回答结束关闭 | 已有研究设备用户验收；不同服务需各自验证 |
| TinyFish 联网搜索 | 实际工具调用及回答已由用户确认；需自己的 Key |
| 自定义提示词、最近50条成功问答消息上下文 | 已实现，默认无个人身份；上下文在进程内 |
| 对话 Markdown、本机录音选择与系统分享 | 录音导出已由用户确认；不读取全部官方聊天历史 |
| 高德地图搜索、长按地图选终点、步行/骑行/驾车规划 | 三种在线规划已返回路线 |
| 路段文字、距离 → 眼镜持续显示 | 真实路线文字已由用户确认；户外跟随未验收 |
| 模拟导航、暂停/继续、1/2/4/8倍速 | 代码和自动测试通过，新增模拟模式尚未真机验收 |
| Codex 知识库查询 / 任务状态 Tools | 已有适配代码，Android 端到端尚未验收 |

尚未完整移植 iOS 的新闻提词器、待办双向、全天智记数据库转写导出、APNs/主动通知等功能。导出页可以选择已落盘的音频/文本，不代表能重建完整全天智记会话。不把 iOS 成功记录当成 Android 验收。

## 2. 兼容与安装边界

- 官方 App：Android **雷鸟 AI 1.0.4（195）**，包名 `com.rayneo.venus.pub`，ARM64，官方最低 Android 10 / API 29。
- 合并输入 SHA-256：`ef2e7dd346ca478e13d0f3f1bf31fa61412e44fb9b4ca9cf0d3e864ac608584b`。版本号相同但内容不同也会拒绝；不要跳过检查。
- 前期业务验收来自 Android 12 ARM64 Root 研究设备；**2026-09-15 用户进一步确认非 Root 设备已实机测试可用**。不再要求Root才能使用；不同机型、签名/地图服务与长期稳定性仍按自己的环境复核。
- Root 不是原创 Java 业务代码的必要依赖；它用于当前研究加载。合并工具生成普通 DEX/APK，不等于已证明所有非 Root 手机可用。
- 这是**宿主内扩展**：沿用宿主连接，不需要按 V1 独立 SDK 的步骤先解绑。不要同时运行 V1 或其他手机争抢同一副眼镜；跨手机换绑仍由官方流程处理。
- 不修改眼镜固件或内置页面布局。导航复用字幕显示模板，不是投屏，也不是把 Android App 安装到眼镜。

我们只提供原创扩展源码、测试和本地合并工具，**不提供官方 APK、修改版 APK、预签名安装包、厂商反编译源码、账号或密钥**。输入包由使用者自行合法准备；所有生成物留在本机 `build/`，不要上传到 Issue 或 Release。

## 3. 编译与本地合并

依赖：JDK 17、Node.js 20+、Android SDK platform 36 / build-tools 36.0.0、apktool 2.12.1、`zip` / `unzip`。本地构建使用命令行，不需要 Gradle；构建工具由使用者安装，仓库不附带二进制。当前合并验证环境是 macOS。

在仓库根目录执行（SDK 目录换成自己的）：

```sh
export ANDROID_SDK_ROOT="/path/to/Android/sdk"
# 若尚未安装对应组件，使用 SDK 的 sdkmanager：
sdkmanager "platforms;android-36" "build-tools;36.0.0"

bash android-addon/build.sh
node android-addon/package.mjs /path/to/RayNeo_AI_1.0.4.apk
```

第一步运行73项检查，生成原创 `android-addon/build/dex/classes.dex`。第二步校验输入包、保留原回调方法并增加桥接，输出 `android-addon/build/TurboIO-RayNeo-1.0.4-unsigned.apk`。只编译原创 DEX 不需要官方 APK。

### 自己签名（非 Root 设备已验证可用）

使用自己的 keystore；不要把签名密码写进命令或仓库。以下命令由工具交互询问密码：

```sh
"$ANDROID_SDK_ROOT/build-tools/36.0.0/zipalign" -p -f 4 \
  android-addon/build/TurboIO-RayNeo-1.0.4-unsigned.apk \
  android-addon/build/TurboIO-RayNeo-1.0.4-aligned.apk
"$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner" sign \
  --ks /path/to/your-release.jks \
  --out android-addon/build/TurboIO-RayNeo-1.0.4-signed.apk \
  android-addon/build/TurboIO-RayNeo-1.0.4-aligned.apk
"$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner" verify --verbose \
  android-addon/build/TurboIO-RayNeo-1.0.4-signed.apk
```

原厂签名不能保留。**不同签名无法直接覆盖已安装的官方 App；不要为了安装贸然卸载而丢失录音或登录数据。** 请先备份，在可恢复的测试设备上自行决定安装方案，再使用 `adb -s YOUR_DEVICE_SERIAL install /path/to/signed.apk`。本项目不绕过登录、签名校验、证书校验或服务授权，不保证重签后厂商服务继续工作。

运行时研究用的私人设备脚本、调试服务器和设备标识不发布；公开使用路径是上述本地编译/合并，不要求连接维护者的设备或服务。

## 4. 配置模型与工具

扩展入口位于官方主界面的 **Turbo IO** 按钮，Android 当前没有新增底部 Tab。

1. 打开「模型与对话」，可先选“随机测试回复”，确认镜片链路，再切“自有模型”。
2. 填写完整 HTTPS Chat Completions URL、账户实际可用的模型 ID、自己的 API Key。DeepSeek 地址为 `https://api.deepseek.com/chat/completions`；默认模型字符串只是可编辑示例，不保证所有账号可用。
3. 按需编辑个人提示词。请求默认关闭思考、开启 SSE、最多2048输出 tokens；其他服务需兼容实际请求字段。
4. 在「联网搜索与知识库」填写自己的 TinyFish Key 并开启搜索。只有已启用且有凭据的工具才注册给模型；这是扩展的 `web_search` 函数工具，不是模型厂商内置搜索。
5. 知识库可选：先按 [Mac 桥接说明](../official-addon/knowledge-bridge/README.md) 启动自己的服务，再填 HTTPS `/api/turbo-knowledge` 地址和令牌。Android 目前仅接只读 query / status / sources，手机到电脑全链路仍需验收。不要填写维护者的地址。

默认使用官方模型、搜索/知识库关闭。所有 Key 输入为空，不提供测试 Key。Android Key 以 Keystore AES-GCM 加密存储；不显示已有 Key、不写进源文件或调试输出。新填空值表示保留已存的 Key，不是清空；停用能力使用开关，泄露的 Key 应到服务商撤销。

官方 ASR 继续走官方流程，不需要另配阿里 ASR Key。自有模型模式**不等于完全绕过官方云**：当前等待官方普通问答模板再替换回答，官方识别/模板链路仍可能依赖网络。

## 5. 导航怎么用

1. 结束录音、提词、字幕及语音任务，确保官方 App 已连接眼镜。
2. 进入「Turbo IO → 导航」，同意地图/定位，搜索地点并点选，或长按地图选终点。
3. 点击“定位我的位置”，选择步行 / 骑行 / 驾车，规划并选择路线。
4. **真实模式**：点“开始前台导航并显示到眼镜”。定位弱时先显示路线概览；实时转向需15秒内、精度不差于50米的位置，静止不会自动跑段。
5. **模拟模式**：点“开始模拟导航并显示到眼镜”，选择1/2/4/8倍速，可暂停、继续。沿已规划折线推进，手机和眼镜标注“模拟 / 非真实位置”，不修改真实 GPS。基础速度约为步行1.4、骑行4.17、驾车11.11米/秒。
6. 点“停止导航 / 关闭眼镜显示”。如提示上一轮退出待确认，先实际确认眼镜已回首页，再确认继续；无需每次操作官方字幕页。

手机约每秒刷新，镜片文字约3秒节流，不是逐帧同步。模拟到达约8秒后请求关闭；**所有显示仍有4分钟保护，暂停也计时**。长路线可选择更高倍速或近处终点。离开前台、切换路线或显示通道结束会停止模拟。

地图调用宿主已有的高德公开 SDK。**重签后的包名/证书可能使原 Android 高德配置失效；iOS Key 不能通用，也不能保证原宿主配置能继续用。** 当前无独立 Android 高德 Key 设置页；重签地图授权适配仍待开发。错误码、搜索/算路失败应单独排查，不要拿固定“7392”显示测试当作地图可用。

这是“路线 + 定位 + 文本显示”的前台研究指引，**不是完整专业导航引擎**；未实现车道级提示、自动偏航重算或长期后台，不能作为驾驶时唯一依据。

## 6. 源码结构与后续方向

| 文件 | 职责 |
| --- | --- |
| `TurboAddon.java` / `ChatPolicy.java` | 官方回调主线程桥接、问答接管、SSE、历史与设置 |
| `SecretStore.java` / `ToolClient.java` | 本机密钥、按需注册搜索/知识库工具 |
| `RecordingExports.java` | 只读扫描与副本分享，不删除原件 |
| `NavigationUI.java` / `NavReflect.java` | 手机地图、规划、定位与宿主 SDK 适配 |
| `NavGlasses.java` | business 19 显示会话、同 SID 回执、节流与退出 |
| `NavCore.java` / `NavSessionPolicy.java` / `NavSimulation.java` | 可脱离 Android 测试的几何、状态门禁和回放 |
| `TurboStyle.java` | 原创原生界面样式 |
| `package.mjs` / `tests/` | 固定版本本地合并与回归检查 |

下一步：扩大非 Root 设备与高德配置覆盖、模拟导航镜片验收、户外跟随/断连/退出、长期稳定性，再逐项移植待办、提词器、全天智记和其他 Agent。欢迎提交**脱敏**复现步骤，不要附 Key、个人录音、聊天、设备标识或官方包。

原创代码沿用仓库 [PolyForm Noncommercial 1.0.0](../LICENSE)，仅非商业学习研究；第三方 App、SDK 和服务的权利与条款不因本项目改变。未经授权不得商用或收费分发。

## 全天智记上下文（Android 1.0.5 源码候选）

新增定稿文本采集、有界窗口队列、显式上传/恢复、主对话上下文工具及外部 Agent 只读接入示例。配置、数据保留和验证边界见 [Ambient context bridge](docs/AMBIENT_CONTEXT.md)。这是源码集成，查询鉴权通过不代表录音上传或完整 Agent 链路已经验收。
