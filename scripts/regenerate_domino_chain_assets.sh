#!/usr/bin/env bash
# Regenerate Web + Android raster icons from extracted logo mark (see BRAND_DOMINO_CHAIN.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/backend/app/assets/images/domino-chain-mark-extracted.png}"
if [[ ! -f "$SRC" ]]; then
  echo "Missing extracted mark: $SRC" >&2
  echo "Run: python3 scripts/extract_domino_chain_mark.py --input <full-sheet.png> --output backend/app/assets/images/domino-chain-mark-extracted.png" >&2
  exit 1
fi

PUBLIC="$ROOT/backend/public"
ASSETS="$ROOT/backend/app/assets/images"
BG="#0a0a0b"

magick "$SRC" -resize '920x920>' -gravity center -background "$BG" -extent 1024x1024 "$ASSETS/domino-chain-logo.png"

magick "$SRC" -resize '460x460>' -gravity center -background "$BG" -extent 512x512 "$PUBLIC/icon.png"
magick "$SRC" -resize '170x170>' -gravity center -background "$BG" -extent 192x192 "$PUBLIC/icon-192.png"
magick "$SRC" -resize '410x410>' -gravity center -background "$BG" -extent 512x512 "$PUBLIC/icon-maskable.png"

magick "$PUBLIC/icon.png" -define icon:auto-resize=16,32,48 "$PUBLIC/favicon.ico"

magick "$SRC" -resize '340x340>' -gravity center -background none -extent 432x432 \
  "$ROOT/android/app/src/main/res/drawable-nodpi/ic_launcher_foreground_art.png"

echo "Done. Source mark: $SRC"
