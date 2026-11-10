#!/usr/bin/env bash
# 云Mac本地一键构建：FOCUS-04 + 高德导航 + TAP1/TCE1 应用SDK → adhoc IPA
# 等价于 GitHub Actions「iOS Merge Build」勾选 focus+amap+app_sdk 的 adhoc 流程。
# 大文件（高德SDK/原厂IPA/固件）首次下载后永久缓存，之后每次构建只重编译 dylib。
#
# 刷自建 TAP1 固件（build-tap1.sh 产物）时：
#   TAP1_FW=<固件zip绝对路径> TAP1_CANDIDATE=<candidate-ota.json绝对路径> bash build-local.sh
#   → dylib 门禁与内嵌固件自动指向新候选（confirmToken=TAP1-2026-10）
#
# 用法（仓库根目录）：
#   bash build-local.sh                      # 默认 Bundle ID = 官方 com.rayneo.venus.pub
#   bash build-local.sh <你的描述文件覆盖的Bundle-ID> iPhone18,2
# 产物：IPA/TurboIO-merged-adhoc.ipa → 回 Windows 用爱思助手（导入证书）签名安装。
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="${1:-com.rayneo.venus.pub}"
PRODUCT="${2:-iPhone18,2}"
UPSTREAM_IPA_URL="https://github.com/Turbo1123/Turbo-IO/releases/download/rayneo-ios-1.0.5-201/RayNeo_AI_1.0.5_201_decrypted_original.ipa"
EXPECTED_IPA_SHA256="39d12aff8f2b312dc3b40ce784a444e52c536e61378434005255177548df966a"
FIRMWARE_URL="https://github.com/Turbo1123/Turbo-IO/releases/download/firmware-strix-1.0.4.12-tfp1-focus04/StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-EXPERIMENTAL.zip"
FIRMWARE_SHA256="ad5054e3d7bda90e94d293bea882bd8dd5a125bcc8f42c13a59b2e149313c9e3"

# GitHub 直连失败时（国内云Mac常见）自动走公共镜像前缀；SHA-256 校验兜底，镜像被污染也进不来。
fetch_github() { # $1=输出文件 $2=github URL
  if curl -fL --max-time 40 -o "$1" "$2"; then echo "    $1 ← GitHub 直连"; return 0; fi
  for M in "https://ghproxy.net/" "https://gh-proxy.com/" "https://mirror.ghproxy.com/"; do
    echo "    直连失败，尝试镜像：$M"
    if curl -fL --max-time 300 -o "$1" "${M}${2}"; then echo "    $1 ← ${M}镜像"; return 0; fi
  done
  echo "错误：$2 直连与镜像均失败。可手动下载该文件放到 $PWD/$1 后重跑" >&2; return 1
}

echo "==> [0/6] 环境检查"
command -v node >/dev/null || { echo "缺少 node（建议 22+）：brew install node"; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "缺少 Xcode 命令行工具：xcode-select --install"; exit 1; }

echo "==> [1/6] 高德 SDK（缓存：official-addon/build/amap-sdk）"
# SDK 不走 git 仓库，从高德官方 CDN（a.amap.com，国内直连）下载；版本与哈希由
# setup-amap.mjs 锁定（Navi 11.3.100 / Search 9.8.1）。下载失败时从 Windows 手动
# 上传两个 zip 到 amap-archives/ 后重跑即可（本机 D:\Downloads\amap-sdk\ 有备份）。
if [[ ! -d official-addon/build/amap-sdk/navi ]]; then
  mkdir -p amap-archives
  [[ -f amap-archives/AMap_iOS_Navi_ALL.zip ]] || curl -fL --max-time 600 -o amap-archives/AMap_iOS_Navi_ALL.zip https://a.amap.com/lbs/static/zip/AMap_iOS_Navi_ALL.zip || { echo "错误：高德 Navi 包下载失败；从 Windows 上传该 zip 到 $PWD/amap-archives/ 后重跑"; exit 1; }
  [[ -f amap-archives/search-9.8.1.zip ]] || curl -fL --max-time 600 -o amap-archives/search-9.8.1.zip https://a.amap.com/lbs/static/zip/AMap_iOS_Search_Lib_V9.8.1.zip || { echo "错误：高德 Search 包下载失败；从 Windows 上传（可改名前为 AMap_iOS_Search_Lib_V9.8.1.zip）到 $PWD/amap-archives/ 后重跑"; exit 1; }
  node official-addon/setup-amap.mjs --accept-sdk-terms --archives-dir "$PWD/amap-archives" || { echo "错误：SDK 校验/安装失败（若为 hash mismatch 说明高德更新了包）；可从 Windows 上传两个 zip 到 amap-archives/ 重试"; exit 1; }
