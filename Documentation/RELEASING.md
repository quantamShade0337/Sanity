# Releasing Sanity

How to turn this project into a `.dmg` other people can install. No Apple
Developer account is needed.

## Making a release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Sanity target's
   build settings (both Debug and Release).
2. Add the release notes to `Resources/CHANGELOG.md`.
3. Run:

   ```bash
   scripts/release.sh
   ```

   It archives a Release build, ad-hoc signs the whole app and writes
   `build/release/Sanity-<version>.dmg`.
4. Publish the `.dmg` as an asset on a GitHub release tagged `v<version>`.

## What people see the first time

The app isn't notarized by Apple, so the first time someone opens it macOS
says it can't verify the developer. Put this in each release's notes:

> Open the `.dmg` and drag Sanity to Applications. Open Sanity. When macOS
> says it can't verify it, click **Done**, then open **System Settings →
> Privacy & Security**, scroll down and click **Open Anyway** next to Sanity.
> You only do this once.

macOS ties Accessibility and Screen Recording permissions to the app's
signature, and an ad-hoc signature changes with every build. After
installing a new version, people may need to turn Sanity off and on again in
those permission lists.

## What needs a Developer ID

Everything works without one except:

- **Fan Control** stays unavailable. Its helper runs as root and only talks to
  an app signed by one Developer team, so it needs `FanControlIdentifiers.teamID`
  (`Services/FanControl/FanControlXPC.swift`) set to your Team ID and a
  Developer ID release.
- **Opening without a warning.** That needs notarization.

If you join the Apple Developer Program later, create a **Developer ID
Application** certificate and a notarization profile:

```bash
xcrun notarytool store-credentials sanity-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

`scripts/release.sh` then finds the certificate, signs with it and notarizes
on its own. `ADHOC=1` forces an ad-hoc build anyway.

## Turning on self-updates

Self-updates are **off** on purpose (`distributionConfigured = false` in
`Services/Update/UpdateService.swift`). The installer only accepts updates
signed by one Developer team, so self-updates also need a Developer ID.
The release feed (`UpdateService.repository`) already points at
`quantamShade0337/Sanity`. Before switching it on:

| What | Where | Change it to |
|---|---|---|
| Signing team the installer trusts (two places) | `UpdateInstallerSupport.swift`, `DMG_VERIFY_REQ` and `VERIFY_REQ` | your Team ID instead of Vorssaint's `3D485NHW29` |
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
