# TAR2 · iPhone AirPlay 接收模块（GPLv3）

另一台 iPhone / iPad / Mac → 同一 Wi-Fi 的 iPhone 接收器 → H.264 解码 → 原生 540×220 灰度分块 → TVP2 眼镜。

接收端不需要 Mac 或服务器。首版限定 iPhone App 前台、静音、单发送设备、手动开启；PIN 配对，不保存画面。不是 Apple 官方认证接收器，不支持受保护视频、HEVC 或网页视频直投，不保证所有发送端兼容。

## 许可边界

**本目录（包括为接收模块提供的高清编码/传输副本）按 GPL-3.0-or-later 提供，见 [LICENSE](LICENSE)。这是经维护者明确同意的局部许可例外，根目录非商业条款不叠加到此目录；不改变仓库其他目录的许可。** `../tar2-display`、固件和其他原创目录仍依根许可。第三方源文件保留各自许可，不被本项目重新许可。

依赖 UxPlay（GPLv3 接收核心）、libplist（LGPL）、OpenSSL（Apache-2.0），提交/版本与校验见 [upstream.lock.json](upstream.lock.json)。构建从各自官方源下载并保留原许可，不供应私人账号或签名。分发修改版或与其他宿主组合的二进制前，须自行审查并满足所有相应许可证；本源码发布不保证与任意闭源宿主组合后可再分发。

## 构建

macOS、Xcode iPhoneOS SDK、Python 3.12+、Git、Perl、make：

```sh
cd official-addon/tar2-airplay
python3 build.py --prepare
```

脚本固定 UxPlay / libplist 提交，验证 OpenSSL 源码 SHA-256，交叉编译 **iOS arm64** 静态依赖，再构建 `build/sdk/libTurboAirPlay.a` 并做动态库链接自检。首次会下载和编译依赖；`build/` 不应提交。可用 `--deps /path/to/pinned-ios-deps` 复用对应依赖。编译成功不等于真机或宿主整合验收。

没有生成完整雷鸟 IPA、没有合并签名、没有启动接收器、没有连眼镜或自动刷写。不要把 macOS Homebrew 的 crypto/plist 库混入 iOS。构建中使用系统 Bonjour / VideoToolbox，不包含桌面 GStreamer 播放器或 macOS AWDL 私有扩展。

## 接入自己的 iOS 宿主

入口为 [TAR2Module.h](TAR2Module.h)。链接本模块及 Foundation、UIKit、CoreVideo、CoreMedia、VideoToolbox、Accelerate；按自己的宿主设置 Objective-C 链接与签名。宿主负责现有的蓝牙连接、设备身份、任务互斥、权限和 OTA，不得另开连接争抢原厂通道。

```objc
TAR2Bindings *b = [TAR2Bindings new];
b.peer = ^{ return connectedPeerID(); };
b.send = ^BOOL(NSData *wire, NSString *peer) {
    // 再核对当前设备/OTA门禁；走宿主既有 business15 二进制发送路径。
    return sendThroughExistingHost(peer, 15, wire);
};
b.otherTasksIdle = ^{ return noOtherGlassesOrMentraTask(); };
b.otaLocked = ^{ return firmwareUpdateProtectionActive(); };
UIViewController *page = TAR2CreateController(b);
if (page) [navigationController pushViewController:page animated:YES];
```

这些函数是接入示意，不是本 SDK 自带的宿主 API。`otherTasksIdle` 应允许接收器自己的会话，但拒绝录音、智记、相机、导航及其他占用；`send` 必须再次核对设备，不能把“SDK 已提交”当成眼镜成功接收。

收到真实原厂 business15 回执时，在主线程调用 `TAR2ConsumeReply`：

```objc
NSDictionary *e = @{
  @"eventType": @"messageReceived",
  @"message": @{@"businessId": @15,
               @"deviceId": actualPeerID,
               @"payload": actualBinaryReply}
};
BOOL consumed = TAR2ConsumeReply(e);
```

把 `TAR2Busy()` 纳入宿主其他独占任务及 OTA 的放行检查。不得伪造成功回执、跳过 CRC/序号/设备校验、自动重放超时按键。缺失绑定时入口拒绝启动。每条消息≤14999字节，最多一块在途、一帧待提交；旧帧丢弃，不排长队。

宿主 Info.plist 必须声明：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>用于在同一Wi-Fi发现接收器，并在用户主动开启后接收屏幕画面。</string>
<key>NSBonjourServices</key>
<array><string>_airplay._tcp</string><string>_raop._tcp</string></array>
```

## 操作与限制

先刷匹配的 [TVP2](../../firmware-research/strix-1.0.5.5-tvp2/README.md)。手动开启接收器，在另一设备控制中心选择“屏幕镜像 → Turbo IO”，输入 PIN。接收手机保持前台；可选完整画面、局部放大与拖动。默认8级灰、目标10帧；完整高清的实际帧率受蓝牙和画面复杂度影响。

眼镜短按暂停/继续、长按退出；离开页面、手机后台、断连或9分钟测试上限会停止。原厂抬头和手势逻辑未替换。临时错误或未确认新高清能力会停发，不尝试把高清数据发送给旧固件。

元数据日志保存 `Library/Application Support/TurboIOPrivateAddon/AirPlay/current.json`，不含画面、PIN 或发送端身份。`receiver.key` 是本机配对私密文件，禁止上传。

2026-10-23：用户在 iPhone 17 Pro Max 私用集成版实测反馈通过；本机回读显示1280×720源、540×220输出、3470帧零解码错误、186帧眼镜完整确认、正常关闭。**公开的独立宿主绑定版另行完成编译/链接测试，未冒充已安装到真机的同一个包。** 本次不发布个人签名 IPA 或含个人视频的完整安装包。

UxPlay 原始核心含桌面进程退出/assert等路径；有界长度和参数校验不等于完整安全审计。仅在可信局域网做主动测试，不暴露公网，不宣称锁屏/后台或生产级稳定。
