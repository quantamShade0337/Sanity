// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI

/// The first page of the Sanity window: everything the system monitor knows,
/// laid out at a size the menu bar panel never has room for. It registers as
/// a full monitor surface while visible, so the samplers run only while the
/// page is on screen and stop the moment the user navigates away.
struct DashboardView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @AppStorage(SettingsPageGuide.gettingStartedDismissedKey) private var gettingStartedDismissed = false
    @Environment(\.colorScheme) private var scheme

    @State private var topCPU: [ProcessUsage] = []
    @State private var topMemory: [ProcessUsage] = []
    @State private var processesLoaded = false

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 420), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !gettingStartedDismissed {
                    GettingStartedCard(onDismiss: { gettingStartedDismissed = true })
                }
                metricsGrid
                storageSection
                processesSection
                shortcutsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { SystemMonitor.shared.panelDidAppear() }
        .onDisappear { SystemMonitor.shared.panelDidDisappear() }
        .task { await refreshProcessesLoop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))
                Text("\(Host.current().localizedName ?? "This Mac") · up \(MetricFormat.uptime(Int(ProcessInfo.processInfo.systemUptime)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if gettingStartedDismissed {
                Button {
                    gettingStartedDismissed = false
                } label: {
                    Label("Getting Started", systemImage: "lightbulb")
                }
                .controlSize(.small)
            }
            Button {
                router.request(FeatureSettingsDestination(.monitor))
            } label: {
                Label("Monitor Settings", systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)
        }
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
            if features.isAvailable(.monitorCPU) {
                MetricCard(title: "CPU", icon: "cpu",
                           value: snapshot.cpuUsage.map(MetricFormat.percent) ?? "—",
                           detail: temp(snapshot.cpuTemperature),
                           history: snapshot.cpuHistory, maxValue: 1,
                           color: usageColor(snapshot.cpuUsage))
            }
            if features.isAvailable(.monitorGPU) {
                MetricCard(title: "GPU", icon: "rectangle.3.group",
                           value: snapshot.gpuUsage.map(MetricFormat.percent) ?? "—",
                           detail: temp(snapshot.gpuTemperature),
                           history: snapshot.gpuHistory, maxValue: 1,
                           color: usageColor(snapshot.gpuUsage))
            }
            if features.isAvailable(.monitorMemory) {
                MetricCard(title: "Memory", icon: "memorychip",
                           value: memoryValue,
                           detail: memoryDetail,
                           history: snapshot.memoryHistory, maxValue: 1,
                           color: pressureColor)
            }
            if features.isAvailable(.monitorNetwork) {
                MetricCard(title: "Network", icon: "arrow.up.arrow.down",
                           value: snapshot.netDownBytesPerSec.map { "↓ " + MetricFormat.bytesPerSecCompact($0) } ?? "—",
                           detail: snapshot.netUpBytesPerSec.map { "↑ " + MetricFormat.bytesPerSecCompact($0) },
                           history: snapshot.netDownHistory, maxValue: nil,
                           color: PanelMetricColor.cyan(for: scheme))
            }
            if features.isAvailable(.monitorDisk) {
                MetricCard(title: "Disk Activity", icon: "internaldrive",
                           value: diskActivityValue,
                           detail: diskWriteDetail,
                           history: snapshot.diskReadHistory, maxValue: nil,
                           color: PanelMetricColor.mint(for: scheme))
            }
            if features.isAvailable(.monitorPower), let power = snapshot.power, !power.isEmpty {
                MetricCard(title: power.hasBattery ? "Battery" : "Power",
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
        let pressure: String
        switch snapshot.memoryPressure {
        case .normal: pressure = "normal pressure"
        case .warning: pressure = "pressure: warning"
        case .critical: pressure = "pressure: critical"
        case .unknown: pressure = ""
        }
        let amount = "\(MetricFormat.bytes(used)) of \(MetricFormat.bytes(total))"
        return pressure.isEmpty ? amount : "\(amount) · \(pressure)"
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
                parts.append("charging")
            } else if power.externalConnected {
                parts.append("on power adapter")
            } else if let seconds = power.timeRemainingSeconds, seconds > 0 {
                parts.append("\(MetricFormat.uptime(Int(seconds))) left")
            }
            if let health = power.healthPercent { parts.append("health \(Int(health.rounded()))%") }
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
            DashboardSection(title: "Storage") {
                VStack(spacing: 12) {
                    ForEach(disk.devices) { device in
                        VolumeRow(device: device)
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
            DashboardSection(title: "Top Apps") {
                HStack(alignment: .top, spacing: 24) {
                    if showCPU {
                        processList(title: "By CPU", rows: topCPU) { String(format: "%.1f%%", $0.value) }
                    }
                    if showMemory {
                        processList(title: "By Memory", rows: topMemory) { MetricFormat.bytes(UInt64(max(0, $0.value))) }
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
                Text(processesLoaded ? "Nothing to show" : "Sampling…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(height: 22)
            } else {
                ForEach(rows) { row in
                    ProcessUsageRow(row: row, value: value(row), iconSize: 16)
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Shortcuts

    private struct Shortcut: Identifiable {
        let page: SettingsPage
        let title: String
        let icon: String
        var id: SettingsPage { page }
    }

    private var shortcuts: [Shortcut] {
        [
            Shortcut(page: .cleaner, title: "Cleaner", icon: "sparkles"),
            Shortcut(page: .killProcess, title: "Kill Process", icon: "xmark.octagon"),
            Shortcut(page: .uninstaller, title: "Uninstaller", icon: "trash"),
            Shortcut(page: .clipboard, title: "Clipboard", icon: "doc.on.clipboard"),
            Shortcut(page: .windowLayout, title: "Windows", icon: "rectangle.split.2x1"),
            Shortcut(page: .notch, title: "Notch", icon: "rectangle.topthird.inset.filled"),
            Shortcut(page: .energy, title: "Energy", icon: "bolt.fill"),
            Shortcut(page: .homebrew, title: "Homebrew", icon: "mug"),
        ].filter { shortcut in
            FeatureVisibilitySupport.isPageVisible(shortcut.page) { features.isAvailable($0) }
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        let items = shortcuts
        if !items.isEmpty {
            DashboardSection(title: "Jump To") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            router.request(FeatureSettingsDestination(item.page))
                        } label: {
                            Label(item.title, systemImage: item.icon)
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
                Text("\(MetricFormat.diskBytes(device.freeBytes)) free of \(MetricFormat.diskBytes(device.totalBytes))")
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
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @Environment(\.colorScheme) private var scheme

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
                 title: "Allow Accessibility access",
                 detail: "Window snapping, shortcuts and mouse tools need this permission from macOS.",
                 button: permissions.accessibility ? "Allowed" : "Open System Settings",
                 isDone: permissions.accessibility,
                 action: { permissions.requestAccessibility() }),
            Step(id: "features", icon: "square.grid.2x2",
                 title: "Pick what Sanity does",
                 detail: "Turn on only the features you want. You can start from a ready-made set.",
                 button: "Choose features",
                 isDone: false,
                 action: { router.request(FeatureSettingsDestination(.features)) }),
            Step(id: "login", icon: "power",
                 title: "Start Sanity when you log in",
                 detail: "So your shortcuts and menu bar stats are always there.",
                 button: launchesAtLogin ? "On" : "Turn on in General",
                 isDone: launchesAtLogin,
                 action: { router.request(FeatureSettingsDestination(.general)) }),
            Step(id: "shortcuts", icon: "command",
                 title: "Learn the shortcuts",
                 detail: "See every keyboard shortcut in one list, and change any you don't like.",
                 button: "View shortcuts",
                 isDone: false,
                 action: { router.request(FeatureSettingsDestination(.shortcuts)) }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Getting Started", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Hide", action: onDismiss)
                    .buttonStyle(.borderless)
                    .help("Hide this card. Bring it back with the Getting Started button above.")
            }
            Text("New to Sanity? These four steps take about a minute. Everything else is in the sidebar, and you can search for any setting at the top of it.")
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
        .accessibilityLabel("Step \(number): \(step.title)\(step.isDone ? ", done" : "")")
    }
}
