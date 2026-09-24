# 第三方来源与许可

2026-09-24 核对固定版本。这里只区分原有许可证归属，不给第三方代码或模型重新加上本项目条款；完整条款以相应来源为准。

| 内容 | 固定来源 | 许可 / 分发边界 |
| --- | --- | --- |
| Turbo IO 原创 UI、流水线、桥接、调度和测试 | 本目录 | [PolyForm Noncommercial](../../LICENSE)；非商业研究 |
| Apple Translation / AVFoundation / CoreML | 用户的 Apple SDK 与系统 | Apple SDK/平台条款；不随本仓库分发 SDK 或系统语言包 |
| Hy-MT2 GGUF | [腾讯模型卡](https://huggingface.co/tencent/Hy-MT2-1.8B-1.25Bit-GGUF/tree/9df5c824a00a744fb0512a29c640466f4d97dfb0) | 模型卡标注 Apache-2.0；权重从上游自行下载，不上传到本仓库 |
| llama.cpp STQ 分支 | [固定提交](https://github.com/sjl623/llama.cpp/tree/1e411d8f5a1e23525fa3265dfb4bd76265465397) | MIT，见 `licenses/llama-MIT.txt`；不声称普通主线支持本次量化 |
| FluidAudio | [固定提交](https://github.com/FluidInference/FluidAudio/tree/eabcd9e36dab48f1f7180165396d84b9688650e0) | Apache-2.0，另保留上游第三方通知于 `licenses/`；不是模型权重的许可证 |
| Parakeet EOU 120M CoreML | [固定模型卡](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355) | NVIDIA Open Model License，参见[官方条款](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)；不能写成 Apache 或本仓库非商业许可 |

构建时 SwiftPM 可能解析/缓存 FluidAudio 的可选二进制依赖。使用 `--disable-default-traits` 关闭本次不需要的 NeMo 文本处理链接，但不能据此宣称上游构建完全不联网。运行时只启用 Parakeet，不调用 FluidAudio 的其他云服务/TTS 引擎。

GGUF 兼容转换只接受清单指定的原始哈希，产生一个新文件：224 个张量类型 ID 从 42 改成 43，另改一个 `general.file_type` 字段；张量载荷不变。原件保留，副本不是腾讯原始发行文件，也不是重新量化。固定内核与副本必须成对使用。

没有附带维护者的 Key、专属 Host、Cookie、账号、证书、录音或测试设备信息。用户自行使用自己的签名、合法宿主及有权使用的资源。此目录不包含网页取书适配，不改变微信读书相关发布边界。