else
  echo "    已缓存，跳过"
fi

echo "==> [2/6] 原厂砸壳 IPA（缓存：original.ipa）"
if [[ ! -f original.ipa ]]; then
  fetch_github original.ipa "$UPSTREAM_IPA_URL"
fi
echo "$EXPECTED_IPA_SHA256  original.ipa" | shasum -a 256 -c -

echo "==> [3/6] 固件（TAP1 自建 或 缓存 FOCUS-04）"
if [[ -n "${TAP1_FW:-}" ]]; then
  [[ -n "${TAP1_CANDIDATE:-}" && -f "$TAP1_FW" && -f "$TAP1_CANDIDATE" ]] || { echo "错误：TAP1_FW 需同时给 TAP1_CANDIDATE，且两文件存在"; exit 1; }
  FIRMWARE_SRC="$(cd "$(dirname "$TAP1_FW")" && pwd)/$(basename "$TAP1_FW")"
  echo "    使用自建 TAP1 固件：${FIRMWARE_SRC}（候选描述 ${TAP1_CANDIDATE}）"
else
  if [[ ! -f focus-firmware.zip ]]; then
    fetch_github focus-firmware.zip "$FIRMWARE_URL"
  fi
  echo "$FIRMWARE_SHA256  focus-firmware.zip" | shasum -a 256 -c -
  FIRMWARE_SRC="$PWD/focus-firmware.zip"
  echo "    使用缓存 FOCUS-04 固件（默认候选 tfp1-focus-04）"
fi

echo "==> [4/6] 编译 TurboIOPrivateAddon.dylib"
export TIO_AMAP_ENABLED=1
export TIO_AMAP_SDK_ROOT="$PWD/official-addon/build/amap-sdk"
export TIO_OTA_FLASH_ENABLED=1
export TIO_IMAGE_RX_LAB=1
export TIO_IMAGE_RX_WIDE=1
export TIO_DISPLAY_PHONE=1
export TIO_DISPLAY_FLASH=1
export TIO_APP_SDK=1
if [[ -n "${TAP1_CANDIDATE:-}" ]]; then export TIO_OTA_CANDIDATE="$TAP1_CANDIDATE"; fi
echo "    开关回显：AMap=$TIO_AMAP_ENABLED APP_SDK=$TIO_APP_SDK PHONE=$TIO_DISPLAY_PHONE RX_LAB=$TIO_IMAGE_RX_LAB FLASH=$TIO_DISPLAY_FLASH OTA=$TIO_OTA_FLASH_ENABLED 候选=${TIO_OTA_CANDIDATE:-tfp1-focus-04(默认)}"
bash official-addon/focus-edition/build.sh embedded "$BUNDLE_ID"
ADDON=official-addon/focus-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib
# 注意：不要用 `nm | grep -q`——本脚本开了 pipefail，grep -q 提前退出会让 nm 吃到
# SIGPIPE(141)，管道整体被判失败，明明匹配到了也误报缺失。用 grep -c 读完整个输出。
TCE_COUNT=$(nm -g "$ADDON" | grep -c TCEEditorController || true)
echo "    符号核验：TCEEditorController×$TCE_COUNT"
if [[ "$TCE_COUNT" -eq 0 ]]; then
  echo "错误：App SDK 符号缺失（TCE=$TCE_COUNT，APP_SDK=${TIO_APP_SDK}）"; exit 1
