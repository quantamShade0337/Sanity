# Releasing Sanity

How to turn this project into a `.dmg` other people can install without macOS
warnings, and what has to change before Sanity can update itself.

## What you need once

1. **A paid Apple Developer Program membership** and a **Developer ID
   Application** certificate. The Apple Development certificates in your
   keychain today only run on your own registered Macs.
2. **A notarization profile** saved in the keychain (use an app-specific
   password from appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials sanity-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

## Making a release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Info.plist`.
2. Add the release notes to `Resources/CHANGELOG.md`.
3. Run:

   ```bash
   scripts/release.sh
   ```

   It archives a Release build, signs it with your Developer ID, builds
   `build/release/Sanity-<version>.dmg`, notarizes and staples it, and checks
   it with Gatekeeper. `SKIP_NOTARIZE=1` skips notarization for a quick local test.

## Turning on self-updates

Self-updates are **off** on purpose (`distributionConfigured = false` in
`Services/Update/UpdateService.swift`). The updater code comes from the app
Sanity is based on, so it still points at that project. Before switching it on:

| What | Where | Change it to |
|---|---|---|
| Release feed | `UpdateService.repository` | your GitHub `owner/repo` |
| Signing team the installer trusts (two places) | `UpdateInstallerSupport.swift`, `DMG_VERIFY_REQ` and `VERIFY_REQ` | your Team ID instead of `3D485NHW29` |
| Showcase media URL | `UpdateShowcaseMedia.swift` | your repo's releases URL |
| Repository link | `AppInfo.repositoryURL` | your repo |
| Switch | `UpdateService.distributionConfigured` | `true` |

Then publish each `Sanity-<version>.dmg` as an asset on a GitHub release
tagged `v<version>`. The updater picks the first `.dmg` asset on the newest
release.

## Now Playing (private API)

The notch's music info uses Apple's private `MediaRemote.framework` through a
helper (`Support/NowPlayingAdapter`). It works for direct downloads, but:

- it can break with a macOS update (in-process reads already stopped working
  in macOS 15.4, which is why it runs in a helper), and
- it would be rejected from the Mac App Store.

For a direct-download release this is an acceptable, known risk. If you ever
want the App Store, the Now Playing parts of the notch need to be switched off
for that build.
