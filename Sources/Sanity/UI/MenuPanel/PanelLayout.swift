// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

/// The major, user-customizable sections of the menu panel. Raw values are the
/// stable identifiers persisted in the saved order and the collapsed set, so
/// renaming a case would orphan a user's stored layout — keep them stable.
enum PanelSectionID: String, CaseIterable, Identifiable, Hashable {
    case keepAwake, brightness, mixer, system, network, disk, power, fanControl, utilities, controls,
         toggles

    var id: String { rawValue }

    /// Localized display name, reused from the existing section titles.
    func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .power: return s.powerSection
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        case .utilities: return s.utilitiesSection
        case .controls: return s.quickControlsSection
        case .toggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        }
    }

    var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .mixer: return "slider.horizontal.3"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        case .toggles: return "togglepower"
        }
    }

    /// The UserDefaults key that controls whether this section shows in the panel.
    /// The monitoring blocks reuse their existing `monitorShow*` keys; the rest
    /// get a dedicated `panelShow*` key so every section is hideable.
    var visibilityKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.panelShowKeepAwake
        case .brightness: return DefaultsKey.panelShowBrightness
        case .mixer: return DefaultsKey.monitorShowMixer
        case .system: return DefaultsKey.monitorShowSystem
        case .network: return DefaultsKey.monitorShowNetwork
        case .disk: return DefaultsKey.monitorShowDisk
        case .power: return DefaultsKey.monitorShowPower
        case .fanControl: return DefaultsKey.panelShowFanControl
        case .utilities: return DefaultsKey.panelShowUtilities
        case .controls: return DefaultsKey.panelShowControls
        case .toggles: return DefaultsKey.panelShowToggles
        }
    }

    /// Installed sections show by default and remain individually hideable.
    var shownByDefault: Bool { true }

    /// Hub features that keep this section alive: with all of them off, the
    /// section leaves the panel, the section navigation and the layout
    /// editors, regardless of its visibility key (which is preserved for the
    /// feature's return).
    var featureGate: [AppFeature] {
        switch self {
        case .keepAwake: return [.keepAwake]
        case .brightness: return [.brightness]
        case .mixer: return [.mixer]
        case .system: return [.monitorCPU, .monitorGPU, .monitorMemory]
        case .network: return [.monitorNetwork]
        case .disk: return [.monitorDisk]
        case .power: return [.monitorPower]
        case .fanControl: return [.fanControl]
        case .utilities: return [.quickLauncher, .cleaner, .homebrew, .appUpdates, .mediaTools,
                                 .clipboardHistory,
                                 .windowLayout, .uninstaller, .urlCleaner, .cleaningMode, .screenOCR,
                                 .colorPicker, .screenshot, .screenRecorder,
                                 .cameraPreview, .scratchpad, .commandBar]
        case .controls: return [.scrollInverter, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .switcher,
                                .finderCutPaste, .autoQuit,
                                .shelf, .windowMaximizer, .dockPreview, .keyboardDebounce, .dockClick,
                                .middleClick, .textSnippets, .superKey, .radialMenu, .mouseClickDebounce]
        case .toggles: return [.quickToggles, .micMute]
        }
    }

    var isAvailable: Bool { featureGate.contains(where: \.isAvailable) }
}

/// Persisted panel layout: the order the sections appear in and which ones are
/// collapsed. The order is a comma-joined list of ids; any section missing from
/// a saved order (e.g. one added in a later version) is appended in its canonical
/// position, so a section can never silently disappear. Collapsed sections are a
/// comma-joined set of ids.
enum PanelLayout {
    private static var defaults: UserDefaults { .standard }

    /// The sections in display order: the user's saved order first, then any not
    /// yet listed, in their canonical order.
    static var order: [PanelSectionID] {
        let saved = (defaults.string(forKey: DefaultsKey.panelSectionOrder) ?? "")
            .split(separator: ",")
            .compactMap { PanelSectionID(rawValue: String($0)) }
        var seen = Set<PanelSectionID>()
        var result: [PanelSectionID] = []
        for id in saved where seen.insert(id).inserted { result.append(id) }
        for id in PanelSectionID.allCases where seen.insert(id).inserted {
            if id == .disk, let networkIndex = result.firstIndex(of: .network) {
                result.insert(id, at: networkIndex + 1)
            } else if id == .controls, let utilitiesIndex = result.firstIndex(of: .utilities) {
                result.insert(id, at: utilitiesIndex + 1)
            } else if id == .brightness, let keepAwakeIndex = result.firstIndex(of: .keepAwake) {
                // New in 3.1.13: saved orders predate it, so it slots in at
                // its canonical place instead of the end.
                result.insert(id, at: keepAwakeIndex + 1)
            } else {
                result.append(id)
            }
        }
        return result
    }

