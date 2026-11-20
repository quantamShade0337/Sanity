// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI
import SystemConfiguration

/// The parts of the Dashboard a person can switch off.
enum DashboardCard: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, power, storage, processes, alerts, shortcuts
    var id: String { rawValue }

    static let hiddenKey = "dashboardHiddenCards"

    static func decodeHidden(_ raw: String) -> Set<DashboardCard> {
        Set(raw.split(separator: ",").compactMap { DashboardCard(rawValue: String($0)) })
    }

    static func encodeHidden(_ cards: Set<DashboardCard>) -> String {
        cards.map(\.rawValue).sorted().joined(separator: ",")
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return GuideText.t(.memory, language)
        case .network: return GuideText.t(.network, language)
        case .disk: return GuideText.t(.diskActivity, language)
        case .power: return GuideText.t(.battery, language)
        case .storage: return GuideText.t(.storage, language)
        case .processes: return GuideText.t(.topApps, language)
        case .alerts: return GuideText.t(.recentAlerts, language)
        case .shortcuts: return GuideText.t(.jumpTo, language)
        }
    }
}

/// The first page of the Sanity window: everything the system monitor knows,
/// laid out at a size the menu bar panel never has room for. It registers as
/// a full monitor surface while visible, so the samplers run only while the
/// page is on screen and stop the moment the user navigates away.
struct DashboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var alertHistory = MonitorAlertHistory.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @AppStorage(SettingsPageGuide.gettingStartedDismissedKey) private var gettingStartedDismissed = false
    @AppStorage(DashboardCard.hiddenKey) private var hiddenCardsRaw = ""
    @Environment(\.colorScheme) private var scheme

    @State private var topCPU: [ProcessUsage] = []
    @State private var topMemory: [ProcessUsage] = []
    @State private var processesLoaded = false
    @State private var showingCustomize = false

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 420), spacing: 12)]

    private var lang: AppLanguage { l10n.language }
    private func t(_ key: GuideKey) -> String { GuideText.t(key, lang) }
    private var hidden: Set<DashboardCard> { DashboardCard.decodeHidden(hiddenCardsRaw) }
    private func shows(_ card: DashboardCard) -> Bool { !hidden.contains(card) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !gettingStartedDismissed {
                    GettingStartedCard(onDismiss: { gettingStartedDismissed = true })
                }
                metricsGrid
                if shows(.storage) { storageSection }
                if shows(.processes) { processesSection }
                if shows(.alerts) { alertsSection }
                if shows(.shortcuts) { shortcutsSection }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { SystemMonitor.shared.panelDidAppear() }
        .onDisappear { SystemMonitor.shared.panelDidDisappear() }
        .task(id: shows(.processes)) {
            guard shows(.processes) else { return }
            await refreshProcessesLoop()
        }
    }

    // MARK: - Header

    private static let computerName: String? =
        SCDynamicStoreCopyComputerName(nil, nil) as String?

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(.dashTitle))
                    .font(.largeTitle.weight(.semibold))
                Text(GuideText.f(.dashSubtitle,
                                 Self.computerName ?? t(.thisMac),
                                 MetricFormat.uptime(Int(ProcessInfo.processInfo.systemUptime)),
                                 language: lang))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if gettingStartedDismissed {
                Button {
                    gettingStartedDismissed = false
                } label: {
                    Label(t(.gettingStarted), systemImage: "lightbulb")
                }
                .controlSize(.small)
            }
            Button {
                showingCustomize.toggle()
            } label: {
                Label(t(.customize), systemImage: "square.grid.2x2")
            }
            .controlSize(.small)
            .popover(isPresented: $showingCustomize, arrowEdge: .bottom) { customizePopover }
            Button {
                router.request(FeatureSettingsDestination(.monitor))
            } label: {
                Label(t(.monitorSettings), systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)
        }
    }

    private var customizePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t(.showOnDashboard))
                .font(.headline)
            ForEach(DashboardCard.allCases) { card in
                Toggle(card.title(lang), isOn: Binding(
                    get: { shows(card) },
                    set: { visible in
                        var cards = hidden
                        if visible { cards.remove(card) } else { cards.insert(card) }
                        hiddenCardsRaw = DashboardCard.encodeHidden(cards)
                    }))
            }
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }

    // MARK: - Live metrics

    private var snapshot: SystemSnapshot { monitor.snapshot }
    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }

    private func temp(_ value: Double?) -> String? {
        value.map { MetricFormat.temperature($0, unit: temperatureUnit) }
    }

    @ViewBuilder
    private var metricsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            if shows(.cpu), features.isAvailable(.monitorCPU) {
                MetricCard(title: "CPU", icon: "cpu",
                           value: snapshot.cpuUsage.map(MetricFormat.percent) ?? "—",
                           detail: temp(snapshot.cpuTemperature),
                           history: snapshot.cpuHistory, maxValue: 1,
                           color: usageColor(snapshot.cpuUsage))
            }
            if shows(.gpu), features.isAvailable(.monitorGPU) {
                MetricCard(title: "GPU", icon: "rectangle.3.group",
                           value: snapshot.gpuUsage.map(MetricFormat.percent) ?? "—",
                           detail: temp(snapshot.gpuTemperature),
                           history: snapshot.gpuHistory, maxValue: 1,
                           color: usageColor(snapshot.gpuUsage))
            }
            if shows(.memory), features.isAvailable(.monitorMemory) {
                MetricCard(title: t(.memory), icon: "memorychip",
                           value: memoryValue,
                           detail: memoryDetail,
                           history: snapshot.memoryHistory, maxValue: 1,
                           color: pressureColor)
            }
            if shows(.network), features.isAvailable(.monitorNetwork) {
                MetricCard(title: t(.network), icon: "arrow.up.arrow.down",
                           value: snapshot.netDownBytesPerSec.map { "↓ " + MetricFormat.bytesPerSecCompact($0) } ?? "—",
                           detail: snapshot.netUpBytesPerSec.map { "↑ " + MetricFormat.bytesPerSecCompact($0) },
                           history: snapshot.netDownHistory, maxValue: nil,
                           color: PanelMetricColor.cyan(for: scheme))
            }
            if shows(.disk), features.isAvailable(.monitorDisk) {
                MetricCard(title: t(.diskActivity), icon: "internaldrive",
                           value: diskActivityValue,
                           detail: diskWriteDetail,
                           history: snapshot.diskReadHistory, maxValue: nil,
                           color: PanelMetricColor.mint(for: scheme))
            }
            if shows(.power), features.isAvailable(.monitorPower), let power = snapshot.power, !power.isEmpty {
                MetricCard(title: power.hasBattery ? t(.battery) : t(.power),
                           icon: batteryIcon(power),
                           value: powerValue(power),
                           detail: powerDetail(power),
                           history: power.hasBattery ? snapshot.batteryHistory : snapshot.systemPowerHistory,
                           maxValue: power.hasBattery ? 1 : nil,
                           color: PanelMetricColor.green(for: scheme))
            }
        }
    }

    private var memoryValue: String {
        guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return "—" }
        return MetricFormat.percent(Double(used) / Double(total))
    }

    private var memoryDetail: String? {
        guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal else { return nil }
        let pressure: String?
        switch snapshot.memoryPressure {
        case .normal: pressure = t(.pressureNormal)
        case .warning: pressure = t(.pressureWarning)
        case .critical: pressure = t(.pressureCritical)
        case .unknown: pressure = nil
        }
        let amount = GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes(total), language: lang)
        return pressure.map { "\(amount) · \($0)" } ?? amount
    }

    private var diskActivityValue: String {
        guard let reading = snapshot.disk else { return "—" }
        let read = reading.uniqueIODevices.compactMap(\.readBytesPerSec).reduce(0, +)
        return "R " + MetricFormat.bytesPerSecCompact(read)
    }

    private var diskWriteDetail: String? {
        guard let reading = snapshot.disk else { return nil }
        let write = reading.uniqueIODevices.compactMap(\.writeBytesPerSec).reduce(0, +)
        return "W " + MetricFormat.bytesPerSecCompact(write)
    }

    private func powerValue(_ power: PowerReading) -> String {
        if power.hasBattery, let charge = power.chargePercent { return "\(charge)%" }
        if let watts = power.systemWatts { return MetricFormat.watts(watts) }
        return "—"
    }

    private func powerDetail(_ power: PowerReading) -> String? {
        var parts: [String] = []
        if power.hasBattery {
            if power.isCharging {
                parts.append(t(.charging))
            } else if power.externalConnected {
                parts.append(t(.onAdapter))
            } else if let seconds = power.timeRemainingSeconds, seconds > 0 {
                parts.append(GuideText.f(.timeLeft, MetricFormat.uptime(Int(seconds)), language: lang))
            }
            if let health = power.healthPercent {
                parts.append(GuideText.f(.health, "\(Int(health.rounded()))%", language: lang))
            }
        }
        if let watts = power.systemWatts, power.hasBattery { parts.append(MetricFormat.watts(watts)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func batteryIcon(_ power: PowerReading) -> String {
        guard power.hasBattery else { return "bolt" }
        if power.isCharging { return "battery.100percent.bolt" }
        switch power.chargePercent ?? 100 {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func usageColor(_ fraction: Double?) -> Color {
        guard let fraction else { return .accentColor }
        if fraction >= 0.85 { return PanelMetricColor.red(for: scheme) }
        if fraction >= 0.6 { return PanelMetricColor.orange(for: scheme) }
        return .accentColor
    }

    private var pressureColor: Color {
        switch snapshot.memoryPressure {
        case .critical: return PanelMetricColor.red(for: scheme)
        case .warning: return PanelMetricColor.yellow(for: scheme)
        default: return PanelMetricColor.pink(for: scheme)
        }
    }

    // MARK: - Storage

    @ViewBuilder
    private var storageSection: some View {
        if features.isAvailable(.monitorDisk), let disk = snapshot.disk, !disk.isEmpty {
            DashboardSection(title: t(.storage)) {
                VStack(spacing: 12) {
                    ForEach(disk.devices) { device in
                        VolumeRow(device: device, freeText: GuideText.f(
                            .freeOf, MetricFormat.diskBytes(device.freeBytes),
                            MetricFormat.diskBytes(device.totalBytes), language: lang))
                    }
                }
            }
        }
    }

    // MARK: - Processes

    @ViewBuilder
    private var processesSection: some View {
        let showCPU = features.isAvailable(.monitorCPU)
        let showMemory = features.isAvailable(.monitorMemory)
        if showCPU || showMemory {
            DashboardSection(title: t(.topApps)) {
                HStack(alignment: .top, spacing: 24) {
                    if showCPU {
                        processList(title: t(.byCPU), rows: topCPU) { String(format: "%.1f%%", $0.value) }
                    }
                    if showMemory {
                        processList(title: t(.byMemory), rows: topMemory) { MetricFormat.bytes(UInt64(max(0, $0.value))) }
                    }
                }
            }
        }
    }

    private func processList(title: String, rows: [ProcessUsage],
                             value: @escaping (ProcessUsage) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(processesLoaded ? t(.nothingToShow) : t(.sampling))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(height: 22)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        ProcessUsageRow(row: row, value: value(row), iconSize: 16)
                            .font(.callout)
                        quitButton(for: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only ordinary apps with a Dock icon get a Quit button: background
    /// helpers and system processes are left to the Kill Process page.
    @ViewBuilder
    private func quitButton(for row: ProcessUsage) -> some View {
        if let app = NSRunningApplication(processIdentifier: row.pid),
           app.activationPolicy == .regular,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let name = app.localizedName ?? row.name
            Button {
                app.terminate()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(GuideText.f(.quitApp, name, language: lang) + " — " + t(.quitHelp))
            .accessibilityLabel(GuideText.f(.quitApp, name, language: lang))
        } else {
            Color.clear.frame(width: 13, height: 13)
        }
    }

    /// Refreshes the process lists off the main thread while the page is
    /// visible. The `.task` modifier cancels this loop on disappear.
    private func refreshProcessesLoop() async {
        while !Task.isCancelled {
            let interval = TimeInterval(SanityDefaults.sanitizedMonitorInterval(monitorInterval))
            let cpuPercent = monitor.snapshot.cpuUsage.map { $0 * 100 }
            let wantCPU = features.isAvailable(.monitorCPU)
            let wantMemory = features.isAvailable(.monitorMemory)
            let rows = await Task.detached(priority: .utility) { () -> ([ProcessUsage], [ProcessUsage]) in
                let service = ProcessUsageService.shared
                let cpu = wantCPU ? service.top(.cpu, limit: 6, sampleInterval: interval, cpuPercentage: cpuPercent) : []
                let memory = wantMemory ? service.top(.memory, limit: 6) : []
                return (cpu, memory)
            }.value
            guard !Task.isCancelled else { return }
            if !rows.0.isEmpty || topCPU.isEmpty { topCPU = rows.0 }
            if !rows.1.isEmpty || topMemory.isEmpty { topMemory = rows.1 }
            processesLoaded = true
            try? await Task.sleep(for: .seconds(max(3, interval * 2)))
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        DashboardSection(title: t(.recentAlerts)) {
            if alertHistory.entries.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(t(.noAlerts))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(t(.setUpAlerts)) {
                        router.request(FeatureSettingsDestination(.monitor))
                    }
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alertHistory.entries.prefix(6)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(PanelMetricColor.orange(for: scheme))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title).fontWeight(.medium)
                                Text(entry.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack {
                        Spacer()
                        Button(t(.clear)) { alertHistory.clear() }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts

    private static let shortcutPages: [SettingsPage] = [
        .cleaner, .killProcess, .uninstaller, .clipboard, .windowLayout, .notch, .energy, .homebrew,
    ]

    private struct Shortcut: Identifiable {
        let page: SettingsPage
        let title: String
        let icon: String
        var id: SettingsPage { page }
    }

    private var shortcuts: [Shortcut] {
        let items = SettingsDirectory.sections(l10n.s, language: lang).flatMap(\.items)
        return Self.shortcutPages.compactMap { page in
            guard FeatureVisibilitySupport.isPageVisible(page, isAvailable: { features.isAvailable($0) }),
                  let item = items.first(where: { $0.page == page }) else { return nil }
            return Shortcut(page: page, title: item.title, icon: item.icon)
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        let items = shortcuts
        if !items.isEmpty {
            DashboardSection(title: t(.jumpTo)) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            router.request(FeatureSettingsDestination(item.page))
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(PanelSurface.controlFill(for: scheme),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct DashboardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelSurface.cardFill(for: scheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: scheme)))
        }
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let detail: String?
    let history: [Double]
    let maxValue: Double?
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Sparkline(values: history, color: color, maxValue: maxValue, fillOpacity: 0.22, lineWidth: 1.6)
                .frame(height: 44)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelSurface.cardFill(for: scheme),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(PanelSurface.border(for: scheme)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct VolumeRow: View {
    let device: DiskDeviceReading
    let freeText: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: device.isInternal ? "internaldrive" : "externaldrive")
                    .foregroundStyle(.secondary)
                Text(device.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let fs = device.fileSystem {
                    Text(fs)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(freeText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: device.usedFraction)
                .tint(barColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var barColor: Color {
        if device.usedFraction >= 0.9 { return PanelMetricColor.red(for: scheme) }
        if device.usedFraction >= 0.75 { return PanelMetricColor.orange(for: scheme) }
        return .accentColor
    }
}

// MARK: - Getting started

/// A short checklist for someone opening Sanity for the first time. Each step
/// explains why it matters in one line and links straight to the right page.
private struct GettingStartedCard: View {
    let onDismiss: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @Environment(\.colorScheme) private var scheme

    private func t(_ key: GuideKey) -> String { GuideText.t(key, l10n.language) }

    private struct Step: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let button: String
        let isDone: Bool
        let action: () -> Void
    }

    private var steps: [Step] {
        [
            Step(id: "accessibility", icon: "hand.raised",
                 title: t(.gsAccessTitle), detail: t(.gsAccessDetail),
                 button: permissions.accessibility ? t(.allowed) : t(.openSystemSettings),
                 isDone: permissions.accessibility,
                 action: { permissions.requestAccessibility() }),
            Step(id: "features", icon: "square.grid.2x2",
                 title: t(.gsFeaturesTitle), detail: t(.gsFeaturesDetail),
                 button: t(.gsFeaturesButton), isDone: false,
                 action: { router.request(FeatureSettingsDestination(.features)) }),
            Step(id: "login", icon: "power",
                 title: t(.gsLoginTitle), detail: t(.gsLoginDetail),
                 button: launchesAtLogin ? t(.on) : t(.gsLoginButton),
                 isDone: launchesAtLogin,
                 action: { router.request(FeatureSettingsDestination(.general)) }),
            Step(id: "shortcuts", icon: "command",
                 title: t(.gsShortcutsTitle), detail: t(.gsShortcutsDetail),
                 button: t(.gsShortcutsButton), isDone: false,
                 action: { router.request(FeatureSettingsDestination(.shortcuts)) }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(t(.gettingStarted), systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button(t(.hide), action: onDismiss)
                    .buttonStyle(.borderless)
                    .help(t(.hideHelp))
            }
            Text(t(.gsIntro))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Divider() }
                    stepRow(step, number: index + 1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.25)))
        .onAppear {
            permissions.refresh()
            launchesAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func stepRow(_ step: Step, number: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(step.isDone ? Color.green : Color.accentColor.opacity(0.18))
                if step.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .fontWeight(.medium)
                    .strikethrough(step.isDone, color: .secondary)
                    .foregroundStyle(step.isDone ? .secondary : .primary)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(step.button, action: step.action)
                .controlSize(.small)
                .disabled(step.isDone)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GuideText.f(.stepLabel, "\(number)",
                                        step.isDone ? "\(step.title), \(t(.done))" : step.title,
                                        language: l10n.language))
    }
}
