#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

RAW_VERSION="${1:-${APP_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}}"
VERSION="${RAW_VERSION#v}"

APP_VERSION="$VERSION" ./scripts/build.sh

APP_PATH="dist/SnipX.app"
DMG_NAME="SnipX-${VERSION}.dmg"
DMG_PATH="dist/${DMG_NAME}"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

ditto "$APP_PATH" "$STAGE_DIR/SnipX.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH" "${DMG_PATH}.sha256"
hdiutil create \
  -volname "SnipX" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

(cd dist && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")
echo "Built DMG: $PWD/$DMG_PATH"
