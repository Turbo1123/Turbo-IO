#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun --sdk macosx swiftc Shared/RemoteCore.swift tests/main.swift -o build/tests/remote-core-tests
build/tests/remote-core-tests
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
xcrun --sdk macosx clang -isysroot "$sdk_path" -std=c11 -Wall -Wextra -Werror \
 -fsanitize=address,undefined -g Firmware/remote.c tests/global.c -o build/tests/global-tests
build/tests/global-tests
xcrun --sdk macosx clang -isysroot "$sdk_path" -fobjc-arc -fmodules \
 -framework Foundation -I Addon Addon/WatchRemoteGate.m tests/gate.m -o build/tests/gate-tests
build/tests/gate-tests
xcrun --sdk macosx clang -isysroot "$sdk_path" -fobjc-arc -fmodules \
 -Wno-incompatible-pointer-types -framework Foundation -I Addon -I Firmware \
 -I ../official-addon/focus-edition Addon/WatchGlobalBridge.m Firmware/remote.c tests/bridge.m \
 -o build/tests/bridge-tests
build/tests/bridge-tests build/tests/bridge-tests.json
