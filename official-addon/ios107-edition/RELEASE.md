# Turbo IO · iOS 1.0.7（230）APP107 OTA 开放

2026-10-19：**iPhone 17 Pro Max 已通过雷鸟 1.0.7 官方升级流程实刷 TMG2 成功。** 功能使用也已获用户实测正常反馈。现公开专用升级适配，不再整项禁用 OTA。

- 新增 1.0.7 精确宿主、UUID、查询数据记录和签名后路由校验，不沿用旧版偏移。
- 打包默认加入固定 TMG2 升级通道，保留默认锁定、15 分钟只下载、单次授权、实际目录/清单/分片校验。
- 原样沿用 TMG2，没有重新生成固件；已装 TMG2 的用户无需重复刷写。
- 公开版编译、14 组离线回归、7 项打包测试、OTA 宿主与篡改检查、本地签名打包检查通过。
- 实刷官方传输 100%、安装 succeeded、重连版本匹配；成功后重启手机 App，授权归零。

## 获取与使用

- [最新源码与构建](https://github.com/Turbo1123/Turbo-IO/tree/main/official-addon/ios107-edition)
- [1.0.7 专用刷机教程：包含刷后解除保护](https://github.com/Turbo1123/Turbo-IO/blob/main/official-addon/ios107-edition/OTA.md)
- [原样 TMG2 固件下载](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)
- [首页更新日志](https://github.com/Turbo1123/Turbo-IO#ios107-update)

旧的 APP107 禁用 OTA 构建需要重新合并、签名；仅更新文档不会改变已装 App。源码快照随本 Release 提供，审计 JSON 单独附上。**不提供合并或个人签名 IPA。** [原厂 1.0.7 去签名 IPA](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.7-230)另行归档，使用最新主分支打包器接受其精确哈希；原厂输入、第三方 SDK、签名和服务配置须自行合法使用。

本轮实刷使用逐字节校验一致的官方缓存，没有另做网络重新下载实测。公开脱敏派生包单独编译和本地签名验证，不是私用实测 IPA 的原样公开；不宣称所有机型、账号、功能或后台场景均验收通过。手机锁屏导航问题仍保留，Dots 未完成。

不含个人 Cookie、Key、签名材料、私用日志、手机备份、智记内容或微信读书网页正文适配。原创源码沿用仓库许可证，第三方权利不变。

**非官方高风险实验预发布。非开发者请勿刷；不保证稳定、回滚或救砖。刷后必须按教程完成收尾，不混用其他版本的候选和授权。**
