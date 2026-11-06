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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>NSAudioCaptureUsageDescription</key><string>Nommo captures system audio so it can apply the spatial effect before playing it on your speaker.</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with a real certificate when one is available. An ad-hoc signature changes with every build, so macOS
# treats each build as a new app and asks for the System Audio Recording permission again. A certificate-based
# signature keeps the same identity across builds, so the permission sticks.
# Override with NOMMO_SIGN_IDENTITY="<name or hash>".
IDENTITY="${NOMMO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier ai.amplified.nommo "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - --identifier ai.amplified.nommo "$APP"
  echo "Signed ad hoc (permissions will be requested again after each rebuild)"
fi
echo "Built $APP"
