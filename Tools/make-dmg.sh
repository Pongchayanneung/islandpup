#!/bin/bash
# Build a drag-to-Applications disk image from a built IslandPup.app.
#   Tools/make-dmg.sh path/to/IslandPup.app [output.dmg]
set -euo pipefail
APP="${1:?usage: make-dmg.sh path/to/IslandPup.app [output.dmg]}"
OUT="${2:-IslandPup.dmg}"
[ -d "$APP" ] || { echo "not a directory: $APP" >&2; exit 1; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
ditto "$APP" "$ROOT/IslandPup.app"
ln -s /Applications "$ROOT/Applications"

rm -f "$OUT"
hdiutil create -quiet -volname IslandPup -srcfolder "$ROOT" -fs HFS+ -format UDZO -ov "$OUT"
echo "Built $OUT"
shasum -a 256 "$OUT"
