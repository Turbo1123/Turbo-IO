#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -framework Foundation NavigationBackgroundTests.m -o build/navigation-background-tests
./build/navigation-background-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation HostCompatibilityTests.m -o build/host-compatibility-tests
./build/host-compatibility-tests
node --test host-compatibility.test.mjs
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation NavigationModes.m NavigationModesTests.m -o build/navigation-modes-tests
./build/navigation-modes-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation Profile.m ProfileTests.m -o build/profile-tests
./build/profile-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation Core.m Profile.m WebSearch.m KnowledgeToolFlowTests.m -o build/knowledge-tool-tests
./build/knowledge-tool-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation HomeTabLayout.m HomeTabLayoutTests.m -o build/home-tab-layout-tests
./build/home-tab-layout-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation ResearchCatalog.m ResearchCatalogTests.m -o build/research-catalog-tests
./build/research-catalog-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation VoiceTTSCore.m VoiceTTSTests.m -o build/voice-tts-tests
./build/voice-tts-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation NewsPresentation.m NewsPresentationTests.m -o build/news-presentation-tests
./build/news-presentation-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation Core.m Profile.m Tests.m -o build/core-tests
./build/core-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -framework Foundation Core.m Profile.m PrivateBootstrap.m PrivateBootstrapTests.m -o build/private-bootstrap-tests
./build/private-bootstrap-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation TodoProtocol.m TodoProtocolTests.m -o build/todo-protocol-tests
./build/todo-protocol-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation RecordingExports.m RecordingExportsTests.m -o build/recording-export-tests
./build/recording-export-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation RecordingText.m RecordingTextTests.m -o build/recording-text-tests
./build/recording-text-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation AlwaysOnAudioFiles.m AlwaysOnOgg.m AlwaysOnAudioTests.m -o build/alwayson-audio-tests
./build/alwayson-audio-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation AlwaysOnOgg.m AlwaysOnOggTests.m -o build/alwayson-ogg-tests
./build/alwayson-ogg-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation WebSearch.m WebSearchTests.m -o build/web-search-tests
./build/web-search-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation Core.m Profile.m WebSearch.m WebSearchFlowTests.m -o build/web-search-flow-tests
./build/web-search-flow-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation TodoBridgeClient.m TodoBridgeClientTests.m -o build/todo-bridge-client-tests
./build/todo-bridge-client-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation Core.m Profile.m WebSearch.m TodoToolFlowTests.m -o build/todo-tool-flow-tests
./build/todo-tool-flow-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -framework Foundation NewsCore.m NewsCoreTests.m -o build/news-core-tests
./build/news-core-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation TodoProtocol.m NewsCaption.m NewsCaptionTests.m -o build/news-caption-tests
./build/news-caption-tests
xcrun clang -DNSHomeDirectory=TIOTestHome -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation TodoProtocol.m ProtocolContext.m NewsTeleprompter.m NewsTeleprompterTests.m -o build/news-teleprompter-tests
./build/news-teleprompter-tests

xcrun clang -DNSHomeDirectory=TIOTestHome -fobjc-arc -fmodules -Wno-incompatible-pointer-types -framework Foundation TodoProtocol.m ProtocolContext.m NewsTeleprompter.m ProtocolRestartTests.m -o build/protocol-restart-tests
protocol_test_dir=$(mktemp -d "$PWD/build/protocol-restart-test.XXXXXX")
./build/protocol-restart-tests write "$protocol_test_dir"
./build/protocol-restart-tests read "$protocol_test_dir"
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation SubtitleHUDCore.m SubtitleHUDTests.m -o build/subtitle-hud-tests
./build/subtitle-hud-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation A2UIProtocol.m NavigationCore.m SubtitleHUDCore.m NavigationSubtitleHUD.m NavigationSubtitleHUDTests.m -o build/navigation-subtitle-tests
./build/navigation-subtitle-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation A2UIProtocol.m NavigationCore.m NavigationCoreTests.m -o build/navigation-core-tests
./build/navigation-core-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-incompatible-pointer-types -framework Foundation A2UIProtocol.m NavigationCore.m NavigationPlaces.m NavigationPlacesTests.m -o build/navigation-places-tests
./build/navigation-places-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation A2UIProtocol.m NavigationCore.m NavigationTeleHUD.m NavigationTeleHUDTests.m -o build/navigation-tele-tests
./build/navigation-tele-tests
xcrun clang -fobjc-arc -fmodules -Wno-incompatible-pointer-types -framework Foundation A2UIProtocol.m A2UIProtocolTests.m -o build/a2ui-protocol-tests
./build/a2ui-protocol-tests
node --test package.test.mjs
(
  cd focus-edition
  mkdir -p build
  xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation CueCardsCore.m CueCardsCoreTests.m reader.c -o build/cue-cards-core-tests
  ./build/cue-cards-core-tests
)
python3 ../firmware-research/strix-1.0.4.12/native-navigation/workout/test_overlay.py
