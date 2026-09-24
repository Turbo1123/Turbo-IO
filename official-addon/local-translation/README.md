# 本地翻译与英语离线字幕 · iOS 26+

2026-09-24。公开 OFFLINE-ENGLISH-05 的原创实现，支持 **Apple 本地翻译 / Hy-MT2 本地翻译 / 只显示英文**。运行在 iPhone，不在眼镜上加载大模型，**不需要刷固件，也不需要服务 Key**。不提供签名 IPA 或模型打包下载。

## 能做什么

| 部分 | 实现与限制 |
| --- | --- |
| 文字翻译 | Apple 系统 Translation，或 Hy-MT2-1.8B-1.25Bit GGUF；当前 UI 中英互译 |
| 英语离线 ASR | Parakeet Realtime EOU 120M CoreML / FluidAudio，320 ms 模型块；不是 320 ms 端到端延迟，也不是中文 ASR |
| 收音 | 手机麦克风，或系统实际列出的 AirPods/蓝牙 HFP 输入；路由变化停止，不悄悄切换 |
| 字幕翻译 | 默认“快速预译”，约6个识别词后尝试短前缀，保留末尾上下文；Hy-MT 逐步输出，Apple 每次前缀返回整体结果 |
| 镜片同步 | 原厂字幕纯显示通道，业务19：设置→匹配SID回执→文字→退出；不启动原厂录音上行 |
| 运行边界 | 前台、用户主动开启；离开页面/退后台/中断/输入路由改变即停止，20分钟保护 |

预译会修正，不等于同时传译。只运行一个翻译任务，待处理最终片段最多4项，音频最多32个缓冲；积压明确报错。眼镜0.5秒发送节流、384字节帧上限、单个待提交包、合并最新内容。旧导航的3秒/80帧/4分钟限制保持不变。

**不包含**：眼镜“前方/四周”定向原始收音、自定义云端 ASR/实时翻译配置 UI、多语言离线 ASR、后台无限录音、自动保存转写或音频、云端失败兜底。蓝牙HFP可用不等于已实现眼镜专有方向协议。

## 1. 准备依赖

Apple Silicon Mac、CMake、Python 3.10+、Node.js、完整 Xcode（本次用 iOS 27 SDK、Swift 6.4，语言模式 Swift 6；目标最低 iOS 26）。需要足够磁盘与内存，模型约462 MB +224 MB，兼容转换保留原件，因此下载目录大于1 GB。运行内存还包括计算/缓存及宿主 App，不能拿权重大小当峰值RAM。

先阅读[第三方许可](THIRD_PARTY.md)。下面命令在仓库根目录运行，目录必须是新的，不覆盖已有实验：

```sh
mkdir -p official-addon/local-translation/work
git clone https://github.com/sjl623/llama.cpp.git official-addon/local-translation/work/llama.cpp
git -C official-addon/local-translation/work/llama.cpp checkout --detach 1e411d8f5a1e23525fa3265dfb4bd76265465397
git clone https://github.com/FluidInference/FluidAudio.git official-addon/local-translation/work/FluidAudio
git -C official-addon/local-translation/work/FluidAudio checkout --detach eabcd9e36dab48f1f7180165396d84b9688650e0
python3 official-addon/local-translation/models.py \
  --out official-addon/local-translation/work/models --accept-model-licenses
```

下载器只访问固定公开版本，逐文件验证长度和 SHA-256；失败保留 `.download` 供检查，使用新输出目录重试。不要用其他权重替换文件名绕过校验。Apple语言包不是这里下载的：在 App 内点“准备 Apple 语言包”，明确同意系统下载，之后才可离线翻译。

## 2. 编译翻译模块和宿主入口

```sh
python3 official-addon/local-translation/build.py \
  --llama official-addon/local-translation/work/llama.cpp \
  --fluid official-addon/local-translation/work/FluidAudio \
  --out official-addon/local-translation/work/module
TIO_LOCAL_TRANSLATION=1 bash official-addon/build.sh embedded
python3 official-addon/local-translation/test.py
```

