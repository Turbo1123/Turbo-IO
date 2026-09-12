#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation Profile.m ProfileTests.m -o build/profile-tests
./build/profile-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation Core.m Profile.m WebSearch.m KnowledgeToolFlowTests.m -o build/knowledge-tool-tests
./build/knowledge-tool-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation HomeTabLayout.m HomeTabLayoutTests.m -o build/home-tab-layout-tests
./build/home-tab-layout-tests
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -framework Foundation ResearchCatalog.m ResearchCatalogTests.m -o build/research-catalog-tests
./build/research-catalog-tests
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
xcrun clang -DNSHomeDirectory=TIOTestHome -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -framework Foundation TodoProtocol.m NewsTeleprompter.m NewsTeleprompterTests.m -o build/news-teleprompter-tests
./build/news-teleprompter-tests
