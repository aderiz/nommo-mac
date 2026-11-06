#!/bin/zsh
# Builds a notarised release DMG using Xcode's signed-in Apple account: no app-specific password needed.
#
# This is the route for a *cloud-managed* Developer ID certificate, which Xcode holds on Apple's servers and which
# `codesign` cannot use directly. (scripts/release.sh is the alternative for a Developer ID certificate that lives in
# your keychain, using notarytool.)
#
# One-time setup:
#   - Xcode signed in to the Apple ID with a paid developer membership (Settings > Accounts).
#   - The latest Apple Developer Program License Agreement accepted at developer.apple.com/account
#     (and any agreements pending in App Store Connect). Apple refuses to issue certificates or accept
#     submissions until they are accepted.
#
# What it does: builds the app, wraps it in a minimal .xcarchive, has Xcode re-sign it with Developer ID (creating
# the certificate the first time), uploads it to Apple's notary service, waits for approval, collects the app with
# the notarisation ticket stapled to it, and packs that into Releases/Nommo-<version>.dmg.
#
# Usage: ./scripts/release_via_xcode.sh        (override the team with NOMMO_TEAM_ID)
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Nommo.app/Contents/Info.plist)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' dist/Nommo.app/Contents/Info.plist)"
TEAM="${NOMMO_TEAM_ID:-$(codesign -dv dist/Nommo.app 2>&1 | awk -F= '/TeamIdentifier/ {print $2}')}"
[[ -n "$TEAM" && "$TEAM" != "notset" ]] || { echo "Could not work out the team ID; set NOMMO_TEAM_ID." >&2; exit 1; }
echo "Releasing Nommo $VERSION as team $TEAM"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ARCHIVE="$WORK/Nommo.xcarchive"
mkdir -p "$ARCHIVE/Products/Applications"
ditto dist/Nommo.app "$ARCHIVE/Products/Applications/Nommo.app"

cat > "$ARCHIVE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>Name</key><string>Nommo</string>
  <key>SchemeName</key><string>Nommo</string>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/Nommo.app</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>Team</key><string>$TEAM</string>
  </dict>
</dict></plist>
PLIST

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
PLIST

echo "Signing with Developer ID and uploading to Apple's notary service..."
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/upload" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates 2>&1 | grep -E "error|Uploaded|SUCCEEDED|FAILED" || true

echo "Waiting for Apple to finish checking it (usually a few minutes)..."
for attempt in {1..60}; do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$WORK/notarised" >/dev/null 2>&1 \
     && [[ -d "$WORK/notarised/Nommo.app" ]]; then
    break
  fi
  sleep 30
done
[[ -d "$WORK/notarised/Nommo.app" ]] || { echo "Notarisation did not complete. Check the Organizer in Xcode for Apple's log." >&2; exit 1; }

# The stapled, notarised app replaces the development build.
rm -rf dist/Nommo.app
ditto "$WORK/notarised/Nommo.app" dist/Nommo.app
xcrun stapler validate dist/Nommo.app
spctl --assess --type execute --verbose=2 dist/Nommo.app

NOMMO_SKIP_BUILD=1 ./scripts/make_dmg.sh

# Check the app the way a user will meet it: inside the DMG.
MOUNT="$(mktemp -d)"
hdiutil attach "Releases/Nommo-${VERSION}.dmg" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
spctl --assess --type execute --verbose=2 "$MOUNT/Nommo.app"
hdiutil detach "$MOUNT" >/dev/null
echo
echo "Release ready: Releases/Nommo-${VERSION}.dmg"
