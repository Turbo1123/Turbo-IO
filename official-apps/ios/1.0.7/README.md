# 雷鸟 AI iOS 1.0.7（230）· 原厂砸壳 / 未签名 IPA

2026-10-19 · **[下载 IPA、SHA256SUMS 与审计报告](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.7-230)** · [版本索引](../README.md)

这是**原厂 1.0.7（230）的砸壳副本，未加入 Turbo IO，未改变原厂功能代码**。移除了全部代码签名、描述文件和商店授权元数据，并重新归档；不是 App Store 原始加密包，也不是已签名可直接安装的成品。

**版权仍归雷鸟官方及相关权利人。** 这不是官方源码；仓库原创源码许可证不覆盖原厂二进制，不改变其原有许可，也不表示官方背书。使用者须有权使用该输入。

## 精确产物

| 项目 | 值 |
| --- | --- |
| 文件 | `RayNeo_AI_1.0.7_230_decrypted_unsigned_original.ipa` |
| 版本 / Build | **1.0.7 / 230** |
| Bundle ID | `com.rayneo.venus.pub` |
| 架构 / 加密状态 | arm64；全部 95 个 Mach-O 均无启用的加密标记 |
| 大小 | **353,804,631 字节** |
| IPA SHA-256 | `50df3954845e3bc2e34f9ba6def8c3837e9d1a6c232f36f3a975dd08152a3ff7` |
| 未签名 Runner SHA-256 | `765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3` |
| 未签名 App.framework/App SHA-256 | `041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d` |

## 去签名与隐私检查

- **95/95 个 Mach-O 签名移除**；另行回读归档确认 `LC_CODE_SIGNATURE`、`LC_DYLIB_CODE_SIGN_DRS` 和启用加密的代码镜像均为 0。
- 清理 102 个签名／商店元数据文件，包括签名目录、SC_Info、收据和描述文件。没有重新签名。
- 与已有原厂解密输入比对：UUID、加载依赖、归一化加载命令、全部文件内 section 与签名前数据一致；签名相关头部及链接区长度变化允许，其他 2610 项资源保持原样。
- 对照本机个人签名 profile 中的标识扫描，匹配数为 0；不发布比对标识、Cookie、Key、应用数据、个人签名或证书私钥。
- ZIP CRC、2705 个归档成员逐个回读通过；原始输入保持不变。
- 不含 Turbo IO、研究探针、越狱注入加载项、个人模型或 Watch 扩展。这些检查不等于对原厂所有业务或厂商内置配置的完整审计。

[审计报告](audit.json)与[SHA256SUMS](SHA256SUMS)同时附在 Release；大体积 IPA 存于 Release，不加入 Git 历史。

```sh
shasum -a 256 -c SHA256SUMS
unzip RayNeo_AI_1.0.7_230_decrypted_unsigned_original.ipa -d /absolute/new-input
```

## 合并 Turbo IO

使用最新版 [APP107 / iOS 1.0.7 集成目录](../../../official-addon/ios107-edition/README.md)。打包器精确接受原始签名保留版或本 Release 去签名版的 Runner + App.framework **配对哈希**；不接受混搭、其他版本或未知重签输入，没有放宽固件校验和单次刷写门禁。

你仍须使用自己的合法证书、描述文件与设备授权完成合并签名；解压或去签名都不等于签名。官方登录、推送等权限需独立核验。1.0.6 输入不能替代此版本。

1.0.7 / TMG2 已有 iPhone 17 Pro Max 实测；**这份去签名派生输入只做发布审计与本地打包签名验证，没有另行安装做全功能真机回归**。不要将前者当作此 IPA 已预签名或开箱可用。

`sanitize.py` 只处理固定哈希的已有原厂未加密输入／已取得的解密主程序，不执行设备砸壳、联网提取、安装、签名或刷写；输出必须是新目录，原输入不修改。未知版本、代码和研究注入项会被拒绝。
