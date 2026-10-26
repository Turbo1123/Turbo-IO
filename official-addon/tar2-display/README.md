# TVP2 原创高清编码与传输层

本目录沿用仓库根目录的非商业许可，不包含 UxPlay 接收核心。需要可独立构建的 GPLv3 接收 SDK，请看 [tar2-airplay](../tar2-airplay/README.md)；该目录的局部许可例外不改变这里的许可。

- `player.c/h`：TVP1旧单帧兼容 + TVP2四分块/整帧CRC/原子提交。
- `FrameEncoder.m`：NV12亮度、全画面/局部缩放、高质量重采样、2/4/8/16灰阶与四分块。
- `HDLink.m`：能力握手、单块在途、逐块/完整帧回执核对、暂停退出和超时停发。
- `tests.m`、`legacy-player-tests.c`：不接设备的像素/协议测试。

macOS/Xcode 离线验证：

```sh
cd official-addon/tar2-display
mkdir -p build
xcrun clang -fobjc-arc -fmodules -fsanitize=address,undefined -g \
  tests.m FrameEncoder.m HDLink.m player.c \
  -framework Foundation -framework CoreVideo -framework Accelerate -o build/hd-tests
./build/hd-tests
xcrun clang -fsanitize=address,undefined -I. player.c legacy-player-tests.c -o build/legacy-tests
./build/legacy-tests
```

原生显示540×220，stride最大544，双缓冲239424字节；不允许未收齐的分块换到前台。每条消息最大14999字节。协议的成功回执证明提交给渲染层，不单独证明光学刷新率。高清像素数是旧270×110编码源的4倍，帧率与清晰度有带宽取舍。
