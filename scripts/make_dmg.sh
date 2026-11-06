#!/bin/zsh
# Builds Nommo.app and packs it into Releases/Nommo-<version>.dmg, with a checksum.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Nommo.app/Contents/Info.plist)"
DMG="Releases/Nommo-${VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto dist/Nommo.app "$STAGE/Nommo.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p Releases
rm -f "$DMG"
hdiutil create -volname "Nommo" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

( cd Releases && shasum -a 256 "Nommo-${VERSION}.dmg" > "Nommo-${VERSION}.dmg.sha256" )
echo "Built $DMG"
cat "Releases/Nommo-${VERSION}.dmg.sha256"
