#!/bin/zsh
# Builds a release NommoApp.app (menu-bar only) into ./dist and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

# A universal binary (Apple silicon and Intel). Only Apple silicon has been tested.
swift build -c release --arch arm64 --arch x86_64 --product NommoApp
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NommoApp"

APP="dist/Nommo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nommo"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nommo</string>
  <key>CFBundleDisplayName</key><string>Nommo</string>
  <key>CFBundleIdentifier</key><string>ai.amplified.nommo</string>
  <key>CFBundleExecutable</key><string>Nommo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.3</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>NSAudioCaptureUsageDescription</key><string>Nommo captures system audio so it can apply the spatial effect before playing it on your speaker.</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Signing. Preference order: NOMMO_SIGN_IDENTITY, a Developer ID Application certificate, an Apple Development
# certificate, then ad hoc.
#
# - Developer ID is what is needed to notarise a release (see scripts/release.sh).
# - A real certificate of any kind keeps the app's identity the same across builds, so macOS remembers the
#   System Audio Recording permission. An ad-hoc signature changes every build and the permission is asked for again.
# - The hardened runtime is always on, so development builds behave like release builds.
find_identity() {
  security find-identity -v -p codesigning | awk -F'"' -v pattern="$1" '$0 ~ pattern {print $2; exit}'
}
IDENTITY="${NOMMO_SIGN_IDENTITY:-$(find_identity 'Developer ID Application')}"
IDENTITY="${IDENTITY:-$(find_identity 'Apple Development')}"
if [[ -n "$IDENTITY" ]]; then
  FLAGS=(--force --options runtime --identifier ai.amplified.nommo --sign "$IDENTITY")
  # Notarisation requires a secure timestamp, which only Developer ID signing uses.
  [[ "$IDENTITY" == "Developer ID Application"* ]] && FLAGS+=(--timestamp)
  codesign "${FLAGS[@]}" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --options runtime --sign - --identifier ai.amplified.nommo "$APP"
  echo "Signed ad hoc (permissions will be requested again after each rebuild)"
fi
echo "Built $APP"
