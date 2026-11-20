// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import SwiftUI

/// Plain-language help for the Settings window, aimed at someone opening
/// Sanity for the first time: which pages matter most, and one sentence on
/// what each page is for.
enum SettingsPageGuide {
    /// UserDefaults key: set once the Dashboard's getting-started card is dismissed.
    static let gettingStartedDismissedKey = "dashboardGettingStartedDismissed"

    static func summary(for page: SettingsPage,
                        language: AppLanguage = L10n.shared.language) -> String? {
        summaryKey(for: page).map { GuideText.t($0, language) }
    }

    static func summaryKey(for page: SettingsPage) -> GuideKey? {
        switch page {
        // The Dashboard explains itself; the Notch page draws its own header;
        // About, Release Notes and Support need no introduction.
        case .dashboard, .notch, .about, .releaseNotes, .credits: return nil
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

/// Metrics of macOS grouped forms, so text placed above a page's `Form`
/// lines up with the form's rows instead of floating at its own margin.
enum GroupedFormMetrics {
    /// Horizontal margin between the detail pane and the form's sections.
    static let outerMargin: CGFloat = 20
    /// Widest a grouped form's sections grow before they centre.
    static let maxWidth: CGFloat = 704
    /// Leading inset of row content inside a section.
    static let rowInset: CGFloat = 10
}

/// One plain sentence above a Settings page, aligned with the form's rows.
/// The page title lives in the window title bar, so there is no heading,
/// no icon tile and nothing that competes with the form itself.
struct SettingsPageIntro: View {
    let summary: String

    var body: some View {
        Text(summary)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroupedFormMetrics.rowInset)
            .frame(maxWidth: GroupedFormMetrics.maxWidth, alignment: .leading)
            .padding(.horizontal, GroupedFormMetrics.outerMargin)
            .padding(.top, 18)
            .frame(maxWidth: .infinity)
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
                    .padding(.horizontal, GroupedFormMetrics.rowInset)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: GroupedFormMetrics.maxWidth, alignment: .leading)
            .padding(.horizontal, GroupedFormMetrics.outerMargin)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
        }
    }
}