    static func setOrder(_ ids: [PanelSectionID]) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
    }

    static func itemOrder<Item: PanelOrderItem>(_ type: Item.Type, key: String) -> [Item] {
        let defaultOrder = type.allCases.map(\.rawValue)
        let raw = defaults.string(forKey: key) ?? ""
        return SanityDefaults.sanitizedPanelItemOrder(raw, defaultOrder: defaultOrder).compactMap(Item.init(rawValue:))
    }

    static func setItemOrder<Item: PanelOrderItem>(_ ids: [Item], key: String) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: key)
    }

    static func resetItemOrder(key: String) {
        defaults.removeObject(forKey: key)
    }

    /// The sections the one-click Simple Panel keeps: sound, Keep Awake and
    /// the system glance, matching the focused menu bar described in the
    /// architecture notes. Everything else stays reachable in the main window
    /// and can be switched back on in the editor above.
    static let simplePresetSections: Set<PanelSectionID> = [.mixer, .keepAwake, .system]

    static func applySimplePreset() {
        for id in PanelSectionID.allCases {
            setShown(simplePresetSections.contains(id), for: id)
        }
        NotificationCenter.default.post(name: visibilityPresetApplied, object: nil)
    }

    /// Posted after a preset rewrites several visibility keys at once, so
    /// editors that cache visibility can refresh.
    static let visibilityPresetApplied = Notification.Name("PanelLayoutVisibilityPresetApplied")

    static func isShown(_ id: PanelSectionID) -> Bool {
        defaults.object(forKey: id.visibilityKey) as? Bool ?? id.shownByDefault
    }

    static func setShown(_ shown: Bool, for id: PanelSectionID) {
        defaults.set(shown, forKey: id.visibilityKey)
    }

    static func isCollapsed(_ id: PanelSectionID) -> Bool {
        collapsedSet().contains(id.rawValue)
    }

    static func setCollapsed(_ collapsed: Bool, for id: PanelSectionID) {
        var set = collapsedSet()
        if collapsed { set.insert(id.rawValue) } else { set.remove(id.rawValue) }
        defaults.set(set.sorted().joined(separator: ","), forKey: DefaultsKey.panelCollapsedSections)
    }

    static func resetCollapsedSectionsOnce(for version: String) {
        guard defaults.string(forKey: DefaultsKey.panelCollapsedResetVersion) != version else { return }
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedSections)
        defaults.set(version, forKey: DefaultsKey.panelCollapsedResetVersion)
    }

    private static func collapsedSet() -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.panelCollapsedSections) ?? "")
            .split(separator: ",").map(String.init))
    }
}

struct PanelDragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 22)
            .contentShape(Rectangle())
            .help(L10n.shared.s.monitorOrderHint)
    }
}

struct PanelReorderableItem<Item: PanelOrderItem, Content: View>: View {
    let item: Item
    var isEnabled = true
    @Binding var order: [Item]
    @Binding var dragging: Item?
    let content: () -> Content

    var body: some View {
        if isEnabled {
            content()
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: PanelItemDropDelegate(item: item,
                                                                           order: $order,
                                                                           dragging: $dragging))
        } else {
            content()
        }
    }
}

private struct PanelItemDropDelegate<Item: PanelOrderItem>: DropDelegate {
    let item: Item
    @Binding var order: [Item]
    @Binding var dragging: Item?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct PanelInlineHideButton: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isVisible ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((isVisible ? Color.primary : Color.accentColor).opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(isVisible ? l10n.s.panelHideItem : l10n.s.panelShowItem)
        .accessibilityLabel(isVisible ? l10n.s.panelHideItem : l10n.s.panelShowItem)
    }
}

struct PanelHiddenBadge: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Label(l10n.s.panelHiddenItem, systemImage: "eye.slash.fill")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

