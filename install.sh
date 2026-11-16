#!/bin/bash
# IslandPup installer. Downloads the release zip with curl (curl sets no quarantine flag,
# so macOS Gatekeeper does not block the ad-hoc signed app), checks its sha256, installs it
# and opens it. No sudo. Your settings and character packs are never touched.
#   bash install.sh            install or update
#   bash install.sh --uninstall   remove the app only
set -euo pipefail

VERSION="0.1.0"
SHA256="e45f4bd58bc33ae584f07a4e4cd215bc88b50ae655c8ae4f05d992c01c29553a"
URL="https://github.com/Pongchayanneung/islandpup/releases/download/v${VERSION}/IslandPup.zip"
APP="IslandPup.app"

if [ -n "${ISLANDPUP_DEST:-}" ]; then DEST="$ISLANDPUP_DEST"   # for testing
elif [ -w /Applications ]; then DEST="/Applications"
else DEST="$HOME/Applications"; fi
mkdir -p "$DEST"

if [ "${1:-}" = "--uninstall" ]; then
  osascript -e 'tell application "IslandPup" to quit' >/dev/null 2>&1 || true
  rm -rf "${DEST:?}/$APP"
  echo "Removed $DEST/$APP (settings in ~/Library/Application Support/IslandPup were kept)."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || { echo "IslandPup is macOS only." >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "IslandPup needs a Mac with Apple Silicon." >&2; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "IslandPup needs macOS 14 or newer." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading IslandPup $VERSION ..."
curl -fL --progress-bar -o "$TMP/IslandPup.zip" "$URL"

GOT="$(shasum -a 256 "$TMP/IslandPup.zip" | cut -d' ' -f1)"
if [ "$GOT" != "$SHA256" ]; then
  echo "Checksum mismatch, not installing." >&2
  echo "  expected $SHA256" >&2
  echo "  got      $GOT" >&2
  exit 1
fi

ditto -x -k "$TMP/IslandPup.zip" "$TMP/out"
[ -d "$TMP/out/$APP" ] || { echo "IslandPup.app not found in the zip." >&2; exit 1; }

osascript -e 'tell application "IslandPup" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "${DEST:?}/$APP"
ditto "$TMP/out/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "Installed to $DEST/$APP"
open "$DEST/$APP"
