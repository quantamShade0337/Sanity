// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import SwiftUI

/// Plain-language help for the Settings window, aimed at someone opening
/// Sanity for the first time: which pages matter most, and one sentence on
/// what each page is for.
enum SettingsPageGuide {
    /// UserDefaults key: false (the default) shows only `corePages` in the
    /// sidebar, true shows every page.
    static let showAllPagesKey = "settingsShowAllPages"
    /// UserDefaults key: set once the Dashboard's getting-started card is dismissed.
    static let gettingStartedDismissedKey = "dashboardGettingStartedDismissed"

    /// The pages a new user is most likely to need. Everything else stays one
    /// click away behind "Show all pages", and is always reachable by search.
    static let corePages: Set<SettingsPage> = [
        .dashboard, .general, .features, .notch, .energy, .monitor,
        .clipboard, .windowLayout, .screenshot, .cleaner, .uninstaller,
        .shortcuts, .about,
    ]

    static func summary(for page: SettingsPage,
                        language: AppLanguage = L10n.shared.language) -> String? {
        summaryKey(for: page).map { GuideText.t($0, language) }
    }

    static func summaryKey(for page: SettingsPage) -> GuideKey? {
        switch page {
        // The Dashboard explains itself; the Notch page draws its own header;
        // About, Release Notes and Support need no introduction.
        case .dashboard, .notch, .about, .releaseNotes, .support: return nil
        case .general: return .sumGeneral
        case .features: return .sumFeatures
        case .energy: return .sumEnergy
        case .monitor: return .sumMonitor
        case .mouse: return .sumMouse
        case .switcher: return .sumSwitcher
        case .windowLayout: return .sumWindowLayout
        case .autoQuit: return .sumAutoQuit
        case .quitProtection: return .sumQuitProtection
        case .clipboard: return .sumClipboard
        case .cutPaste: return .sumCutPaste
        case .shelf: return .sumShelf
        case .media: return .sumMedia
        case .appUpdates: return .sumAppUpdates
        case .cleaner: return .sumCleaner
        case .homebrew: return .sumHomebrew
        case .uninstaller: return .sumUninstaller
        case .killProcess: return .sumKillProcess
        case .commandBar: return .sumCommandBar
        case .quickTools: return .sumQuickTools
        case .screenshot: return .sumScreenshot
        case .urlCleaner: return .sumURLCleaner
        case .keyDebounce: return .sumKeyDebounce
        case .superKey: return .sumSuperKey
        case .textSnippets: return .sumTextSnippets
        case .radialMenu: return .sumRadialMenu
        case .shortcuts: return .sumShortcuts
        case .advanced: return .sumAdvanced
        }
    }
}

/// The title and one-line explanation shown above a Settings page.
struct SettingsPageHeader: View {
    let title: String
    let icon: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.gradient,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Warns at the top of a Settings page when a feature on it is switched on
/// but macOS hasn't granted the permission it needs, with a one-click fix.
struct PagePermissionBanner: View {
    let page: SettingsPage
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var features = FeatureRuntime.shared

    private struct Missing: Identifiable {
        let permission: AppPermission
        let featureNames: [String]
        var id: AppPermission { permission }
    }

    private var missing: [Missing] {
        let pageFeatures = Set(FeatureVisibilitySupport.features(for: page))
        guard !pageFeatures.isEmpty else { return [] }
        let defaults = UserDefaults.standard
        let hub = FeatureStrings.hub(l10n.language)
        var result: [Missing] = []
        for (permission, granted) in [(AppPermission.accessibility, permissions.accessibility),
                                      (.screenRecording, permissions.screenRecording)] where !granted {
            let using = AppFeature.activeFeatures(
                using: permission,
                isAvailable: { features.isAvailable($0) },
                boolFor: { defaults.bool(forKey: $0) },
                stringFor: { defaults.string(forKey: $0) },
                dataFor: { defaults.data(forKey: $0) })
                .filter { pageFeatures.contains($0) }
            if !using.isEmpty {
                result.append(Missing(permission: permission,
                                      featureNames: using.map { $0.hubTitle(l10n.s, hub: hub) }))
            }
        }
        return result
    }

    var body: some View {
        let items = missing
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(GuideText.f(item.permission == .accessibility ? .needsAccessibility : .needsScreenRecording,
                                         ListFormatter.localizedString(byJoining: item.featureNames),
                                         language: l10n.language))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button(GuideText.t(.openSystemSettings, l10n.language)) {
                            if item.permission == .accessibility {
                                permissions.requestAccessibility()
                            } else {
                                permissions.requestScreenRecording()
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }
}
