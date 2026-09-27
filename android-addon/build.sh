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
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-host-events tests/hostevents/*.java tests/musicflow/SystemClock.java src/com/turboio/addon/NativeTransfer.java
java -cp build/test-host-events:build/test com.turboio.addon.HostEventTest
"${TURBO_SDK_PYTHON:-python3}" tests/app_golden.py
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/{BoundedJson,AppCodec,FocusCodec,CustomEnvelope}.java tests/AppCodecTest.java
java -cp build/test AppCodecTest ../app-gallery build/test/app-golden
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test tests/CustomEnvelopeTest.java
java -cp build/test CustomEnvelopeTest
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{OtaFrame,OtaPackage,OtaRecoveryGuard,OtaSession}.java tests/OtaTest.java tests/OtaRecoveryGuardTest.java
java -cp build/test com.turboio.addon.OtaRecoveryGuardTest
ota_candidate=../official-addon/build/app-ap-20260927-test-01/StrixOS-1.0.4.12-TAP1-TEST-01-CANDIDATE-NOT-APPROVED.zip
java -cp build/test com.turboio.addon.OtaTest "$ota_candidate"
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/OfficialOtaFeed.java tests/OfficialOtaFeedTest.java
java -cp build/test com.turboio.addon.OfficialOtaFeedTest "$ota_candidate"
javac -encoding UTF-8 -cp build/test -d build/test tests/OfficialOtaDirectoryTest.java
java -cp build/test com.turboio.addon.OfficialOtaDirectoryTest "$ota_candidate"
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/OfficialOtaGate.java tests/OfficialOtaGateTest.java
java -cp build/test com.turboio.addon.OfficialOtaGateTest "$ota_candidate"
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/OfficialOtaPreflightPoll.java tests/OfficialOtaPreflightPollTest.java
java -cp build/test com.turboio.addon.OfficialOtaPreflightPollTest
mkdir -p build/test-ota-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-ota-flow tests/otaflow/*.java src/com/turboio/addon/OtaController.java
java -cp build/test-ota-flow:build/test com.turboio.addon.OtaControllerTest "$ota_candidate"
java -cp build/test-ota-flow:build/test com.turboio.addon.OtaControllerTest unused recovery
java -cp build/test-ota-flow:build/test com.turboio.addon.OtaInstallGuardTest "$ota_candidate"
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test src/com/turboio/addon/{CardCodec,CardEnvelope}.java tests/CardCodecTest.java
java -cp build/test CardCodecTest build/test/card-golden
cc -Wall -Wextra -Werror -I../official-addon/research/dashboard-editor-v1 tests/card_native.c ../official-addon/research/dashboard-editor-v1/editor.c -o build/test/card-native
build/test/card-native build/test/card-golden
mkdir -p build/test-card-flow
javac -encoding UTF-8 -source 8 -target 8 -cp build/test -d build/test-card-flow tests/cardflow/*.java src/com/turboio/addon/CardTransport.java
java -cp build/test-card-flow:build/test com.turboio.addon.CardFlowTest
javac -encoding UTF-8 -source 8 -target 8 -d build/test src/com/turboio/addon/ChatPolicy.java tests/ChatPolicyTest.java
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
javac -encoding UTF-8 -source 8 -target 8 -cp "$android_jar" -d build/classes src/com/turboio/addon/*.java
jar cf build/turboio-addon.jar -C build/classes .
"$build_tools/d8" --lib "$android_jar" --min-api 29 --output build/dex build/turboio-addon.jar
shasum -a 256 build/dex/classes.dex
