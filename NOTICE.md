# Sanity attribution

Sanity is an independent macOS application, copyright © 2026 Ethan Soh for
its own changes and additions, distributed under the GNU General Public
License version 3 or later. See `LICENSE` for the complete license text.

## Upstream projects

- **Vorssaint**: https://github.com/vorssaintapp/vorssaint-utils
  Copyright © 2026 Vorssaint. GPL-3.0-or-later. Sanity is derived from this
  utility app. Source files that came from Vorssaint keep their
  `Copyright (C) 2026 Vorssaint` headers. Per Vorssaint's TRADEMARKS.md, the
  GPL doesn't cover the Vorssaint name, logo, icon or bundle identity. Sanity
  uses its own name, icon, bundle identifier (`com.ethansoh.Sanity`) and
  release feed. It doesn't use Vorssaint's update feed, share-link server or
  feedback server.
- **Boring Notch**: https://github.com/TheBoredTeam/boring.notch
  Copyright © TheBoredTeam and the Boring Notch contributors. GPL-3.0. Sanity's
  notch and Dynamic Island are derived from it, and its source files keep
  their original headers.

## Third-party code and packages

Boring Notch includes code under the BSD 3-Clause, MIT and Mozilla Public
License 2.0 licenses (MediaRemoteAdapter, Calendr, DynamicNotchKit, NotchDrop,
Parrot). Sanity also links these Swift packages: AsyncXPCConnection, Defaults,
KeyboardShortcuts, LaunchAtLogin-Modern, Lottie, MacroVisionKit,
SkyLightWindow, Sparkle and SwiftUI Introspect.

Each one's copyright notice and full license text is in
`Resources/Acknowledgements.txt`. That file ships inside the app and opens
from Settings → Credits.

Sanity is not affiliated with or endorsed by Vorssaint or Boring Notch.
