#!/bin/zsh
# Renders the app icon from AppIconView and packs it into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="$(mktemp -d)/AppIcon-1024.png"
swift run NommoSnapshot --icon "$MASTER"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
