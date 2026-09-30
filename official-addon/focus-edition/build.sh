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
nav_options=()
if [[ ${TIO_AMAP_ENABLED:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'AMap build is private embedded only' >&2; exit 2; }
  nav_root="${TIO_AMAP_SDK_ROOT:-$PWD/../build/amap-sdk}"
  [[ -f "$nav_root/navi/AMapNaviKit.framework/AMapNaviKit" && -f "$nav_root/foundation/AMapFoundationKit.framework/AMapFoundationKit" ]] || { echo 'Missing pinned private AMap SDK dependencies' >&2; exit 2; }
  output=build/navigation/TurboIOPrivateAddon.dylib
  mkdir -p build/navigation
  nav_options=(-DTIO_AMAP_ENABLED=1 -F "$nav_root/navi" -F "$nav_root/foundation" -framework AMapNaviKit -framework AMapFoundationKit -lc++ -lz -lsqlite3 -framework SystemConfiguration -framework CoreTelephony -framework QuartzCore -framework CoreGraphics -framework OpenGLES -framework GLKit -framework CoreMotion -framework AVFoundation -framework AudioToolbox -framework Accelerate -framework Metal -framework CoreText -framework CallKit -framework WebKit)
  [[ -f "$nav_root/search/AMapSearchKit.framework/AMapSearchKit" ]] || { echo 'Missing pinned AMap Search SDK 9.8.1' >&2; exit 2; }
  nav_options+=(-F "$nav_root/search" -framework AMapSearchKit)
fi
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
link_options=()
if [[ ${TIO_OTA_FLASH_ENABLED:-0} == 1 ]]; then
  [[ ${TIO_OTA_PREPARATION_ENABLED:-0} != 1 && "$mode" == embedded ]] || { echo 'Flash gate requires separate embedded build' >&2; exit 2; }
  link_options+=(-DTIO_OTA_FLASH_ENABLED=1 -DTIO_OTA_FEED_ARMING_ENABLED=1)
fi
if [[ ${TIO_OTA_PREPARATION_ENABLED:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'OTA preparation is private embedded only' >&2; exit 2; }
  link_options+=(-DTIO_OTA_PREPARATION_ENABLED=1 -DTIO_OTA_FEED_ARMING_ENABLED=1)
fi
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
image_options=()
if [[ ${TIO_IMAGE_RX_LAB:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Image RX lab is private embedded only' >&2; exit 2; }
  output=build/image-rx-lab/TurboIOPrivateAddon.dylib
  mkdir -p build/image-rx-lab
  image_options=(-DTIO_IMAGE_RX_LAB=1 -framework PhotosUI -framework ImageIO -framework CoreGraphics ImageUpload.m ImageUploadTransport.m ImageUploadNative.m ImageUploadUI.m)
  [[ ${TIO_IMAGE_RX_WIDE:-0} != 1 ]] || image_options+=(-DTIO_IMAGE_RX_WIDE=1)
fi
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
# Keep the normal embedded build unchanged until the device comparison passes.
if [[ ${TIO_DISPLAY_PHONE:-0} == 1 ]]; then
  [[ ${TIO_IMAGE_RX_LAB:-0} == 1 && "$mode" == embedded ]] || exit 2
  image_options+=(-DTIO_DISPLAY_PHONE=1 -DTIO_DISPLAY_DIAGNOSTICS=1 -DTIO_NATIVE_NAV=1 nav_runtime.c NativeNavigation.m TNVTransport.m NativeNavigationUI.m display_runtime.c display_client.c display_carrier.c DisplayDelta.c DisplayNavigation.m DisplayHUDRenderer.m DisplayReplyObserver.m DisplayPhoneSession.m DisplayPhoneTransport.m DisplayPhoneUI.m DisplayDiagnostics.m)
fi
if [[ ${TIO_DISPLAY_FLASH:-0} == 1 ]]; then
  [[ ${TIO_DISPLAY_PHONE:-0} == 1 && ${TIO_OTA_FLASH_ENABLED:-0} == 1 && "$mode" == embedded ]] || exit 2
  link_options+=(-DTIO_DISPLAY_FLASH=1)
fi
if [[ ${TIO_CLASSIC_BINDINGS:-0} == 1 ]]; then
  link_options+=(-Wl,-no_fixup_chains)
fi
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=16.0 \
  -fobjc-arc -fmodules -dynamiclib -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types \
  -framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers -framework CoreLocation -framework AVFAudio -framework EventKit \
  LocalTranslationEntry.m ExperimentalOTA.m ExperimentalOTAGuard.m ExperimentalOTAFlash.m ExperimentalOTAFeed.m ExperimentalOTAUI.m NavigationModes.m ProtocolContext.m NavigationSubtitleHUD.m NavigationPlaces.m NavigationPlacePicker.m \
  ${nav_options[@]+"${nav_options[@]}"} \
  ${image_options[@]+"${image_options[@]}"} \
  "-DTIO_TARGET_BUNDLE_ID=\"$bundle\"" -install_name "$install_name" ${link_options[@]+"${link_options[@]}"} \
  Core.m Profile.m ProfileUI.m KnowledgeClient.m KnowledgeUI.m HomeTabLayout.m HomeTabBridge.m ResearchCatalog.m ResearchUI.m NewsPresentation.m PrivateBootstrap.m WebSearch.m AppleCalendarSync.m TodoProtocol.m TodoCompletionLedger.m TodoRuntime.m A2UIProtocol.m A2UIProbe.m NavigationCore.m NavigationTeleHUD.m NavigationTransport.m NavigationUI.m ManualHUD.m SubtitleHUDCore.m SubtitleHUD.m GlassesLogContract.m GlassesLogGate.m GlassesLogProbe.m NewsCore.m NewsArchive.m NewsReader.m NewsTeleprompter.m RecordingExports.m RecordingExportsUI.m RecordingExportsMenu.m RecordingText.m RecordingTextUI.m RecordingTextMenu.m AlwaysOnAudioFiles.m AlwaysOnOgg.m AlwaysOnAudioNative.m AlwaysOnAudioUI.m TDPhoneStore.m TDPhoneRun.m TDPhoneUI.m TDPhoneReply.m TDPhoneBridge.m TDTransport.m diagnostics.c command.c WeReadAPI.m FocusTransport.m FocusBridge.m focus.c ReaderTransport.m ReaderBridge.m ReadingOverview.m ReadingContent.m ReaderUI.m reader.c -lz -lxml2 -I"$(xcrun --sdk iphoneos --show-sdk-path)/usr/include/libxml2" VoiceTTSCore.m VoiceTTS.m MusicAPI.m MusicTransport.m MusicBridge.m MusicPlayer.m MusicUI.m music.c -framework AVFoundation -framework MediaPlayer -framework CoreImage -framework ImageIO Addon.m -o "$output"
codesign --force --sign - "$output"
plutil -lint TurboIOPrivateAddon.plist
shasum -a 256 "$output"
