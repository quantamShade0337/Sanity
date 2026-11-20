# Sanity

A menu bar utility for macOS. It tells you at a glance how your Mac is doing,
adds a Dynamic Island to the notch, and gathers everyday tools in one place.

- **Dashboard:** one line on whether your Mac is fine, plus processor,
  memory, battery and storage readings, recent activity, and what is using
  your Mac right now.
- **Dynamic Island:** volume, brightness, charging, AirPods connecting, Keep
  Awake, copies and saved captures appear in the notch. The island only grows
  as wide as what it shows.
- **Tools:** clipboard history, screenshots and screen recording, window
  layout, an app switcher, a command bar, text snippets, cleanup and
  uninstalling, Homebrew, mouse and keyboard tweaks, and more. Each one is
  optional, and Settings explains each page in plain words.
- **13 languages:** English, German, French, Spanish, Italian, Portuguese
  (Brazil), Turkish, Russian, Japanese, Korean, and Simplified and
  Traditional Chinese.

## Requirements

macOS 14 Sonoma or later. The Dynamic Island needs a Mac with a notch.

## Installing

Download `Sanity-<version>.dmg` from
[Releases](https://github.com/quantamShade0337/Sanity/releases) and drag
Sanity to Applications. Sanity isn't notarized by Apple, so the first time
you open it macOS says it can't verify it. Click **Done**, open **System
Settings → Privacy & Security**, and click **Open Anyway** next to Sanity.
You only do this once.

## Building from source

Sanity builds with Xcode 26.

```bash
xcodebuild -project Sanity.xcodeproj -scheme Sanity -destination 'platform=macOS' build
```

To run the tests:

```bash
xcodebuild -project Sanity.xcodeproj -scheme Sanity -destination 'platform=macOS' test
```

Open `Sanity.xcodeproj` directly. Don't regenerate it from `project.yml`,
which is out of date and would drop two Swift packages.

## Permissions

Sanity asks for each permission only when you turn on a feature that needs
it:

- **Accessibility:** volume and brightness in the notch, keyboard shortcuts,
  window layout and the mouse tools.
- **Screen Recording:** screenshots, screen recording and Copy Text from
  Screen.
- **Bluetooth:** battery levels of connected devices and AirPods.
- **Microphone and camera:** only for recordings and the camera preview you
  start.
- **Calendars and Reminders:** only for the notch calendar.

## Privacy

Sanity has no account, analytics or server of its own. It only goes online
for features you use: lyrics (lrclib.net), Homebrew data (formulae.brew.sh),
and the network speed test (speed.cloudflare.com). Automatic updates are
off. New versions come from the Releases page.

Feedback opens a public GitHub issue, so you see everything before it is
sent.

## Credits

Sanity is derived from two GPL-licensed projects:

- [Vorssaint](https://github.com/vorssaintapp/vorssaint-utils), © 2026
  Vorssaint, GPL-3.0-or-later. Sanity is built on this utility app.
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch), © TheBoredTeam
  and contributors, GPL-3.0. The notch and Dynamic Island come from here.

Sanity also uses open-source Swift packages and code that Boring Notch
includes. Settings → Credits lists them all, and
[`Resources/Acknowledgements.txt`](Resources/Acknowledgements.txt) has every
license text in full. Vorssaint's version history is kept in
[`Documentation/VORSSAINT_CHANGELOG.md`](Documentation/VORSSAINT_CHANGELOG.md).

Sanity is an independent project. It is not affiliated with or endorsed by
Vorssaint or Boring Notch.

## License

Sanity is free software under the
[GNU General Public License, version 3 or later](LICENSE). Copyright © 2026
Ethan Soh for Sanity's own changes. Files derived from Vorssaint and Boring
Notch keep their original copyright notices.
