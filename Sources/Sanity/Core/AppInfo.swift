// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Static identity of the app, shared by UI, notifications and tooling.
enum AppInfo {
    static let name = "Sanity"
    static let copyright = "© 2026 Ethan Soh · GPL-3.0-or-later"
    static let repositoryURL = URL(string: "https://github.com/quantamShade0337/Sanity")!
    static let websiteURL = repositoryURL
    /// Where people report problems and request features.
    static let issuesURL = repositoryURL.appendingPathComponent("issues/new")
    /// The server that hosts expiring share links for screenshots and
    /// recordings. Sanity has none yet, so link sharing stays hidden; the
    /// code inherited from Vorssaint uploaded to Vorssaint's own server.
    static let shareLinkServiceURL: URL? = nil
    static var linkSharingAvailable: Bool { shareLinkServiceURL != nil }

    /// The bundle version. The fallback only applies to the bare binary
    /// (e.g. `--selftest`), never the shipped app, which reads its Info.plist.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// True for the local "Sanity (Developer)" build (bundle id ends in `.dev`).
    /// It is never published and never auto-updates; all work is tested here first.
    static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    /// True when the current version is a pre-release (e.g. 3.3.4-beta.1 or 3.3.4-rc.1).
    static var isBeta: Bool {
        if isDeveloperBuild && UserDefaults.standard.bool(forKey: DefaultsKey.simulateBetaUI) {
            return true
        }
        let v = version.lowercased()
        return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
    }

    /// The git commit a Developer build was compiled from, e.g. "ed2ebba · 2026-06-15 21:30"
    /// (or with a "-dirty" suffix on the SHA for uncommitted changes). build.sh stamps
    /// this into the Developer bundle only, so you can confirm at a glance that the
    /// running dev app matches the source you are about to change. nil in the official app.
    static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "SanityBuildCommit") as? String
    }
}
