#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p artifacts/localization/module-cache
platform="$(xcrun --sdk macosx --show-sdk-platform-path)"
frameworks="$(xcode-select -p)/../SharedFrameworks"
xcrun swiftc -D DEBUG -D APP_LANGUAGE_STANDALONE_TESTS \
  -module-cache-path artifacts/localization/module-cache \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" -L "$platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  apps/RayNeoCompanion/Sources/App/Localization/AppLanguage.swift \
  apps/RayNeoCompanion/Sources/App/Localization/AppLanguageSettings.swift \
  apps/RayNeoCompanion/Tests/AppLanguageTests.swift \
  -o artifacts/localization/language-tests
DYLD_LIBRARY_PATH="$platform/Developer/usr/lib" \
DYLD_FRAMEWORK_PATH="$frameworks" artifacts/localization/language-tests
node --test scripts/localization.test.mjs
