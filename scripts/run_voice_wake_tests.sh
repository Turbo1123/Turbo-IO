#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p artifacts/voice-wake/module-cache
xcrun swiftc -module-cache-path artifacts/voice-wake/module-cache \
  core-probe/Sources/SpeechEndpointDetector.swift \
  core-probe/Sources/StandbyVoiceSession.swift \
  core-probe/Tests/StandbyWakeTests.swift \
  -o artifacts/voice-wake/standby-wake-tests
artifacts/voice-wake/standby-wake-tests
