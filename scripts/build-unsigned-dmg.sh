#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
RELEASE_TAG="${RELEASE_TAG:-v1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

xcodegen generate
mkdir -p build/release

xcodebuild archive \
  -project Pico.xcodeproj \
  -scheme Pico \
  -configuration Release \
  -archivePath "build/Pico-${RELEASE_TAG}.xcarchive" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="build/Pico-${RELEASE_TAG}.xcarchive/Products/Applications/Pico.app"
ZIP_PATH="build/release/Pico-${RELEASE_TAG}.zip"
DMG_PATH="build/release/Pico-${RELEASE_TAG}.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
  -volname "Pico ${RELEASE_TAG}" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"

echo "Unsigned release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  ${DMG_PATH}.sha256"