第一个命令生成 `module/TurboCaptionTranslation.dylib` 和依赖资源，不使用开发者证书。第二个生成 `official-addon/build/local-translation/TurboIOPrivateAddon.dylib`，增加「TurboIO → 资料 → Apple / Hy-MT2 本地翻译」入口。默认构建不带此入口；旧 iOS 不加载26+模块。也可与既有导航/音乐构建开关组合，但仍须遵守各自固件门禁，不因此授权刷机。

Hy-MT 使用固定 STQ CPU/ARM NEON 内核，不是 Metal/ANE 后端。默认线程数最多6，可选至8但不超过设备核心数，保留温控/低电量降档、取消、15秒单次超时、1024 token上下文、384 token输出上限与退出释放。

## 3. 自行签名打包

遵循[宿主版本与签名说明](../README.md)。需要合法取得且通过仓库校验的未加密 thin-arm64 `Runner.app`；本文不提供解密操作。已测试私用前身宿主为官方 iOS 1.0.5（201），设备为 iPhone Air；其他版本不能直接外推。

```sh
node official-addon/package.mjs \
  --app /absolute/Runner.app \
  --addon /absolute/Turbo-IO/official-addon/build/local-translation/TurboIOPrivateAddon.dylib \
  --translation-module-dir /absolute/Turbo-IO/official-addon/local-translation/work/module \
  --translation-models /absolute/Turbo-IO/official-addon/local-translation/work/models \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 \
  --device YOUR_DEVICE_ID \
  --out /absolute/new-local-output
```

占位路径和签名参数由你替换，**不填写维护者账号**。打包器检查入口与资源配对，核对模型哈希，只拷贝明确列出的文件，拒绝覆盖宿主内已有翻译资源；在现有签名步骤之前加入dylib、模型和资源。此命令不安装、不刷眼镜、不为你增加不属于证书的权限。完整打包仍须使用自己的证书在自己的设备验收。

## 4. 手机上使用

1. 打开「TurboIO → 资料 → Apple / Hy-MT2 本地翻译」。先测试短句；Apple先准备语言包，Hy-MT自动校验本机随包模型。
2. 点右上角麦克风进入“英语离线字幕”；选择仅英文或翻译引擎、输入设备、是否同步眼镜。
3. 先停止音乐/TTS/对话/录音/导航等其他任务，再主动点开始并允许麦克风。模型首次校验加载可能需数秒。
4. 开启镜片同步时等待本次SID成功回执；失败可关闭镜片同步，先在手机测收音。不强抢官方会话。
5. 说英语，先显示英文，再显示带“预译”标识的译文。想要更稳定可关“快速预译”。停止或退出页面即取消收音和翻译。

官方 App 的其他功能仍可能联网；“本地翻译”仅指这条识别/翻译处理链无云端兜底，不代表整个宿主 App 被断网。

## 验证与已知问题

- 私用前身：用户确认文字翻译可用、04版真实英语识别很好；05版已安装。不能把这些反馈当成本次公开包已经真机全量验收。
- 05版历史设备组合探针：音频回调和ASR通过，但Apple翻译阶段返回 `CaptionFailure`；未明确错误分支，可能需要核对语言资源，**不宣称组合探针全通过**。
- 本次公开构建/测试结果见 [VALIDATION.md](VALIDATION.md)。没有操作用户手机或眼镜。
- AirPods/其他蓝牙麦克风、长时温升、真实镜片延迟和多语种质量仍需专项验收；不承诺零延迟。
- 这是新的独立字幕入口，不是全面替换官方翻译页所有行为。遇到内存压力/温控/积压会停止或降档，不强行持续运行。

原创代码沿用仓库非商业许可；第三方模型/依赖保持各自许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。不上传 Key、Cookie、个人提示词、模型权重、签名材料或 IPA。
