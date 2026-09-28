#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bundle=${1:-${TIO_COMPANION_BUNDLE_ID:-com.rayneo.venus.pub}}
[[ "$bundle" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$ ]] || { echo 'Invalid companion Bundle ID' >&2; exit 2; }
xcodegen generate --spec project.yml
sign_options=(CODE_SIGNING_ALLOWED=NO)
if [[ -n ${TIO_DEVELOPMENT_TEAM:-} ]]; then
  [[ "$TIO_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple development team ID' >&2; exit 2; }
  sign_options=(CODE_SIGNING_ALLOWED=YES "DEVELOPMENT_TEAM=$TIO_DEVELOPMENT_TEAM" -allowProvisioningUpdates)
fi
xcodebuild -project TurboCueCardsWatch.xcodeproj -scheme CueCardsWatch \
  -destination "${TIO_WATCH_DESTINATION:-generic/platform=watchOS}" -derivedDataPath build \
  "TIO_COMPANION_BUNDLE_ID=$bundle" "${sign_options[@]}" build
