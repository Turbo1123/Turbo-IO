# macOS：复用既有绑定的独立连接实验

这是一个可选研究示例，不改变 V1、V2、Android 或鸿蒙的默认配对流程。

## 发现与边界

在一组**同一台 Mac、同一副 RayNeo iO、已有系统及应用绑定、已验证的本机协议身份**环境中，独立 Python BLE 客户端完成了版本交换、对端 proof 校验和设备状态读取。该次实验没有调用厂商 framework，没有写 paired 特征，没有发送 createBond 或解绑指令，也没有要求系统忽略设备。

这提供了“先验证可否复用当前绑定”的实验路径，不能据此断言任意新手机、新身份或账号绑定都能免解绑。

| 项目 | 已有证据 / 限制 |
| --- | --- |
| 历史实验 | 2026-09-09，macOS / RayNeo iO，Strix OS 1.0.3.15；精确 macOS 版本未记录，不以后来的开发环境版本替代 |
| 认证 | 多次独立连接完成版本交换和 SHA256 对端 proof 校验；peer 返回协议版本 2 |
| 业务闭环 | 认证后主动查询 generalStatus，收到电量和亮度；不能把写入成功当作连接就绪 |
| 绑定保持 | 操作中未解绑、未写 paired；一次实验中认证前后 20 字节 paired 描述块一致，但它不是完整系统绑定数据库的证明 |
| 身份来源 | 使用当前本机已验证的协议身份；旧档案中的另一个身份曾导致版本请求无响应。协议身份不是 CoreBluetooth UUID，也不能直接拿历史设备档案 identifier 代替 |
| 未证实 | 系统绑定和协议身份各自是否为必要条件；随机新身份能否连接；跨主机、iOS/鸿蒙迁移、全新首配、其他固件及并发官方客户端 |
| 本目录代码 | 从历史成功流程抽取、收紧和脱敏的新示例；离线测试通过，**这个公开版本尚未重新完成真机验收** |

原始记录包含设备标识，仅留在贡献者本地。本目录只使用人工构造的测试身份；不包含原始抓包、绑定数据库或私人路径。

## 前提：保留已有绑定和身份

- 已有该 Mac 与眼镜的有效绑定，眼镜在附近且可连接。
- 手头已有属于自己当前连接环境的、验证过的 6 字节本机协议身份和 6 字节眼镜协议身份。
- 本示例**不提供通用身份提取器**，不扫描其他应用私有容器，不生成新身份去覆盖旧身份。尚无可靠身份时，应先建立并记录身份来源，不能直接运行此实验。
- 退出当前占用眼镜的官方或独立客户端，然后运行；不要解绑、忽略设备或清空数据。这里不证明多客户端并发可用。
- macOS 的蓝牙权限仍由系统控制；读取 paired 特征等操作可能触发系统权限/配对提示。没有显式 pair 调用不等于能禁止系统自身配对行为。

## 运行

需要 Python 3.11+。在仓库根目录建立独立环境（此示例使用 Bleak 3.0.2 私有 CoreBluetooth 接口找回系统已连接设备，因此固定版本）：

```sh
python3.11 -m venv examples/macos-existing-bond/.venv
examples/macos-existing-bond/.venv/bin/python -m pip install -r examples/macos-existing-bond/requirements.txt
mkdir -p examples/macos-existing-bond/private
```

在 `examples/macos-existing-bond/private/config.json` 写入自己的配置。以下是**不可直接运行的占位符**，不要复制测试身份用于真实眼镜：

```json
{
  "name": "YOUR_EXACT_GLASSES_NAME",
  "phone_identifier": "YOUR_12_HEX_PHONE_ID",
  "peer_identifier": "YOUR_12_HEX_PEER_ID"
}
```

```sh
chmod 600 examples/macos-existing-bond/private/config.json
examples/macos-existing-bond/.venv/bin/python examples/macos-existing-bond/probe.py \
  --config examples/macos-existing-bond/private/config.json --run
```

脚本扫描并找回系统已连接设备，要求名称匹配唯一，再核对 paired 描述块中的眼镜身份。名称仅用于候选选择，后续还要核对版本回复身份及 proof。它不向终端输出设备名称、地址、身份、proof 或原始报文，也不写日志文件；不要打开第三方库调试日志后公开输出。

流程：读取 paired → 订阅 → 等待 3 秒 → 版本交换 → 随机挑战与对端 proof 校验 → 等待 5 秒 → 查询 generalStatus → 收到合法电量 → 关闭 BLE。最多一次认证请求，总超时 75 秒，无自动重试。保留历史验证的 iOS 风格版本请求字段（包括 `iPhone` 标签），不是对任意设备类型的支持声明。

版本不支持、身份不符、账号/公钥认证分支或 proof 失败都会停止，不降级，不尝试解绑。帧处理仅支持 flags=0、无地址/切片的实验配置；遇到其他元数据会停止，不能用作通用生产传输栈。错误仅输出异常类别，后续应先分析原因，避免盲目连续尝试。

预期最终输出包含 `general status received; battery=...%`。只有 proof 成功而没有状态回包，仍不能记为业务连接成功。运行后可重新打开原客户端验证原绑定是否仍能使用，并在反馈中单独记录该结果。

## 离线验证

不需要蓝牙、眼镜或 Bleak：

```sh
PYTHONDONTWRITEBYTECODE=1 python3.11 -m unittest discover -s examples/macos-existing-bond -v
node scripts/check-source.mjs
```

测试覆盖 CRC、跨 ATT 数据重组、畸形元数据、身份/版本/认证分支检查、对端 proof、状态有效性，以及一次性版本→认证→状态顺序。模拟收发不证明 OS 配对行为或真实镜片显示。

## 后续希望共同验证

先在保留绑定的同机环境复现，再评估是否应增加产品入口。对比变量应分开记录：OS bond、本机协议身份、账号绑定状态、固件、连接是否被另一客户端占用。不要为了得到对照组自动清除现有绑定。

欢迎反馈脱敏的环境版本、身份取得方式、各阶段成功/失败及运行后原客户端恢复结果。其他平台在验证前继续遵循原有配对说明。
