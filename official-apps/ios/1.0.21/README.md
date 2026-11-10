# 雷鸟 AI iOS 1.0.21（构建 1）· 已解密、未签名原厂 IPA

[下载 IPA](https://github.com/Turbo1123/Turbo-IO/releases/download/strix-10611-tmig2-video-r1/RayNeo_AI_1.0.21_1_decrypted_unsigned_original.ipa) · [审计记录](audit.json) · [SHA256SUMS](SHA256SUMS) · [配套固件](../../../firmware-research/strix-1.0.6.11/README.md)

应用标识为 `com.rayneo.venus.pub`，架构为 arm64。此文件用于研究原厂程序及自行集成。去签名后需要适用于自己设备的合法证书和描述文件才能安装。使用原厂应用功能可直接通过 App Store 安装。TurboIO 插件、个人签名和账号配置不在此归档中。

| 项目 | 实际值 |
| --- | --- |
| IPA 大小 | 421,432,654 字节 |
| IPA SHA-256 | `e935d2cb45dc524c65bdf13e5bae095123a7c95d99c6d48840779c96afafbfd6` |
| 未签名 Runner SHA-256 | `6efec6987f666bb758bd0c60a0e8f8163fb6423a317c7ee636e0afba2981b348` |
| 未签名 App.framework/App SHA-256 | `2258e6269d855db7de8d7da89a36915b2ff20c082822d00c48aaa624bd7737b6` |

从独立的原厂应用目录制作，使用固定哈希的已解密主程序。对 103 个 Mach-O 逐个移除签名，复查启用加密标记为零，对比程序段、依赖和 UUID。移除 110 项签名／商店元数据，保留 12,964 项其余资源。完成个人签名标识检查及全部 13,067 个归档文件回读。原厂地图框架内有两条独立的 PEM 起止标记字符串，工具核实其为以零字节结尾的分隔符。审计范围是本次脱签、归档和发布物核对。

```sh
shasum -a 256 -c SHA256SUMS
unzip RayNeo_AI_1.0.21_1_decrypted_unsigned_original.ipa -d ./rayneo-1.0.21
```

[sanitize.py](sanitize.py) 在独立目录处理固定版本，自行复现需要已有原厂包和经校验的解密 Runner。厂商保留原厂二进制版权；仓库原创扩展许可仅覆盖相应项目代码。
