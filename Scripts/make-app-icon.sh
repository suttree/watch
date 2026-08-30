#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Assets/noun-candle-4420273.png"
OUTPUT="$ROOT_DIR/Assets/AppIcon.png"
WORK_DIR="$ROOT_DIR/.build/app-icon"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Match the default theme's lightened midpoint pastel. Runtime-themed icons
# derive the same kind of background from the selected theme.
magick -size 1200x1200 xc:'#d2d3d7' "$WORK_DIR/base.png"

# Reuse the app's quiet two-dot paper motif at a larger, icon-friendly scale.
magick -size 16x16 xc:none -fill '#7d858f' \
  -draw 'circle 4,4 5.5,4 circle 12,12 13.5,12' \
  "$WORK_DIR/dot-tile.png"
magick -size 1200x1200 tile:"$WORK_DIR/dot-tile.png" \
  -channel A -evaluate multiply 0.18 +channel "$WORK_DIR/dots.png"

magick "$SOURCE" -alpha extract "$WORK_DIR/mask.png"

magick -size 1200x1200 xc:'#26313a' "$WORK_DIR/mask.png" \
  -compose CopyOpacity -composite "$WORK_DIR/logo.png"

magick "$WORK_DIR/base.png" "$WORK_DIR/dots.png" -compose over -composite \
  -stroke '#ffffff' -strokewidth 20 -fill none \
  -draw 'roundrectangle 160,160 1040,1040 160,160' \
  "$WORK_DIR/logo.png" -compose over -composite \
  -strip "$OUTPUT"
