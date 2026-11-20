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

    static func summary(for page: SettingsPage) -> String? {
        switch page {
        case .dashboard: return nil
        case .general: return "Basic options: start Sanity when you log in, change the language and appearance, and choose what the menu bar icon shows."
        case .features: return "Turn whole features on or off. Anything you switch off here disappears from Sanity completely, so start small and add more later."
        // The Notch page draws its own header with a section picker.
        case .notch: return nil
        case .energy: return "Keep your Mac awake, change screen brightness, and control what happens to Bluetooth when your Mac sleeps."
        case .monitor: return "Choose which live stats (CPU, memory, temperature and more) appear in the menu bar, and how often they update."
        case .mouse: return "Change how your mouse and trackpad behave: scroll direction, smooth scrolling, extra buttons and middle click."
        case .switcher: return "A better app and window switcher, plus options for what clicking an app in the Dock does."
        case .windowLayout: return "Snap windows to halves, thirds or corners of the screen with a shortcut or by dragging them to an edge."
        case .autoQuit: return "Automatically quit apps you haven't used for a while, so they stop using memory and battery."
        case .quitProtection: return "Stops ⌘Q and ⌘W from quitting apps or closing windows by accident: you can make them need a hold or a double press."
        case .clipboard: return "Remembers what you copy so you can paste something from earlier. Your history stays on this Mac."
        case .cutPaste: return "Adds real cut and paste for files in Finder, and quicker ways to rename files."
        case .shelf: return "A temporary spot to drop files while you move them between windows or apps."
        case .media: return "Convert, resize and crop images and PDFs, add watermarks, and rename files in bulk."
        case .appUpdates: return "Checks the apps you have installed and tells you when updates are available."
        case .cleaner: return "Finds caches, logs and leftover files you can safely remove to free up disk space."
        case .homebrew: return "Manage Homebrew packages without the Terminal. Only useful if you already use Homebrew."
        case .uninstaller: return "Removes an app together with the settings and support files it leaves behind."
        case .killProcess: return "Force-quit apps or background processes that have stopped responding."
        case .commandBar: return "A search bar you open with a shortcut to launch apps, run Sanity's tools, and jump to settings."
        case .quickTools: return "Small tools you can open from anywhere: a quick launcher, toggles, microphone mute, a camera preview and a scratchpad."
        case .screenshot: return "Take screenshots and screen recordings, pick colors, and copy text from anything on screen."
        case .urlCleaner: return "Removes tracking junk from links you copy, so they're shorter and more private."
        case .keyDebounce: return "Ignores accidental double key presses. Useful if your keyboard sometimes types a letter twice."
        case .superKey: return "Turns a key you rarely use, like Caps Lock, into an extra modifier key for your own shortcuts."
        case .textSnippets: return "Type a short abbreviation and Sanity replaces it with longer text you use often."
        case .radialMenu: return "A circular menu that pops up under your pointer with the actions you choose."
        case .shortcuts: return "Every keyboard shortcut Sanity uses, in one place. Change any of them here."
        case .advanced: return "Back up or restore your settings, reset Sanity, and other options most people never need."
        case .about, .releaseNotes, .support: return nil
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
