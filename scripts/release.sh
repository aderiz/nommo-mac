#!/bin/zsh
# Builds, notarises and staples a release DMG: Releases/Nommo-<version>.dmg
#
# One-time setup (needs a paid Apple Developer account):
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. Notary credentials stored in the keychain, using an app-specific password
#      from https://account.apple.com (Sign-In and Security > App-Specific Passwords):
#        xcrun notarytool store-credentials nommo-notary \
#          --apple-id YOU@EXAMPLE.COM --team-id YOURTEAMID --password xxxx-xxxx-xxxx-xxxx
#
# Then: ./scripts/release.sh        (set NOMMO_NOTARY_PROFILE to use a different profile name)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOMMO_NOTARY_PROFILE:-nommo-notary}"
IDENTITY="${NOMMO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"

if [[ -z "$IDENTITY" ]]; then
  echo "No 'Developer ID Application' certificate found in your keychain." >&2
  echo "Create one in Xcode (Settings > Accounts > Manage Certificates) and run this again." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No stored notary credentials named '$PROFILE'. Store them once with:" >&2
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id YOU@EXAMPLE.COM --team-id YOURTEAMID --password <app-specific-password>" >&2
  exit 1
fi
export NOMMO_SIGN_IDENTITY="$IDENTITY"
echo "Signing as: $IDENTITY"

# Submits a file to Apple and waits. On failure, prints Apple's log of what was wrong.
notarise() {
  local file="$1" result id status
  echo "Submitting $file to Apple (this usually takes a few minutes)..."
  result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json)"
  id="$(print -r -- "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
  status="$(print -r -- "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  echo "  submission $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    echo "Notarisation failed." >&2
    exit 1
  fi
}

# 1. Build and sign the app (hardened runtime and a secure timestamp), notarise it, and staple the ticket.
./scripts/build_app.sh
ditto -c -k --keepParent dist/Nommo.app dist/Nommo-notarise.zip
notarise dist/Nommo-notarise.zip
rm -f dist/Nommo-notarise.zip
xcrun stapler staple dist/Nommo.app

# 2. Pack the stapled app into a DMG, sign it, notarise it, and staple that too.
NOMMO_SKIP_BUILD=1 ./scripts/make_dmg.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Nommo.app/Contents/Info.plist)"
DMG="Releases/Nommo-${VERSION}.dmg"
notarise "$DMG"
xcrun stapler staple "$DMG"

# 3. Stapling changed the file, so the checksum has to be taken last.
( cd Releases && shasum -a 256 "Nommo-${VERSION}.dmg" > "Nommo-${VERSION}.dmg.sha256" )

# 4. Check it the way Gatekeeper will.
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo
echo "Release ready: $DMG"
cat "Releases/Nommo-${VERSION}.dmg.sha256"
