#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="${ANDROID_SDK_ROOT:?Set ANDROID_SDK_ROOT}"
build_tools="$sdk/build-tools/36.0.0"
android_jar="$sdk/platforms/android-36/android.jar"
mkdir -p build/classes build/test build/dex
javac -encoding UTF-8 -d build/test src/com/turboio/addon/HostBusiness.java tests/HostBusinessTest.java
java -cp build/test com.turboio.addon.HostBusinessTest
node tests/HostProfilesTest.mjs
mkdir -p build/test-hostabi
javac -encoding UTF-8 -source 8 -target 8 -d build/test-hostabi src/com/turboio/addon/HostAbi.java tests/HostAbiTest.java
java -Dturboio.host=1.0.6 -cp build/test-hostabi com.turboio.addon.HostAbiTest X3.Q t u X3.u i4.h j4.q
java -Dturboio.host=1.0.7 -cp build/test-hostabi com.turboio.addon.HostAbiTest Y3.S t u Y3.u j4.h k4.q
# Un-forced probe: newest host first, a 1.0.6 tree with a Y3.u decoy stays 1.0.6, nothing found falls back to 1.0.6.
for stub in v106 v107 decoy; do mkdir -p build/test-hostabi-$stub && javac -encoding UTF-8 -source 8 -target 8 -d build/test-hostabi-$stub $(find tests/hostabi/$stub -name '*.java'); done
java -cp build/test-hostabi:build/test-hostabi-v106 com.turboio.addon.HostAbiTest X3.Q t u X3.u i4.h j4.q
java -cp build/test-hostabi:build/test-hostabi-v107 com.turboio.addon.HostAbiTest Y3.S t u Y3.u j4.h k4.q
java -cp build/test-hostabi:build/test-hostabi-v106:build/test-hostabi-decoy com.turboio.addon.HostAbiTest X3.Q t u X3.u i4.h j4.q
java -cp build/test-hostabi com.turboio.addon.HostAbiTest X3.Q t u X3.u i4.h j4.q
node tests/OtaHooksTest.mjs
node tests/OfficialOtaSourceTest.mjs
python3 tests/ApkAssemblyTest.py
python3 tests/ReaderDemoTest.py
python3 tests/TtsManifestTest.py
python3 tests/BackgroundManifestTest.py
mkdir -p build/test/focus-golden
cc -Wall -Wextra -Werror -I../official-addon/research/focus-v1 tests/focus_golden.c ../official-addon/research/focus-v1/focus.c -o build/test/focus-golden/generate
build/test/focus-golden/generate build/test/focus-golden
javac -encoding UTF-8 -d build/test src/com/turboio/addon/FocusCodec.java tests/FocusCodecTest.java
java -cp build/test FocusCodecTest build/test/focus-golden
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/TransferGate.java tests/TransferGateTest.java
java -cp build/test TransferGateTest
mkdir -p build/test-host-events
javac -encoding UTF-8 -d build/test src/com/turboio/addon/LauncherMeta.java tests/LauncherMetaTest.java
java -cp build/test com.turboio.addon.LauncherMetaTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-host-events tests/hostevents/*.java tests/musicflow/SystemClock.java src/com/turboio/addon/NativeTransfer.java src/com/turboio/addon/HostAbi.java
java -cp build/test-host-events:build/test com.turboio.addon.HostEventTest
"${TURBO_SDK_PYTHON:-python3}" tests/app_golden.py
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/{BoundedJson,AppCodec,FocusCodec,CustomEnvelope}.java tests/AppCodecTest.java
java -cp build/test AppCodecTest ../app-gallery build/test/app-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test tests/CustomEnvelopeTest.java
java -cp build/test CustomEnvelopeTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{HostAbi,OtaFrame,OtaPackage,OtaRecoveryGuard,OtaSession}.java tests/OtaTest.java tests/OtaRecoveryGuardTest.java
java -cp build/test com.turboio.addon.OtaRecoveryGuardTest
# TVP2 is the only candidate (hosts 1.0.6 / 1.0.7). TMIG1, stock 1.0.5.5 and TAP1 must all be refused.
ota_candidate=../official-addon/build/strix-1.0.5.5-tvp2/StrixOS-1.0.5.5-TurboIO-TVP2-CANDIDATE-NOT-APPROVED.zip
tmig1_dir=../official-addon/build/strix-1.0.5.5-tmig1
refused=("$tmig1_dir/StrixOS-1.0.5.5-TurboIO-TMIG1-CANDIDATE-NOT-APPROVED.zip" "$tmig1_dir/Strix-OS-1.0.5.5-original.zip" ../official-addon/build/app-ap-20260927-test-01/StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip)
java -cp build/test com.turboio.addon.OtaTest "$ota_candidate"
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/OfficialOtaFeed.java tests/OfficialOtaFeedTest.java
javac -encoding UTF-8 -cp build/test -d build/test tests/OfficialOtaDirectoryTest.java
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/OfficialOtaGate.java tests/OfficialOtaGateTest.java
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test tests/Tvp2CandidateTest.java
for host in 1.0.6 1.0.7; do
  java -Dturboio.host=$host -cp build/test com.turboio.addon.Tvp2CandidateTest "$ota_candidate" "${refused[@]}"
  java -Dturboio.host=$host -cp build/test com.turboio.addon.OfficialOtaFeedTest "$ota_candidate"
  java -Dturboio.host=$host -cp build/test com.turboio.addon.OfficialOtaDirectoryTest "$ota_candidate"
  java -Dturboio.host=$host -cp build/test com.turboio.addon.OfficialOtaGateTest "$ota_candidate"
done
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/OfficialOtaPreflightPoll.java tests/OfficialOtaPreflightPollTest.java
java -cp build/test com.turboio.addon.OfficialOtaPreflightPollTest
mkdir -p build/test-ota-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-ota-flow tests/otaflow/*.java src/com/turboio/addon/OtaController.java src/com/turboio/addon/HostAbi.java
java -cp build/test-ota-flow:build/test com.turboio.addon.OtaControllerTest "$ota_candidate"
java -cp build/test-ota-flow:build/test com.turboio.addon.OtaControllerTest unused recovery
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{CardCodec,CardEnvelope}.java tests/CardCodecTest.java
java -cp build/test CardCodecTest build/test/card-golden
# TDC1 developer card: Java validator vs the iOS/firmware C dc_parse.
mkdir -p build/test/devcard-golden
cc -Wall -Wextra -Werror -I../official-addon/ios107-edition tests/devcard_golden.c ../official-addon/ios107-edition/card.c -o build/test/devcard-golden/generate
build/test/devcard-golden/generate build/test/devcard-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test tests/DevCardTest.java
java -cp build/test com.turboio.addon.DevCardTest build/test/devcard-golden
cc -Wall -Wextra -Werror -I../official-addon/research/dashboard-editor-v1 tests/card_native.c ../official-addon/research/dashboard-editor-v1/editor.c -o build/test/card-native
build/test/card-native build/test/card-golden
mkdir -p build/test-card-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-card-flow tests/cardflow/*.java src/com/turboio/addon/CardTransport.java
java -cp build/test-card-flow:build/test com.turboio.addon.CardFlowTest
# TMG2 menu layout (2/3 rows): Java codec vs the iOS/firmware C codec.
mkdir -p build/test/menu-golden
cc -Wall -Wextra -Werror -I../official-addon/ios107-edition tests/menu_golden.c ../official-addon/ios107-edition/menu_config.c -o build/test/menu-golden/generate
build/test/menu-golden/generate build/test/menu-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{HexCarrier,MenuCodec}.java tests/MenuCodecTest.java
java -cp build/test com.turboio.addon.MenuCodecTest build/test/menu-golden
# TCM1 remote camera: Java codec vs the iOS/firmware C codec.
mkdir -p build/test/camera-golden
cc -Wall -Wextra -Werror -I../official-addon/ios107-edition/camera-v1 tests/camera_golden.c ../official-addon/ios107-edition/camera-v1/camera.c -o build/test/camera-golden/generate
build/test/camera-golden/generate build/test/camera-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{HexCarrier,CameraCodec}.java tests/CameraCodecTest.java
java -cp build/test com.turboio.addon.CameraCodecTest build/test/camera-golden
mkdir -p build/test-camera-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-camera-flow tests/cameraflow/*.java src/com/turboio/addon/{CameraLink,CameraShutter}.java
java -cp build/test-camera-flow:build/test com.turboio.addon.CameraLinkTest
java -cp build/test-camera-flow:build/test com.turboio.addon.CameraShutterTest
# TDG1 glasses diagnostics: Java codec vs the iOS/firmware C codec.
mkdir -p build/test/tdg-golden
cc -Wall -Wextra -Werror -I../official-addon/ios107-edition tests/tdg_golden.c ../official-addon/ios107-edition/command.c ../official-addon/ios107-edition/diagnostics.c -o build/test/tdg-golden/generate
build/test/tdg-golden/generate build/test/tdg-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{HexCarrier,TdgCodec}.java tests/TdgCodecTest.java
java -cp build/test com.turboio.addon.TdgCodecTest build/test/tdg-golden
mkdir -p build/test-diag-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-diag-flow tests/diagflow/*.java tests/musicflow/SystemClock.java src/com/turboio/addon/{DiagnosticsRun,CustomEnvelope,BoundedJson,TransferGate}.java
java -cp build/test-diag-flow:build/test com.turboio.addon.DiagnosticsRunTest
# TNR3 nav-map wire codec: Java vs the iOS/firmware nav_map.c.
mkdir -p build/test/navmap-golden
cc -Wall -Wextra -Werror -I../official-addon/ios107-edition -I../official-addon/ios107-edition/navigation-runtime-v1 tests/navmap_golden.c ../official-addon/ios107-edition/nav_map.c ../official-addon/ios107-edition/navigation-runtime-v1/nav_runtime.c -o build/test/navmap-golden/generate
build/test/navmap-golden/generate build/test/navmap-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/NavMapCodec.java tests/NavMapCodecTest.java
java -cp build/test com.turboio.addon.NavMapCodecTest build/test/navmap-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{RoadScene,BoundedJson}.java tests/RoadSceneTest.java
java -cp build/test com.turboio.addon.RoadSceneTest ../official-addon/ios107-edition/tests/maps
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/RoadFetch.java tests/RoadFetchTest.java
java -cp build/test com.turboio.addon.RoadFetchTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{RoadFrames,NativeNavCodec}.java tests/RoadFramesTest.java
java -cp build/test com.turboio.addon.RoadFramesTest ../official-addon/ios107-edition/tests/maps
mkdir -p build/test/english-golden
EN=../firmware-research/strix-1.0.5.5-tvp2/src/context-english-v1
cc -Wall -Wextra -Werror -I$EN tests/english_golden.c $EN/english_wire.c $EN/english_view.c $EN/english_progress.c $EN/english_transfer.c -o build/test/english-golden/generate
build/test/english-golden/generate build/test/english-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/CeWire.java tests/CeWireTest.java
java -cp build/test com.turboio.addon.CeWireTest build/test/english-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{CeTransfer,CeSession,TransferGate}.java tests/CeTransferTest.java
java -cp build/test com.turboio.addon.CeTransferTest build/test/english-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{CeHive,CeLifelog}.java tests/CeLifelogTest.java
java -cp build/test com.turboio.addon.CeLifelogTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{CeCore,CeHistory,BoundedJson}.java tests/CeCoreTest.java
java -cp build/test com.turboio.addon.CeCoreTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/CeAuto.java tests/CeAutoTest.java
java -cp build/test com.turboio.addon.CeAutoTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/NotificationArchive.java tests/NotificationArchiveTest.java
java -cp build/test com.turboio.addon.NotificationArchiveTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/NotificationRuntime.java tests/NotificationRuntimeTest.java
java -cp build/test com.turboio.addon.NotificationRuntimeTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/TnlCore.java tests/TnlCoreTest.java
java -cp build/test com.turboio.addon.TnlCoreTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/TnlStore.java tests/TnlStoreTest.java
java -cp build/test com.turboio.addon.TnlStoreTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/ModelCall.java tests/ModelCallTest.java
java -cp build/test com.turboio.addon.ModelCallTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/RecordingText.java tests/RecordingTextTest.java
java -cp build/test com.turboio.addon.RecordingTextTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/KnowledgeView.java tests/KnowledgeViewTest.java
java -cp build/test com.turboio.addon.KnowledgeViewTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/AlwaysOnAudio.java tests/AlwaysOnAudioTest.java
java -cp build/test com.turboio.addon.AlwaysOnAudioTest
mkdir -p build/test/ride-golden
DR=../firmware-research/strix-1.0.5.5-tvp2/src
cc -Wall -Wextra -Werror -I$DR/didi-v1 -I$DR/navigation-runtime-v1 tests/ride_golden.c $DR/didi-v1/ride.c $DR/navigation-runtime-v1/nav_runtime.c -o build/test/ride-golden/generate
build/test/ride-golden/generate build/test/ride-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{DrWire,DrText,DrTool}.java tests/DrCoreTest.java
java -cp build/test com.turboio.addon.DrCoreTest build/test/ride-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{DrRpc,DrService}.java tests/DrServiceTest.java
java -cp build/test com.turboio.addon.DrServiceTest
mkdir -p build/test/timg-golden
IM=../firmware-research/strix-1.0.5.5-tvp2/src/image-upload-test
cc -Wall -Wextra -Werror -DTIO_IMAGE_RX_WIDE=1 -I$IM -I../firmware-research/strix-1.0.5.5-tvp2 tests/timg_golden.c $IM/image_receiver.c $IM/image_mailbox.c $IM/image_test.c $IM/native_file_bridge.c -o build/test/timg-golden/generate
build/test/timg-golden/generate build/test/timg-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{Timg,ImageUpload,TransferGate}.java tests/TimgTest.java
java -cp build/test com.turboio.addon.TimgTest build/test/timg-golden
mkdir -p build/test/tdp-golden
TDPF=../firmware-research/strix-1.0.5.5-tvp2/src/display-runtime-v1;TDPI=../official-addon/ios107-edition
cc -Wall -Wextra -Werror -I$TDPF -I$TDPI tests/tdp_golden.c $TDPF/display_client.c $TDPF/display_carrier.c $TDPF/display_runtime.c $TDPI/DisplayDelta.c -o build/test/tdp-golden/generate
build/test/tdp-golden/generate build/test/tdp-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/Tdp.java tests/TdpTest.java
java -cp build/test com.turboio.addon.TdpTest build/test/tdp-golden
cc -Wall -Wextra -Werror -I$TDPF tests/tdp_oracle.c $TDPF/display_runtime.c -o build/test/tdp-golden/oracle
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/TdpSession.java tests/TdpSessionTest.java
java -cp build/test com.turboio.addon.TdpSessionTest build/test/tdp-golden/oracle
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/DisplayCopy.java tests/DisplayCopyTest.java
java -cp build/test com.turboio.addon.DisplayCopyTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{NavCore,BoundedJson,SubtitleTrial}.java tests/SubtitleTrialTest.java
java -cp build/test com.turboio.addon.SubtitleTrialTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{BoundedJson,HostBusiness,A2uiFrame,GlassesLogContract,GlassesLogGate}.java tests/GlassesLogTest.java
java -cp build/test com.turboio.addon.GlassesLogTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/GlassesLogFiles.java tests/GlassesLogFilesTest.java
java -cp build/test com.turboio.addon.GlassesLogFilesTest
mkdir -p build/test/hd-golden
VPF=../firmware-research/strix-1.0.5.5-tvp2/src/video-player-v1
cc -Wall -Wextra -Werror -I$VPF tests/hd_golden.c $VPF/player.c -o build/test/hd-golden/generate
build/test/hd-golden/generate build/test/hd-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{Vp,HdEncoder}.java tests/HdTest.java
java -cp build/test com.turboio.addon.HdTest build/test/hd-golden
cc -Wall -Wextra -Werror -I$VPF tests/hd_oracle.c $VPF/player.c -o build/test/hd-golden/oracle
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/HdLink.java tests/HdLinkTest.java
java -cp build/test com.turboio.addon.HdLinkTest build/test/hd-golden/oracle
mkdir -p build/test-menu-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-menu-flow tests/menuflow/*.java tests/musicflow/SystemClock.java src/com/turboio/addon/MenuLayout.java
java -cp build/test-menu-flow:build/test com.turboio.addon.MenuLayoutTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/ChatPolicy.java tests/ChatPolicyTest.java
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/VoiceExit.java tests/VoiceExitTest.java
java -cp build/test com.turboio.addon.VoiceExitTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/{CloudTts,BoundedJson}.java tests/CloudTtsTest.java
java -cp build/test com.turboio.addon.CloudTtsTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{BoundedWebSocket,ReaderCodec}.java tests/WebSocketFrameTest.java
java -cp build/test com.turboio.addon.WebSocketFrameTest
java -cp build/test ChatPolicyTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/SpeechBuffer.java tests/SpeechBufferTest.java
java -cp build/test com.turboio.addon.SpeechBufferTest
mkdir -p build/test/music-golden
cc -Wall -Wextra -I../official-addon/research/music-runtime-v1 tests/music_golden.c ../official-addon/research/music-runtime-v1/music.c -o build/test/music-golden/generate
build/test/music-golden/generate build/test/music-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/MusicCodec.java tests/MusicCodecTest.java
java -cp build/test com.turboio.addon.MusicCodecTest build/test/music-golden
mkdir -p build/test-music-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-music-flow tests/musicflow/*.java tests/hostevents/Log.java src/com/turboio/addon/MusicBridge.java
java -cp build/test-music-flow:build/test com.turboio.addon.MusicFlowTest
mkdir -p build/test-focus-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-focus-flow tests/musicflow/{Context,SharedPreferences,SystemClock}.java tests/focusflow/*.java src/com/turboio/addon/FocusController.java
java -cp build/test-focus-flow:build/test com.turboio.addon.FocusFlowTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{ReaderCodec,CaptionText,BoundedWebSocket}.java tests/ReaderCaptionTest.java
java -cp build/test com.turboio.addon.ReaderCaptionTest build/test/reader-golden
mkdir -p build/test-reader-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-reader-flow tests/musicflow/{Context,SharedPreferences,SystemClock,NativeTransfer}.java tests/readerflow/*.java src/com/turboio/addon/ReaderBridge.java
java -cp build/test-reader-flow:build/test com.turboio.addon.ReaderFlowTest
cc -Wall -Wextra -I../official-addon/research/weread-v1 tests/reader_native.c ../official-addon/research/weread-v1/reader.c -o build/test/reader-native
build/test/reader-native build/test/reader-golden
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/NavCore.java tests/NavCoreTest.java
java -cp build/test NavCoreTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/NavSessionPolicy.java tests/NavSessionPolicyTest.java
java -cp build/test NavSessionPolicyTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/NavCore.java src/com/turboio/addon/NavSimulation.java tests/NavSimulationTest.java
java -cp build/test NavSimulationTest
mkdir -p build/test/nav-golden
cc -Wall -Wextra -Werror -I../official-addon/research/navigation-runtime-v1 tests/nav_golden.c ../official-addon/research/navigation-runtime-v1/nav_runtime.c -o build/test/nav-golden/generate
build/test/nav-golden/generate build/test/nav-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{NativeNavCodec,NativeNavSession,NativeNavRoute}.java tests/NativeNavTest.java
java -cp build/test NativeNavTest build/test/nav-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{NativeNavCodec,NativeNavSession,NavMapCodec,HexCarrier}.java tests/NativeNavMapTest.java
java -cp build/test NativeNavMapTest
javac -encoding UTF-8 -source 8 -target 8 -cp "$android_jar" -d build/classes src/com/turboio/addon/*.java
jar cf build/turboio-addon.jar -C build/classes .
# Official GUARD bridge manual release. Fakes first; android.jar and the add-on classes only satisfy
# class loading for UI code that never runs here.
rm -rf build/test-ota-bridge && mkdir -p build/test-ota-bridge
javac -encoding UTF-8 -source 8 -target 8 -cp "$android_jar:build/classes" -d build/test-ota-bridge $(find tests/otabridge -name '*.java') src/com/turboio/addon/{OfficialOtaBridge,OfficialOtaGate,OfficialOtaFeed,OfficialOtaPreflightPoll,OtaRecoveryGuard,OtaPackage,OtaFrame,BoundedJson,HostAbi,HostBusiness}.java
java -cp "build/test-ota-bridge:$android_jar:build/classes" com.turboio.addon.OfficialOtaReleaseTest
"$build_tools/d8" --lib "$android_jar" --min-api 29 --output build/dex build/turboio-addon.jar
shasum -a 256 build/dex/classes.dex
