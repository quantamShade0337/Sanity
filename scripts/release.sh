#!/bin/bash
# Build Sanity-<version>.dmg ready to share.
#
# No Apple Developer account needed. Without a "Developer ID Application"
# certificate the app is ad-hoc signed: it runs on any Mac, but the first
# time someone opens it macOS asks them to allow it in
# System Settings > Privacy & Security (see Documentation/RELEASING.md).
#
# With a Developer ID certificate in your keychain it signs with that
# instead and notarizes, so macOS opens it without asking.
#
# Usage:
#   scripts/release.sh                 # ad-hoc, or Developer ID if you have one
#   ADHOC=1 scripts/release.sh         # force ad-hoc even with a certificate
#   NOTARY_PROFILE=other scripts/release.sh
#   SKIP_NOTARIZE=1 scripts/release.sh # Developer ID signed, not notarized
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Sanity.xcarchive"
EXPORT="$OUT/export"
NOTARY_PROFILE="${NOTARY_PROFILE:-sanity-notary}"

say() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

IDENTITY_LINE=""
if [ "${ADHOC:-0}" != "1" ]; then
    IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
fi

# Info.plist says $(MARKETING_VERSION); the real number is a build setting.
VERSION=$(xcodebuild -project Sanity.xcodeproj -scheme Sanity -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')
[ -n "$VERSION" ] || fail "Couldn't read MARKETING_VERSION from the project."
DMG="$OUT/Sanity-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

make_dmg() {
    local app="$1"
    say "Building $DMG"
    local stage="$OUT/dmg"
    mkdir -p "$stage"
    cp -R "$app" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "Sanity" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
}

if [ -z "$IDENTITY_LINE" ]; then
    say "Archiving Sanity $VERSION (Release, ad-hoc signed)"
    # Hardened runtime is only needed for notarization, and it would refuse
    # to load the ad-hoc signed frameworks inside the app.
    xcodebuild -project Sanity.xcodeproj -scheme Sanity -configuration Release \
        -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
        ENABLE_HARDENED_RUNTIME=NO -quiet archive
    APP="$ARCHIVE/Products/Applications/Sanity.app"
    [ -d "$APP" ] || fail "Archive failed; see the xcodebuild output above."
    # Re-sign the whole bundle so its resources are sealed. A linker-only
    # signature makes a downloaded copy look "damaged" to Gatekeeper.
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    make_dmg "$APP"
    say "Done: $DMG (ad-hoc signed, not notarized)"
    exit 0
fi

TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/' <<<"$IDENTITY_LINE")
say "Signing as team $TEAM_ID"

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

make_dmg "$APP"
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
