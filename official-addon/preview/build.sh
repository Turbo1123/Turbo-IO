#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=build/research-preview/ResearchPreview.app
mkdir -p "$output"
cp preview/Info.plist "$output/Info.plist"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.0-simulator -isysroot "$sdk_path" \
  -DTIO_UI_PREVIEW=1 -fobjc-arc -fmodules -Wno-deprecated-declarations -Wno-incompatible-pointer-types \
  -framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
  Core.m Profile.m KnowledgeClient.m KnowledgeUI.m ProfileUI.m HomeTabLayout.m HomeTabBridge.m ResearchCatalog.m ResearchUI.m NewsPresentation.m PrivateBootstrap.m WebSearch.m TodoProtocol.m TodoRuntime.m NewsCore.m NewsReader.m NewsTeleprompter.m RecordingExports.m RecordingExportsUI.m RecordingExportsMenu.m RecordingText.m RecordingTextUI.m RecordingTextMenu.m AlwaysOnAudioFiles.m AlwaysOnOgg.m AlwaysOnAudioNative.m AlwaysOnAudioUI.m Addon.m preview/Main.m preview/HomeTabFixture.m \
  -o "$output/ResearchPreview"
codesign --force --sign - "$output"
echo "Preview only: $output (no official binary, no private bootstrap)"
