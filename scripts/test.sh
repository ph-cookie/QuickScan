#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project QuickScan.xcodeproj -scheme QuickScan -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "${QUICKSCAN_DERIVED_DATA:-build/DerivedData}" \
  CODE_SIGN_IDENTITY=- test
