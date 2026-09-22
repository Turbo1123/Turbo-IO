#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk" && -n "${LOCALAPPDATA:-}" && -d "${LOCALAPPDATA}/Android/Sdk" ]]; then
  sdk="${LOCALAPPDATA}/Android/Sdk"
fi
build_tools="$sdk/build-tools/36.0.0"
android_jar="$sdk/platforms/android-36/android.jar"
for tool in javac java; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
mkdir -p build/classes build/test build/dex
jdk_sources=(
  src/com/turboio/addon/ChatPolicy.java
  src/com/turboio/addon/RayneoAuthDiagnostic.java
  src/com/turboio/addon/NavCore.java
  src/com/turboio/addon/NavSessionPolicy.java
  src/com/turboio/addon/NavSimulation.java
  src/com/turboio/addon/AlwaysOnConsume.java
  src/com/turboio/addon/RayneoContextQueue.java
  src/com/turboio/addon/RayneoCurrentQuestion.java
  src/com/turboio/addon/RayneoContextProtocol.java
  src/com/turboio/addon/RayneoQueryBridge.java
  src/com/turboio/addon/RayneoSourceIdentity.java
)
javac -encoding UTF-8 -source 8 -target 8 -d build/test "${jdk_sources[@]}" tests/*.java
for test in ChatPolicyTest NavCoreTest NavSessionPolicyTest NavSimulationTest AlwaysOnContextTest AlwaysOnContractTest AlwaysOnWindowTest com.turboio.addon.RayneoAuthDiagnosticTest; do
  java -cp build/test "$test"
done
if [[ -z "$sdk" || ! -f "$android_jar" || ! -x "$build_tools/d8" ]]; then
  echo 'SDK/d8 missing; JDK-8 tests passed (original addon dex not rebuilt).'
  exit 0
fi
command -v jar >/dev/null || { echo "Missing tool: jar" >&2; exit 1; }
javac -encoding UTF-8 -source 8 -target 8 -cp "$android_jar" -d build/classes \
  src/com/turboio/addon/ChatPolicy.java src/com/turboio/addon/NavCore.java \
  src/com/turboio/addon/NavGlasses.java src/com/turboio/addon/NavigationUI.java \
  src/com/turboio/addon/NavReflect.java src/com/turboio/addon/NavSessionPolicy.java \
  src/com/turboio/addon/NavSimulation.java src/com/turboio/addon/RecordingExports.java \
  src/com/turboio/addon/SecretStore.java src/com/turboio/addon/ToolClient.java \
  src/com/turboio/addon/TurboAddon.java src/com/turboio/addon/TurboStyle.java \
  src/com/turboio/addon/AlwaysOnConsume.java src/com/turboio/addon/RayneoContextQueue.java \
  src/com/turboio/addon/RayneoCurrentQuestion.java src/com/turboio/addon/RayneoContextProtocol.java \
  src/com/turboio/addon/RayneoQueryBridge.java src/com/turboio/addon/RayneoSourceIdentity.java \
  src/com/turboio/addon/RayneoContextClient.java src/com/turboio/addon/RayneoAuthDiagnostic.java
jar cf build/turboio-addon.jar -C build/classes .
"$build_tools/d8" --lib "$android_jar" --min-api 29 --output build/dex build/turboio-addon.jar
echo 'Built build/dex/classes.dex (original addon only; no API keys).'
