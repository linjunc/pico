#!/bin/zsh
set -euo pipefail

: "${RELEASE_TAG:?Set RELEASE_TAG}"
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY}"

GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$(find "$HOME/Library/Developer/Xcode/DerivedData" -name generate_appcast -type f -perm -111 2>/dev/null | head -1)}"
if [[ -z "$GENERATE_APPCAST" || ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast not found; install Sparkle tools before publishing." >&2
  exit 1
fi

mkdir -p build/update-feed
print -r -- "$SPARKLE_PRIVATE_KEY" > build/update-feed/sparkle-private-key
chmod 600 build/update-feed/sparkle-private-key
"$GENERATE_APPCAST" --ed-key-file build/update-feed/sparkle-private-key \
  --download-url-prefix "https://github.com/linjunc/pico/releases/download/${RELEASE_TAG}/" \
  --output build/update-feed/appcast.xml build/release
rm -f build/update-feed/sparkle-private-key

