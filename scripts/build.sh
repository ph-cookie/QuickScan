#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${QUICKSCAN_DERIVED_DATA:-build/DerivedData}"
SIGNING=()
if [[ -n "${QUICKSCAN_SIGN_IDENTITY:-}" ]]; then
  SIGNING+=("CODE_SIGN_IDENTITY=$QUICKSCAN_SIGN_IDENTITY")
else
  SIGNING+=("CODE_SIGN_IDENTITY=-")
fi
xcodebuild -project QuickScan.xcodeproj -scheme QuickScan -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${SIGNING[@]}" build
mkdir -p build
if [[ "$DERIVED/Build/Products/Release/QuickScan.app" != "build/QuickScan.app" ]]; then
  ditto "$DERIVED/Build/Products/Release/QuickScan.app" build/QuickScan.app
fi
lipo -info build/QuickScan.app/Contents/MacOS/QuickScan
codesign --verify --strict --verbose=2 build/QuickScan.app
