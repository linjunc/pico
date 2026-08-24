#!/bin/zsh
set -euo pipefail

: "${RELEASE_TAG:=v1.0.0}"
REPO="${PICO_REPOSITORY:-linjunc/pico}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT/build/release"

for file in \
  "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg" \
  "$RELEASE_DIR/Pico-${RELEASE_TAG}.zip" \
  "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg.sha256"; do
  [[ -f "$file" ]] || { echo "缺少发布文件：$file，请先运行 build-unsigned-dmg.sh" >&2; exit 1; }
done

if command -v gh >/dev/null 2>&1; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "请先执行 gh auth login" >&2
    exit 1
  fi
  if gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$RELEASE_TAG" "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg" \
      "$RELEASE_DIR/Pico-${RELEASE_TAG}.zip" \
      "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg.sha256" --clobber --repo "$REPO"
  else
    gh release create "$RELEASE_TAG" \
      "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg" \
      "$RELEASE_DIR/Pico-${RELEASE_TAG}.zip" \
      "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg.sha256" \
      --repo "$REPO" --title "Pico ${RELEASE_TAG}" \
      --notes "Pico ${RELEASE_TAG} 未签名 macOS 发布版本。首次打开请右键 Pico.app，选择打开。"
  fi
  exit 0
fi

: "${GITHUB_TOKEN:?未安装 gh 时，请设置 GITHUB_TOKEN}"
API="https://api.github.com/repos/${REPO}"
auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")

release_json=$(curl -fsSL "${auth[@]}" "$API/releases/tags/$RELEASE_TAG" 2>/dev/null || true)
if [[ -z "$release_json" ]]; then
  release_json=$(curl -fsSL -X POST "${auth[@]}" "$API/releases" \
    -d "{\"tag_name\":\"${RELEASE_TAG}\",\"name\":\"Pico ${RELEASE_TAG}\",\"body\":\"Pico ${RELEASE_TAG} 未签名 macOS 发布版本。首次打开请右键 Pico.app，选择打开。\",\"draft\":false,\"prerelease\":false}")
fi

upload_url=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"].split("{")[0])' <<< "$release_json")
release_id=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$release_json")
for file in "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg" "$RELEASE_DIR/Pico-${RELEASE_TAG}.zip" "$RELEASE_DIR/Pico-${RELEASE_TAG}.dmg.sha256"; do
  name="$(basename "$file")"
  curl -fsSL -X POST "${auth[@]}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$file" \
    "${upload_url}?name=${name}" >/dev/null
done
echo "Release ${RELEASE_TAG} 已上传（release id ${release_id}）"
