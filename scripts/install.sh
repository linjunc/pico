#!/bin/sh
set -eu

REPO="${PICO_REPOSITORY:-linjunc/pico}"
INSTALL_DIR="${PICO_INSTALL_DIR:-/Applications}"
API="https://api.github.com/repos/${REPO}/releases/latest"

command -v curl >/dev/null 2>&1 || { echo "需要 curl" >&2; exit 1; }
command -v hdiutil >/dev/null 2>&1 || { echo "需要 macOS hdiutil" >&2; exit 1; }

DMG_URL=$(curl -fsSL "$API" | awk -F'"' '/browser_download_url/ && /\.dmg"/ { print $4; exit }')
[ -n "$DMG_URL" ] || { echo "找不到最新 Pico DMG，请检查 GitHub Release" >&2; exit 1; }

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pico-install.XXXXXX")
MOUNT_DIR="$TMP_DIR/mount"
mkdir -p "$MOUNT_DIR"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

curl -fL --progress-bar "$DMG_URL" -o "$TMP_DIR/Pico.dmg"
hdiutil attach "$TMP_DIR/Pico.dmg" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null

APP_PATH="$MOUNT_DIR/Pico.app"
[ -d "$APP_PATH" ] || { echo "DMG 中没有 Pico.app" >&2; exit 1; }
mkdir -p "$INSTALL_DIR"
ditto "$APP_PATH" "$INSTALL_DIR/Pico.app"
echo "Pico 已安装到 $INSTALL_DIR/Pico.app"
