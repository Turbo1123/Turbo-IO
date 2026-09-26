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
  [[ "$mode" == embedded ]] || { echo 'Navigation requires embedded mode' >&2; exit 2; }
  nav_root="${TIO_AMAP_SDK_ROOT:-$PWD/build/amap-sdk}"
  for part in navi/AMapNaviKit foundation/AMapFoundationKit search/AMapSearchKit; do
    [[ -f "$nav_root/$part.framework/$(basename "$part")" ]] || { echo 'Run setup-amap.mjs first; missing pinned SDK' >&2; exit 2; }
  done
  output=build/navigation/TurboIOPrivateAddon.dylib; mkdir -p build/navigation
  nav_options=(-DTIO_AMAP_ENABLED=1 -F "$nav_root/navi" -F "$nav_root/foundation" -F "$nav_root/search" -framework AMapNaviKit -framework AMapFoundationKit -framework AMapSearchKit -lc++ -lz -lsqlite3 -framework SystemConfiguration -framework CoreTelephony -framework QuartzCore -framework CoreGraphics -framework OpenGLES -framework GLKit -framework CoreMotion -framework AVFoundation -framework AudioToolbox -framework Accelerate -framework Metal -framework CoreText -framework CallKit -framework WebKit)
fi
ota_options=()
ota_sources=()
native_options=()
native_sources=()
navigation_ui=NavigationUI.m
music_options=()
music_sources=()
if [[ ${TIO_MUSIC:-0} == 1 ]]; then
  [[ ${TIO_NATIVE_NAV:-0} == 1 ]] || { echo 'TMU1 requires TIO_NATIVE_NAV=1 and its explicit research gates' >&2; exit 2; }
  music_options=(-DTIO_MUSIC=1 -I "$PWD/music" -framework AVFoundation -framework MediaPlayer -framework CoreImage -framework ImageIO)
  for unit in MusicAPI.m MusicTransport.m MusicBridge.m MusicPlayer.m MusicUI.m music.c; do music_sources+=("music/$unit"); done
fi
if [[ ${TIO_NATIVE_NAV:-0} == 1 ]]; then
  [[ ${TIO_OTA_RESEARCH_ENABLED:-0} == 1 && "$mode" == embedded ]] || { echo 'TNV1 requires explicit TIO_OTA_RESEARCH_ENABLED=1 and embedded mode' >&2; exit 2; }
  ota_root=../firmware-research/strix-1.0.4.12/native-navigation/phone
  if [[ ${TIO_MUSIC:-0} == 1 ]]; then ota_root=../firmware-research/strix-1.0.4.12/native-navigation/music/phone; fi
  navigation_ui="$ota_root/NavigationUI.m"
  native_options=(-DTIO_NATIVE_NAV=1 -DTIO_DISPLAY_PHONE=1 -DTIO_DISPLAY_DIAGNOSTICS=1 -DTIO_DISPLAY_FLASH=1 -DTIO_IMAGE_RX_LAB=1 -DTIO_IMAGE_RX_WIDE=1 -I "$ota_root" -I "$PWD" -framework PhotosUI -framework ImageIO -framework CoreGraphics)
  for unit in nav_runtime.c NativeNavigation.m TNVTransport.m NativeNavigationUI.m display_runtime.c display_client.c display_carrier.c DisplayDelta.c DisplayNavigation.m DisplayHUDRenderer.m DisplayReplyObserver.m DisplayPhoneSession.m DisplayPhoneTransport.m DisplayPhoneUI.m DisplayDiagnostics.m ImageUpload.m ImageUploadTransport.m ImageUploadNative.m ImageUploadUI.m; do
    native_sources+=("$ota_root/$unit")
  done