fi
echo "    扩展就绪：$ADDON"

echo "==> [5/6] 合并 + 高德资源 + FOCUS 固件注入 + adhoc 签名"
rm -rf input merged && mkdir input merged
[[ -d IPA ]] || mkdir IPA
unzip -q original.ipa -d input
# 注意：gray/upgrade 两个更新检查 URL 的回环补丁由 focus-adhoc-package.mjs
# 在 merged/ 上完成（那里才是最终产物），此处不要重复打——已补丁的二进制
# 过不了补丁模块的原始 SHA 自校验，会让打包脚本炸掉。
node official-addon/macho-embed.mjs \
  "$PWD/input/Payload/Runner.app" \
  "$PWD/merged/Payload/Runner.app" \
  "$PWD/$ADDON" \
  "$BUNDLE_ID"
node --input-type=module -e "
  import {amapResources,copyAMapResources} from './official-addon/amap-resources.mjs';
  copyAMapResources(amapResources(process.argv[1]), process.argv[2]);
" "$PWD/official-addon/build/amap-sdk" "$PWD/merged/Payload/Runner.app"
PLIST="merged/Payload/Runner.app/Info.plist"
if [[ $(plutil -convert json -o - "$PLIST" | grep -c NSLocationWhenInUseUsageDescription || true) -eq 0 ]]; then
  plutil -insert NSLocationWhenInUseUsageDescription -string '用于用户主动选择的地图定位和前台步行导航。' "$PLIST"
fi
if [[ -n "${TAP1_CANDIDATE:-}" ]]; then
  node .github/scripts/focus-adhoc-package.mjs \
    "$PWD/merged/Payload/Runner.app" \
    "$FIRMWARE_SRC" \
    "$PWD/official-addon/build/amap-sdk" \
    "$PWD/merged/experimental-ota-routing.json" \
    "$TAP1_CANDIDATE"
else
  node .github/scripts/focus-adhoc-package.mjs \
    "$PWD/merged/Payload/Runner.app" \
    "$FIRMWARE_SRC" \
    "$PWD/official-addon/build/amap-sdk" \
    "$PWD/merged/experimental-ota-routing.json"
fi
# 原厂包按机型裁剪（列表只到 iPhone16,2），补进当前机型避免安装报错
if [[ $(plutil -convert json -o - "$PLIST" | grep -c UISupportedDevices || true) -gt 0 \
   && $(plutil -convert json -o - "$PLIST" | grep -c "\"$PRODUCT\"" || true) -eq 0 ]]; then
  plutil -insert UISupportedDevices.0 -string "$PRODUCT" "$PLIST"
  echo "    已把 $PRODUCT 加入 UISupportedDevices"
fi
find merged/Payload/Runner.app/Frameworks -name '*.framework' -type d | while read -r fw; do codesign -f -s - "$fw"; done
find merged/Payload/Runner.app/Frameworks -name '*.dylib' -type f | while read -r lib; do codesign -f -s - "$lib"; done
codesign -f -s - --generate-entitlement-der merged/Payload/Runner.app

echo "==> [6/6] 打包"
ditto -c -k --norsrc --keepParent merged/Payload IPA/TurboIO-merged-adhoc.ipa
if [[ ! -f IPA/TurboIO-merged-adhoc.ipa ]]; then echo "错误：IPA 未生成"; exit 1; fi
echo "=============================================="
echo "完成：IPA/TurboIO-merged-adhoc.ipa ($(du -h IPA/TurboIO-merged-adhoc.ipa | cut -f1))"
echo "Bundle ID：${BUNDLE_ID:-com.rayneo.venus.pub}（爱思签名时须与描述文件覆盖的 ID 一致；用固定 ID 证书时把你的 ID 作为第一个参数传入）"
shasum -a 256 IPA/TurboIO-merged-adhoc.ipa
echo "回 Windows：爱思助手 → 导入证书（p12+mobileprovision）→ 安装 → 设置→通用→VPN与设备管理→信任"
