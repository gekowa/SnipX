#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --scratch-path .build
APP="dist/SnipX.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SnipX "$APP/Contents/MacOS/SnipX"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "$APP/Contents/Info.plist"
fi
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP"
echo "Built: $PWD/$APP"