fi
if [[ ${TIO_OTA_RESEARCH_ENABLED:-0} == 1 ]]; then
  [[ "$mode" == embedded && "$bundle" == com.rayneo.venus.pub ]] || { echo 'Firmware research requires embedded original bundle; see firmware safety documentation' >&2; exit 2; }
  ota_root=${ota_root:-../firmware-research/strix-1.0.4.12/ios-reference}
  ota_options=(-DTIO_OTA_RESEARCH_ENABLED=1 -DTIO_OTA_FLASH_ENABLED=1 -DTIO_OTA_FEED_ARMING_ENABLED=1 -I "$ota_root" -I "$PWD")
  ota_sources=("$ota_root/ExperimentalOTA.m" "$ota_root/ExperimentalOTAGuard.m" "$ota_root/ExperimentalOTAFlash.m" "$ota_root/ExperimentalOTAFeed.m" "$ota_root/ExperimentalOTAUI.m")
  output=build/ota-research/TurboIOPrivateAddon.dylib; mkdir -p build/ota-research
fi
if [[ ${TIO_NATIVE_NAV:-0} == 1 ]]; then
  output=build/native-navigation/TurboIOPrivateAddon.dylib; mkdir -p build/native-navigation
fi
if [[ ${TIO_MUSIC:-0} == 1 ]]; then output=build/music/TurboIOPrivateAddon.dylib; mkdir -p build/music; fi
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
caption_options=()
caption_sources=()
subtitle_core=SubtitleHUDCore.m
subtitle_runtime=SubtitleHUD.m
if [[ ${TIO_LOCAL_TRANSLATION:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Local translation requires embedded mode and iOS 26+' >&2; exit 2; }
  caption_options=(-DTIO_LOCAL_TRANSLATION=1 -I "$PWD/local-translation" -I "$PWD")
  caption_sources=(local-translation/LocalTranslationEntry.m)
  subtitle_core=local-translation/SubtitleHUDCore.m
  subtitle_runtime=local-translation/SubtitleHUD.m
  output=build/local-translation/TurboIOPrivateAddon.dylib; mkdir -p build/local-translation
fi
link_options=()
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
# Keep the normal embedded build unchanged until the device comparison passes.
if [[ ${TIO_CLASSIC_BINDINGS:-1} == 1 ]]; then
  link_options+=(-Wl,-no_fixup_chains)
fi
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=16.0 \
  -fobjc-arc -fmodules -dynamiclib -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types \
  -framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers -framework CoreLocation -framework AVFAudio -framework EventKit \
  ${nav_options[@]+"${nav_options[@]}"} \
  ${ota_options[@]+"${ota_options[@]}"} ${ota_sources[@]+"${ota_sources[@]}"} \
  ${native_options[@]+"${native_options[@]}"} ${native_sources[@]+"${native_sources[@]}"} \
  ${music_options[@]+"${music_options[@]}"} ${music_sources[@]+"${music_sources[@]}"} \
  ${caption_options[@]+"${caption_options[@]}"} ${caption_sources[@]+"${caption_sources[@]}"} \
  NavigationModes.m ProtocolContext.m NavigationSubtitleHUD.m NavigationPlaces.m NavigationPlacePicker.m A2UIProtocol.m NavigationCore.m NavigationTeleHUD.m NavigationTransport.m "$navigation_ui" ManualHUD.m "$subtitle_core" "$subtitle_runtime" \
  "-DTIO_TARGET_BUNDLE_ID=\"$bundle\"" -install_name "$install_name" "${link_options[@]}" \
  Core.m Profile.m KnowledgeClient.m KnowledgeUI.m ProfileUI.m HomeTabLayout.m HomeTabBridge.m ResearchCatalog.m ResearchUI.m NewsPresentation.m PrivateBootstrap.m VoiceTTSCore.m VoiceTTS.m WebSearch.m AppleCalendarSync.m TodoProtocol.m TodoCompletionLedger.m TodoRuntime.m NewsCore.m NewsReader.m NewsTeleprompter.m RecordingExports.m RecordingExportsUI.m RecordingExportsMenu.m RecordingText.m RecordingTextUI.m RecordingTextMenu.m AlwaysOnAudioFiles.m AlwaysOnOgg.m AlwaysOnAudioNative.m AlwaysOnAudioUI.m Addon.m -o "$output"
codesign --force --sign - "$output"
plutil -lint TurboIOPrivateAddon.plist
shasum -a 256 "$output"
