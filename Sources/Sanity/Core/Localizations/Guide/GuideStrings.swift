// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import Foundation

/// Strings for the Dashboard, the beginner guide (page summaries, Getting
/// Started, simple sidebar), permission banners, the simple menu panel and
/// Sanity's notch events. One key enum, one table per language; a unit test
/// checks every language covers every key and keeps the same format slots.
enum GuideKey: String, CaseIterable {
    // Dashboard
    case dashTitle, dashSubtitle, thisMac, monitorSettings, gettingStarted, customize
    case memory, network, diskActivity, battery, power, storage, topApps, byCPU, byMemory
    case nothingToShow, sampling, jumpTo, amountOf, freeOf
    case pressureNormal, pressureWarning, pressureCritical
    case charging, onAdapter, timeLeft, health
    case quitApp, quitHelp
    case recentAlerts, noAlerts, setUpAlerts, clear, showOnDashboard
    // Getting started
    case gsIntro, hide, hideHelp
    case gsAccessTitle, gsAccessDetail, openSystemSettings, allowed
    case gsFeaturesTitle, gsFeaturesDetail, gsFeaturesButton
    case gsLoginTitle, gsLoginDetail, gsLoginButton, on
    case gsShortcutsTitle, gsShortcutsDetail, gsShortcutsButton
    case stepLabel, done
    // Sidebar
    case showAllPages, showFewerPages, showAllHelp, showFewerHelp
    // Permission banners
    case needsAccessibility, needsScreenRecording
    // Menu panel
    case simplePanel, simplePanelHelp
    // Notch events
    case notchSubtitle, notchEventsSection, notchEventsCaption
    case notchEventKeepAwake, notchEventCopied, notchEventCapture, notchEventOutput
    case evKeepAwakeOn, evKeepAwakeOff, evCopied, evScreenshot, evRecording
    // Page summaries
    case sumGeneral, sumFeatures, sumEnergy, sumMonitor, sumMouse, sumSwitcher, sumWindowLayout
    case sumAutoQuit, sumQuitProtection, sumClipboard, sumCutPaste, sumShelf, sumMedia
    case sumAppUpdates, sumCleaner, sumHomebrew, sumUninstaller, sumKillProcess, sumCommandBar
    case sumQuickTools, sumScreenshot, sumURLCleaner, sumKeyDebounce, sumSuperKey
    case sumTextSnippets, sumRadialMenu, sumShortcuts, sumAdvanced
}

enum GuideText {
    static func table(_ language: AppLanguage) -> [GuideKey: String] {
        switch language {
        case .enUS: return GuideStrings.enUS
        case .ptBR: return GuideStrings.ptBR
        case .tr: return GuideStrings.tr
        case .ru: return GuideStrings.ru
        case .es: return GuideStrings.es
        case .de: return GuideStrings.de
        case .fr: return GuideStrings.fr
        case .it: return GuideStrings.it
        case .ja: return GuideStrings.ja
        case .ko: return GuideStrings.ko
        case .zhHans: return GuideStrings.zhHans
        case .zhTW: return GuideStrings.zhTW
        case .zhHK: return GuideStrings.zhHK
        }
    }

    /// The string for `key` in `language`, falling back to English.
    static func t(_ key: GuideKey, _ language: AppLanguage = L10n.shared.language) -> String {
        table(language)[key] ?? GuideStrings.enUS[key] ?? key.rawValue
    }

    /// A format string from the table filled with `args` (all `%@`).
    static func f(_ key: GuideKey, _ args: String..., language: AppLanguage = L10n.shared.language) -> String {
        String(format: t(key, language), arguments: args.map { $0 as CVarArg })
    }
}

/// Namespace for the per-language tables (one file each).
enum GuideStrings {}

