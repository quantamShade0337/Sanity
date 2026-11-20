#!/bin/bash
# Build a signed, notarized Sanity.dmg ready to share.
#
# Needs (see Documentation/RELEASING.md):
#   - a "Developer ID Application" certificate in your keychain
#   - a notarytool keychain profile:  xcrun notarytool store-credentials sanity-notary ...
#
# Usage:
#   scripts/release.sh                 # uses the notary profile "sanity-notary"
#   NOTARY_PROFILE=other scripts/release.sh
#   SKIP_NOTARIZE=1 scripts/release.sh # signed but not notarized, for a quick local test
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Sanity.xcarchive"
EXPORT="$OUT/export"
NOTARY_PROFILE="${NOTARY_PROFILE:-sanity-notary}"

say() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
[ -n "$IDENTITY_LINE" ] || fail "No \"Developer ID Application\" certificate found.
  Apple Development certificates can only run on your own Macs.
  Create one at https://developer.apple.com/account/resources/certificates (paid Apple Developer Program)."
TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/' <<<"$IDENTITY_LINE")
say "Signing as team $TEAM_ID"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sources/Info.plist)
DMG="$OUT/Sanity-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

say "Archiving Sanity $VERSION (Release)"
xcodebuild -project Sanity.xcodeproj -scheme Sanity -configuration Release \
    -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -quiet archive
[ -d "$ARCHIVE/Products/Applications/Sanity.app" ] || fail "Archive failed; see the xcodebuild output above."

say "Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist"
APP="$EXPORT/Sanity.app"
codesign --verify --deep --strict "$APP"

say "Building $DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sanity" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    say "Skipping notarization. $DMG is signed but macOS will warn other people who open it."
    exit 0
fi

say "Notarizing (this usually takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "Notarization failed. See: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

say "Done: $DMG"
