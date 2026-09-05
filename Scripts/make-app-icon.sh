#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "$ROOT_DIR/Sources/WatchApp/Resources/AppIconArtwork.png" "$ROOT_DIR/Assets/AppIcon.png"