extension GuideStrings {
    static let enUS: [GuideKey: String] = [
        .dashTitle: "Dashboard",
        .dashSubtitle: "%@ · up %@",
        .thisMac: "This Mac",
        .monitorSettings: "Monitor Settings",
        .gettingStarted: "Getting Started",
        .customize: "Customize",
        .memory: "Memory",
        .network: "Network",
        .diskActivity: "Disk Activity",
        .battery: "Battery",
        .power: "Power",
        .storage: "Storage",
        .topApps: "Top Apps",
        .byCPU: "By CPU",
        .byMemory: "By Memory",
        .nothingToShow: "Nothing to show",
        .sampling: "Sampling…",
        .jumpTo: "Jump To",
        .amountOf: "%@ of %@",
        .freeOf: "%@ free of %@",
        .pressureNormal: "normal pressure",
        .pressureWarning: "pressure: warning",
        .pressureCritical: "pressure: critical",
        .charging: "charging",
        .onAdapter: "on power adapter",
        .timeLeft: "%@ left",
        .health: "health %@",
        .quitApp: "Quit %@",
        .quitHelp: "Asks the app to quit, the same as choosing Quit from its menu.",
        .recentAlerts: "Recent Alerts",
        .noAlerts: "No alerts yet. Sanity can warn you when the CPU runs hot, memory is low, the disk is almost full or the battery is low.",
        .setUpAlerts: "Set Up Alerts",
        .clear: "Clear",
        .showOnDashboard: "Show on Dashboard",
        .gsIntro: "New to Sanity? These four steps take about a minute. Everything else is in the sidebar, and you can search for any setting at the top of it.",
        .hide: "Hide",
        .hideHelp: "Hide this card. Bring it back with the Getting Started button above.",
        .gsAccessTitle: "Allow Accessibility access",
        .gsAccessDetail: "Window snapping, shortcuts and mouse tools need this permission from macOS.",
        .openSystemSettings: "Open System Settings",
        .allowed: "Allowed",
        .gsFeaturesTitle: "Pick what Sanity does",
        .gsFeaturesDetail: "Turn on only the features you want. You can start from a ready-made set.",
        .gsFeaturesButton: "Choose Features",
        .gsLoginTitle: "Start Sanity when you log in",
        .gsLoginDetail: "So your shortcuts and menu bar stats are always there.",
        .gsLoginButton: "Turn On in General",
        .on: "On",
        .gsShortcutsTitle: "Learn the shortcuts",
        .gsShortcutsDetail: "See every keyboard shortcut in one list, and change any you don't like.",
        .gsShortcutsButton: "View Shortcuts",
        .stepLabel: "Step %@: %@",
        .done: "done",
        .showAllPages: "Show all pages (%@ more)",
        .showFewerPages: "Show fewer pages",
        .showAllHelp: "List every settings page, including advanced tools.",
        .showFewerHelp: "Only list the pages most people use. Search still finds every page.",
        .needsAccessibility: "%@ needs Accessibility permission to work.",
        .needsScreenRecording: "%@ needs Screen Recording permission to work.",
        .simplePanel: "Simple Panel",
        .simplePanelHelp: "Show only sound, Keep Awake and system stats in the menu bar panel. Everything else stays in the Sanity window.",
        .notchSubtitle: "Shows music, volume, brightness and battery in a small panel at the top of your screen, around the camera notch.",
        .notchEventsSection: "Sanity events",
        .notchEventsCaption: "Briefly show these in the notch when they happen.",
        .notchEventKeepAwake: "Keep Awake turned on or off",
        .notchEventCopied: "Something copied",
        .notchEventCapture: "Screenshot or recording saved",
        .notchEventOutput: "Sound output changed",
        .evKeepAwakeOn: "Keep Awake on",
        .evKeepAwakeOff: "Keep Awake off",
        .evCopied: "Copied",
        .evScreenshot: "Screenshot saved",
        .evRecording: "Recording saved",
        .sumGeneral: "Basic options: start Sanity when you log in, change the language and appearance, and choose what the menu bar icon shows.",
        .sumFeatures: "Turn whole features on or off. Anything you switch off here disappears from Sanity completely, so start small and add more later.",
        .sumEnergy: "Keep your Mac awake, change screen brightness, and control what happens to Bluetooth when your Mac sleeps.",
        .sumMonitor: "Choose which live stats (CPU, memory, temperature and more) appear in the menu bar, and how often they update.",
        .sumMouse: "Change how your mouse and trackpad behave: scroll direction, smooth scrolling, extra buttons and middle click.",
        .sumSwitcher: "A better app and window switcher, plus options for what clicking an app in the Dock does.",
        .sumWindowLayout: "Snap windows to halves, thirds or corners of the screen with a shortcut or by dragging them to an edge.",
        .sumAutoQuit: "Automatically quit apps you haven't used for a while, so they stop using memory and battery.",
        .sumQuitProtection: "Stops ⌘Q and ⌘W from quitting apps or closing windows by accident: you can make them need a hold or a double press.",
        .sumClipboard: "Remembers what you copy so you can paste something from earlier. Your history stays on this Mac.",
        .sumCutPaste: "Adds real cut and paste for files in Finder, and quicker ways to rename files.",
        .sumShelf: "A temporary spot to drop files while you move them between windows or apps.",
        .sumMedia: "Convert, resize and crop images and PDFs, add watermarks, and rename files in bulk.",
        .sumAppUpdates: "Checks the apps you have installed and tells you when updates are available.",
        .sumCleaner: "Finds caches, logs and leftover files you can safely remove to free up disk space.",
        .sumHomebrew: "Manage Homebrew packages without the Terminal. Only useful if you already use Homebrew.",
        .sumUninstaller: "Removes an app together with the settings and support files it leaves behind.",
        .sumKillProcess: "Force-quit apps or background processes that have stopped responding.",
        .sumCommandBar: "A search bar you open with a shortcut to launch apps, run Sanity's tools, and jump to settings.",
        .sumQuickTools: "Small tools you can open from anywhere: a quick launcher, toggles, microphone mute, a camera preview and a scratchpad.",
        .sumScreenshot: "Take screenshots and screen recordings, pick colors, and copy text from anything on screen.",
        .sumURLCleaner: "Removes tracking junk from links you copy, so they're shorter and more private.",
        .sumKeyDebounce: "Ignores accidental double key presses. Useful if your keyboard sometimes types a letter twice.",
        .sumSuperKey: "Turns a key you rarely use, like Caps Lock, into an extra modifier key for your own shortcuts.",
        .sumTextSnippets: "Type a short abbreviation and Sanity replaces it with longer text you use often.",
        .sumRadialMenu: "A circular menu that pops up under your pointer with the actions you choose.",
        .sumShortcuts: "Every keyboard shortcut Sanity uses, in one place. Change any of them here.",
        .sumAdvanced: "Back up or restore your settings, reset Sanity, and other options most people never need.",
    ]
}
