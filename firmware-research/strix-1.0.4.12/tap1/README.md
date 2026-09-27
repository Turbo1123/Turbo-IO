# TAP1-TEST-01 · Android 官方流程 OTA 实测

**试验用品，非开发者请勿刷。** 断电、中断、不兼容或程序缺陷都可能造成无法启动、失去OTA或需要返厂。仅改 AP 不能保证安全；原厂回滚不是救砖保证。

- [APK、固件与校验文件](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01)
- [从安装 APK 到刷写、验收的完整教程](../../../android-addon/docs/INSTALL_AND_FLASH.md)
- [仪表盘 / 四槽小应用 SDK 与20个模板](../../../docs/DEVELOPER_ECOSYSTEM.md)

本次公开用户在2026-09-27以 Fold3 / Android 15、官方1.0.5（201）+ GUARD-07 实测成功的原样完整OTA。包含此前的 TAP1 有界小应用运行时及仪表盘能力；相对已使用的 TAP1 spacefix-c，只将菜单“显示测试”原位改为“显示TEST”，便于检查本轮刷入结果。

## 修改范围与摘要

| 项目 | 值 |
| --- | --- |
| ZIP字节数 | 9,320,672 |
| ZIP SHA-256 | `5ef21d8c18501d03fad6edee4fe039649cb567352e30dbd234081ecf97140afa` |
| nuttx_ap.bin字节数 | 9,590,856 |
| AP SHA-256 | `65e0a5312361ec785eb9ab1659badf182765f4054d4d95fef4c61ceb49dfa4b4` |
| AP MD5（清单） | `ef8922c0d199005164bfb6330bc8eb9d` |

14个固件负载中仅 `nuttx_ap.bin` 相对原厂改变，清单对应Size/MD5更新；另外13个负载与归档原厂1.0.4.12逐字节相同。ZIP是完整OTA，**并非仅AP的刷写文件**，也不意味着安装器物理上只写AP。

为什么只改AP：UI、菜单、应用运行时位于AP，保留蓝牙核、音频核等其他组件能减少修改变量、便于排查；但AP崩溃仍可能破坏整个设备的可用性。

## 源码与证据边界

`source/` 保存该 TAP1 基线构建报告中按SHA-256逐一确认的原创构建输入快照，供审查及开发研究。它不包含原厂完整源码、私人账号或手机网页正文适配。当前不宣称这是一个无需其他原厂符号/基线文件即可独立从零重建的SDK；不要把自行重建的包冒充这个实测固定哈希。

菜单标记的离线派生脚本见 `official-addon/research/app-runtime-v1/build_test_marker.py`（仓库根）；发布包审计见 `android-addon/tests/audit_release_firmware.py`。脚本不连接设备、不授权、不刷机。

日志支持279片、AP全覆盖及零拦截；用户确认最终正常启动。手机自动完成判定尚需人工只读回查，不代表故障恢复、任意旧版本升级或长时间稳定性都验证过。
