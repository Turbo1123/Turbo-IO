#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=../official-addon/focus-edition
app=build/WatchAddonQA.app
mkdir -p "$app"
cp tests/Info.plist "$app/Info.plist"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -target arm64-apple-ios18.0-simulator -isysroot "$sdk_path" -fobjc-arc -fmodules \
 -DTIO_WATCH_TESTING=1 -Wno-incomplete-implementation -I Addon -I "$stage" \
 -framework Foundation -framework UIKit -framework WatchConnectivity \
 Addon/WatchRemoteGate.m Addon/WatchRemoteAddon.m tests/host.m -o "$app/WatchAddonQA"
codesign --force --sign - "$app"
