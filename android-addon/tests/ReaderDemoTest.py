"""The reviewed original reading fixture must ship through the exact allowlist."""
import hashlib
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from addon_assets import assets
p = assets()['assets/turboio/reader/demo-7392.txt']
data = p.read_bytes()
assert len(data) == 11961
assert hashlib.sha256(data).hexdigest() == '369b632f58e96d625731765ff2159d453fefcdca6c4e33d710878fdb7706f643'
lines = data.decode('utf-8', errors='strict').splitlines()
assert len(lines) == 70
for i, line in enumerate(lines, 1):
    assert line == f'第{i}行：Turbo IO 安卓阅读通道测试。校验七三九二。本段为原创测试内容，不是微信读书正文。检查滚动、分页和退出是否正常。'
print('ReaderDemo: original 70-line UTF-8 fixture and public APK allowlist verified')
