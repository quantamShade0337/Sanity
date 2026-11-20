// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI

/// Who Sanity is built on, under which license, and where their source is.
/// The full license texts ship in the app as Acknowledgements.txt, which
/// GPL and the BSD/MIT/Apache licenses below require for binary copies.
struct CreditsSettings: View {
    @ObservedObject private var l10n = L10n.shared

    private func t(_ key: GuideKey) -> String { GuideText.t(key, l10n.language) }

    struct Credit: Identifiable {
        let name: String
        let detail: String
        let url: String
        var id: String { name }
    }

    static let upstream: [Credit] = [
        Credit(name: "Vorssaint", detail: "© 2026 Vorssaint · GPL-3.0-or-later",
               url: "https://github.com/vorssaintapp/vorssaint-utils"),
        Credit(name: "Boring Notch", detail: "© TheBoredTeam and contributors · GPL-3.0",
               url: "https://github.com/TheBoredTeam/boring.notch"),
    ]

    static let viaBoringNotch: [Credit] = [
        Credit(name: "MediaRemoteAdapter", detail: "© 2025 Jonas van den Berg and contributors · BSD-3-Clause",
               url: "https://github.com/ungive/mediaremote-adapter"),
        Credit(name: "Calendr", detail: "© 2021 Carlos César Neves Enumo · MIT",
               url: "https://github.com/pakerwreah/Calendr"),
        Credit(name: "DynamicNotchKit", detail: "© 2025 Kai Azim · MIT",
               url: "https://github.com/MrKai77/DynamicNotchKit"),
        Credit(name: "NotchDrop", detail: "© 2024 Lakr Aream · MIT",
               url: "https://github.com/Lakr233/NotchDrop"),
        Credit(name: "Parrot", detail: "© 2018 Aditya Vaidyam and contributors · MPL-2.0",
               url: "https://github.com/avaidyam/Parrot"),
    ]

    static let libraries: [Credit] = [
        Credit(name: "AsyncXPCConnection", detail: "© 2023 Chime · BSD-3-Clause",
               url: "https://github.com/ChimeHQ/AsyncXPCConnection"),
        Credit(name: "Defaults", detail: "© Sindre Sorhus · MIT",
               url: "https://github.com/sindresorhus/Defaults"),
        Credit(name: "KeyboardShortcuts", detail: "© Sindre Sorhus · MIT",
               url: "https://github.com/sindresorhus/KeyboardShortcuts"),
        Credit(name: "LaunchAtLogin", detail: "© Sindre Sorhus · MIT",
               url: "https://github.com/sindresorhus/LaunchAtLogin-Modern"),
        Credit(name: "Lottie", detail: "© Airbnb · Apache-2.0",
               url: "https://github.com/airbnb/lottie-spm"),
        Credit(name: "MacroVisionKit", detail: "© 2024 theboringhumane · MIT",
               url: "https://github.com/TheBoredTeam/MacroVisionKit"),
        Credit(name: "SkyLightWindow", detail: "© 2025 Lakr Aream · MIT",
               url: "https://github.com/Lakr233/SkyLightWindow"),
        Credit(name: "Sparkle", detail: "© Andy Matuschak and the Sparkle Project · MIT",
               url: "https://github.com/sparkle-project/Sparkle"),
        Credit(name: "SwiftUI Introspect", detail: "© 2019 Timber Software · MIT",
               url: "https://github.com/siteline/swiftui-introspect"),
    ]

    static var licensesURL: URL? {
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
    }

    var body: some View {
        Form {
            Section {
                Text(t(.creditsIntro))
                    .font(SanityDesign.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Link(destination: AppInfo.repositoryURL) {
                        Label(t(.creditsSourceCode), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.bordered)
                    if let licenses = Self.licensesURL {
                        Button {
                            NSWorkspace.shared.open(licenses)
                        } label: {
                            Label(t(.creditsViewLicenses), systemImage: "doc.text")
                        }
                    }
                }
            }

            Section(t(.creditsBuiltOn)) {
                creditRow(Self.upstream[0], role: t(.creditsVorssaintRole))
                creditRow(Self.upstream[1], role: t(.creditsBoringNotchRole))
            }

            Section(t(.creditsIncluded)) {
                ForEach(Self.viaBoringNotch) { creditRow($0) }
            }

            Section {
                ForEach(Self.libraries) { creditRow($0) }
            } header: {
                Text(t(.creditsLibraries))
            } footer: {
                Text(t(.creditsNotAffiliated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func creditRow(_ credit: Credit, role: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credit.name)
                if let role {
                    Text(role)
                        .font(SanityDesign.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                Text(credit.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let url = URL(string: credit.url) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .accessibilityLabel(credit.name)
                }
                .buttonStyle(.borderless)
                .help(credit.url)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
