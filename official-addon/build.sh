#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
mode=${1:-embedded}
bundle=${2:-com.rayneo.venus.pub}
if [[ ! "$bundle" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$ ]]; then
  echo 'Invalid explicit target Bundle ID' >&2; exit 2
fi
case "$mode" in
  jailbreak) output=build/TurboIOPrivateAddon.dylib; install_name=/var/jb/usr/lib/TweakInject/TurboIOPrivateAddon.dylib ;;
  embedded) output=build/embedded/TurboIOPrivateAddon.dylib; install_name=@rpath/TurboIOPrivateAddon.dylib; mkdir -p build/embedded ;;
  *) echo 'Usage: build.sh [jailbreak|embedded] [target.bundle.id]' >&2; exit 2 ;;
esac
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
link_options=()
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
# Keep the normal embedded build unchanged until the device comparison passes.
if [[ ${TIO_CLASSIC_BINDINGS:-1} == 1 ]]; then
  link_options+=(-Wl,-no_fixup_chains)
fi
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=16.0 \
  -fobjc-arc -fmodules -dynamiclib -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types \
  -framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
  "-DTIO_TARGET_BUNDLE_ID=\"$bundle\"" -install_name "$install_name" "${link_options[@]}" \
  Core.m Profile.m KnowledgeClient.m KnowledgeUI.m ProfileUI.m HomeTabLayout.m HomeTabBridge.m ResearchCatalog.m ResearchUI.m NewsPresentation.m PrivateBootstrap.m WebSearch.m TodoProtocol.m TodoRuntime.m NewsCore.m NewsReader.m NewsTeleprompter.m RecordingExports.m RecordingExportsUI.m RecordingExportsMenu.m RecordingText.m RecordingTextUI.m RecordingTextMenu.m AlwaysOnAudioFiles.m AlwaysOnOgg.m AlwaysOnAudioNative.m AlwaysOnAudioUI.m Addon.m -o "$output"
codesign --force --sign - "$output"
plutil -lint TurboIOPrivateAddon.plist
shasum -a 256 "$output"
