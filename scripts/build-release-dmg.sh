#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
: "${RELEASE_TAG:?Set RELEASE_TAG, for example v1.0.0}"
: "${SIGNING_IDENTITY:?Set Developer ID Application signing identity}"
: "${APPLE_TEAM_ID:?Set Apple Developer Team ID}"

xcodegen generate
rm -rf build/Pico.xcarchive build/release
mkdir -p build/release
xcodebuild archive -project Pico.xcodeproj -scheme Pico -configuration Release \
  -archivePath build/Pico.xcarchive \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES

APP_PATH="build/Pico.xcarchive/Products/Applications/Pico.app"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "build/release/Pico-${RELEASE_TAG}.zip"
hdiutil create -volname "Pico ${RELEASE_TAG}" -srcfolder "$APP_PATH" -ov -format UDZO "build/release/Pico-${RELEASE_TAG}.dmg"
shasum -a 256 build/release/Pico-${RELEASE_TAG}.dmg > build/release/Pico-${RELEASE_TAG}.dmg.sha256

