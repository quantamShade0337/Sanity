// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI
import SystemConfiguration

/// What the Dashboard says first: one plain-language verdict about the Mac.
struct DashboardStatus: Equatable {
    enum Level: Equatable { case good, warning }
    enum Action: Equatable { case cleaner }

    let level: Level
    let title: GuideKey
    let detailKey: GuideKey
    let detailArgument: String?
    let action: Action?

    /// The single most important thing to tell the person, worst first.
    static func evaluate(cpu: Double?, cpuTemperature: Double?, pressure: MemoryPressure,
                         mainDiskFree: UInt64?, mainDiskTotal: UInt64?,
                         battery: PowerReading?, formatTemperature: (Double) -> String) -> DashboardStatus {
        if let free = mainDiskFree, let total = mainDiskTotal, total > 0,
           Double(free) / Double(total) < 0.08 || free < 10_000_000_000 {
            return .init(level: .warning, title: .statusDisk, detailKey: .statusDiskDetail,
                         detailArgument: MetricFormat.diskBytes(free), action: .cleaner)
        }
        if pressure == .critical || pressure == .warning {
            return .init(level: .warning, title: .statusMemory, detailKey: .statusMemoryDetail,
                         detailArgument: nil, action: nil)
        }
        if let battery, battery.hasBattery, !battery.isCharging, !battery.externalConnected,
           let charge = battery.chargePercent, charge <= 15 {
            let left = battery.timeRemainingSeconds.map { MetricFormat.uptime(Int($0)) } ?? "\(charge)%"
            return .init(level: .warning, title: .statusBattery, detailKey: .statusBatteryDetail,
                         detailArgument: left, action: nil)
        }
        if let temperature = cpuTemperature, temperature >= 95 {
            return .init(level: .warning, title: .statusHot, detailKey: .statusHotDetail,
                         detailArgument: formatTemperature(temperature), action: nil)
        }
        if let cpu, cpu >= 0.85 {
            return .init(level: .warning, title: .statusBusy, detailKey: .statusBusyDetail,
                         detailArgument: MetricFormat.percent(cpu), action: nil)
        }
        return .init(level: .good, title: .statusGood, detailKey: .statusGoodDetail,
                     detailArgument: nil, action: nil)
    }
}

/// The first page of the Sanity window, laid out like a native inspector:
/// a one-line verdict, a strip of four readings, the recent activity, the
/// apps responsible, and the technical details in plain label/value rows.
/// No cards; whitespace and a few hairlines carry the structure. While the
/// page is visible it registers as a full monitor surface, so sampling stops
/// as soon as the person navigates away.
struct DashboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var alertHistory = MonitorAlertHistory.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @AppStorage(SettingsPageGuide.gettingStartedDismissedKey) private var gettingStartedDismissed = false
    @AppStorage("dashboardDetailsExpanded") private var detailsExpanded = true
    @Environment(\.colorScheme) private var scheme

    @State private var topCPU: [ProcessUsage] = []
    @State private var topMemory: [ProcessUsage] = []
    @State private var processesLoaded = false
    @State private var processKind: BreakdownKind = .cpu

    private typealias Space = SanityDesign.Space
    private typealias Typo = SanityDesign.Typography

    private var lang: AppLanguage { l10n.language }
    private func t(_ key: GuideKey) -> String { GuideText.t(key, lang) }
    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusHeader
                    .padding(.bottom, Space.m)
                if !gettingStartedDismissed {
                    SetupStrip(onDismiss: { gettingStartedDismissed = true })
                        .padding(.bottom, Space.m)
                }
                SanityHairline()
                vitalsStrip
                    .padding(.vertical, Space.l)
                SanityHairline()
                    .padding(.bottom, Space.xl)

                VStack(alignment: .leading, spacing: 40) {
                    if features.isAvailable(.monitorCPU) || features.isAvailable(.monitorMemory) {
                        activitySection
                    }
                    if features.isAvailable(.monitorCPU) || features.isAvailable(.monitorMemory) {
                        processesSection
                    }
                    if !alertHistory.entries.isEmpty { alertsSection }
                    detailsSection
                }
            }
            // Same column as the grouped forms on every other page, so the
            // window keeps one grid as you move between pages.
            .padding(.horizontal, GroupedFormMetrics.rowInset)
            .frame(maxWidth: GroupedFormMetrics.maxWidth, alignment: .leading)
            .padding(.horizontal, GroupedFormMetrics.outerMargin)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { SystemMonitor.shared.panelDidAppear() }
        .onDisappear { SystemMonitor.shared.panelDidDisappear() }
        .task(id: features.isAvailable(.monitorCPU) || features.isAvailable(.monitorMemory)) {
            await refreshProcessesLoop()
        }
    }

    // MARK: - Status

    private static let computerName: String? =
        SCDynamicStoreCopyComputerName(nil, nil) as String?

    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    private func temp(_ value: Double) -> String { MetricFormat.temperature(value, unit: temperatureUnit) }

    private var mainDisk: DiskDeviceReading? {
        guard let devices = snapshot.disk?.devices else { return nil }
        return devices.first { $0.mountPath == "/" }
            ?? devices.filter(\.isInternal).max { $0.totalBytes < $1.totalBytes }
    }

    private var otherDrives: [DiskDeviceReading] {
        guard let devices = snapshot.disk?.devices, let main = mainDisk else { return [] }
        // Real drives and partitions only: mounted installer disk images
        // are small and would bury the useful rows.
        return devices.filter { $0.id != main.id && $0.totalBytes >= 8_000_000_000 }
    }

    private var status: DashboardStatus {
        DashboardStatus.evaluate(cpu: snapshot.cpuUsage, cpuTemperature: snapshot.cpuTemperature,
                                 pressure: snapshot.memoryPressure,
                                 mainDiskFree: mainDisk?.freeBytes, mainDiskTotal: mainDisk?.totalBytes,
                                 battery: snapshot.power, formatTemperature: temp)
    }

    private var statusHeader: some View {
        let status = status
        let dot: Color = status.level == .good ? PanelMetricColor.green(for: scheme)
                                               : PanelMetricColor.orange(for: scheme)
        let detail = status.detailArgument.map { GuideText.f(status.detailKey, $0, language: lang) }
            ?? t(status.detailKey)
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t(status.title))
                    .font(Typo.lead)
                Text(detail)
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            if status.action == .cleaner,
               FeatureVisibilitySupport.isPageVisible(.cleaner, isAvailable: { features.isAvailable($0) }) {
                Button(t(.openCleaner)) { router.request(FeatureSettingsDestination(.cleaner)) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(GuideText.f(.dashSubtitle, Self.computerName ?? t(.thisMac),
                                 MetricFormat.uptime(Int(ProcessInfo.processInfo.systemUptime)),
                                 language: lang))
                    .font(Typo.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Vitals strip

    private struct Reading: Identifiable {
        let id: String
        let label: String
        let value: String
        let caption: String
        let fraction: Double?
        let severity: SanityDesign.Severity
        var help: String? = nil
    }

    private var readings: [Reading] {
        var items: [Reading] = []
        if features.isAvailable(.monitorCPU) {
            let cpu = snapshot.cpuUsage
            let load: GuideKey = (cpu ?? 0) >= 0.7 ? .loadHeavy : (cpu ?? 0) >= 0.35 ? .loadModerate : .loadLight
            items.append(Reading(id: "cpu", label: t(.processor),
                                 value: cpu.map(MetricFormat.percent) ?? "—",
                                 caption: cpu == nil ? "" : t(load),
                                 fraction: cpu,
                                 severity: (cpu ?? 0) >= 0.95 ? .critical : (cpu ?? 0) >= 0.85 ? .warning : .normal,
                                 help: snapshot.cpuTemperature.map(temp)))
        }
        if features.isAvailable(.monitorMemory) {
            let fraction: Double? = {
                guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return nil }
                return Double(used) / Double(total)
            }()
            let (word, severity): (GuideKey, SanityDesign.Severity) = switch snapshot.memoryPressure {
            case .critical: (.memLow, .critical)
            case .warning: (.memTight, .warning)
            default: (.memRoomy, .normal)
            }
            let amounts = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.map {
                    GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes($0), language: lang)
                }
            }
            items.append(Reading(id: "memory", label: t(.memory),
                                 value: fraction.map(MetricFormat.percent) ?? "—",
                                 caption: fraction == nil ? "" : t(word),
                                 fraction: fraction, severity: severity, help: amounts))
        }
        if features.isAvailable(.monitorDisk), let disk = mainDisk {
            let severity: SanityDesign.Severity = disk.usedFraction >= 0.95 ? .critical
                : disk.usedFraction >= 0.9 ? .warning : .normal
            items.append(Reading(id: "storage", label: t(.storage),
                                 value: MetricFormat.diskBytes(disk.freeBytes),
                                 caption: GuideText.f(.freeOfTotal, MetricFormat.diskBytes(disk.totalBytes),
                                                      language: lang),
                                 fraction: disk.usedFraction, severity: severity))
        }
        if features.isAvailable(.monitorPower), let power = snapshot.power, !power.isEmpty {
            if power.hasBattery, let charge = power.chargePercent {
                let caption: String
                if power.isCharging {
                    caption = t(.charging).capitalizedFirst
                } else if power.externalConnected {
                    caption = t(.onAdapter).capitalizedFirst
                } else if let seconds = power.timeRemainingSeconds, seconds > 0 {
                    caption = GuideText.f(.timeLeft, MetricFormat.uptime(Int(seconds)), language: lang).capitalizedFirst
                } else {
                    caption = ""
                }
                let low = !power.isCharging && !power.externalConnected
                items.append(Reading(id: "battery", label: t(.battery), value: "\(charge)%",
                                     caption: caption, fraction: Double(charge) / 100,
                                     severity: low && charge <= 10 ? .critical : low && charge <= 20 ? .warning : .normal,
                                     help: power.healthPercent.map {
                                         GuideText.f(.health, "\(Int($0.rounded()))%", language: lang)
                                     }))
            } else if let watts = power.systemWatts {
                items.append(Reading(id: "power", label: t(.power), value: MetricFormat.watts(watts),
                                     caption: "", fraction: nil, severity: .normal))
            }
        }
        return items
    }

    @ViewBuilder
    private var vitalsStrip: some View {
        let items = readings
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            SanityHairline(axis: .vertical)
                                .padding(.horizontal, Space.l)
                        }
                        readingView(item)
                            .frame(minWidth: 128, maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .topLeading, horizontalSpacing: Space.l, verticalSpacing: Space.l) {
                    ForEach(stride(from: 0, to: items.count, by: 2).map { $0 }, id: \.self) { row in
                        GridRow {
                            readingView(items[row]).frame(maxWidth: .infinity, alignment: .leading)
                            if row + 1 < items.count {
                                readingView(items[row + 1]).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            }
        }
    }

    private func readingView(_ item: Reading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.label)
                .font(Typo.secondary)
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(Typo.metric)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, Space.xxs)
            Text(item.caption.isEmpty ? " " : item.caption)
                .font(Typo.secondary)
                .foregroundStyle(item.severity.label(scheme))
                .lineLimit(1)
            Group {
                if let fraction = item.fraction {
                    SanityMeter(fraction: fraction, severity: item.severity)
                } else {
                    Color.clear.frame(height: 3)
                }
            }
            .padding(.top, Space.s)
        }
        .help(item.help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue([item.value, item.caption].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    // MARK: - Activity

    private var cpuColor: Color { .accentColor }
    private var memoryColor: Color { Color.secondary }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SanitySectionHeader(t(.activity)) {
                HStack(spacing: Space.m) {
                    if features.isAvailable(.monitorCPU) { legend(t(.processor), cpuColor) }
                    if features.isAvailable(.monitorMemory) { legend(t(.memory), memoryColor) }
                }
            }
            ActivityChart(cpu: features.isAvailable(.monitorCPU) ? snapshot.cpuHistory : [],
                          memory: features.isAvailable(.monitorMemory) ? snapshot.memoryHistory : [],
                          cpuColor: cpuColor, memoryColor: memoryColor)
                .frame(height: 132)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t(.activityCaption))
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 10, height: 2.5)
            Text(title).font(Typo.secondary).foregroundStyle(.secondary)
        }
    }

    // MARK: - What's using your Mac

    @ViewBuilder
    private var processesSection: some View {
        let showCPU = features.isAvailable(.monitorCPU)
        let showMemory = features.isAvailable(.monitorMemory)
        let kind: BreakdownKind = showCPU && showMemory ? processKind : (showCPU ? .cpu : .memory)
        let rows = Array((kind == .cpu ? topCPU : topMemory).prefix(6))
        VStack(alignment: .leading, spacing: Space.s) {
            SanitySectionHeader(t(.whatsUsing)) {
                if showCPU && showMemory {
                    Picker("", selection: $processKind) {
                        Text(t(.processor)).tag(BreakdownKind.cpu)
                        Text(t(.memory)).tag(BreakdownKind.memory)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            if rows.isEmpty {
                Text(processesLoaded ? t(.nothingToShow) : t(.sampling))
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                ProcessTable(rows: rows, kind: kind,
                             appTitle: t(.appColumn),
                             valueTitle: kind == .cpu ? "% " + t(.processor) : t(.memory),
                             quitTitle: t(.quitAppShort))
                    .frame(height: CGFloat(rows.count) * 26 + 30)
            }
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
            guard wantCPU || wantMemory else { return }
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
        VStack(alignment: .leading, spacing: Space.xs) {
            SanitySectionHeader(t(.recentAlerts)) {
                Button(t(.clear)) { alertHistory.clear() }
                    .buttonStyle(.link)
                    .font(Typo.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(alertHistory.entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { SanityHairline() }
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Circle()
                            .fill(PanelMetricColor.orange(for: scheme))
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                            .accessibilityHidden(true)
                        Text(entry.title).font(Typo.body)
                        Text(entry.body).font(Typo.body).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: Space.s)
                        Text(entry.date, style: .relative)
                            .font(Typo.secondary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, Space.xs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Details

    private struct DetailRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if features.isAvailable(.monitorCPU), let cpuTemp = snapshot.cpuTemperature {
            rows.append(DetailRow(id: "cputemp", label: t(.processor), value: temp(cpuTemp)))
        }
        if features.isAvailable(.monitorGPU), let gpu = snapshot.gpuUsage {
            let value = [MetricFormat.percent(gpu), snapshot.gpuTemperature.map(temp)]
                .compactMap { $0 }.joined(separator: "  ·  ")
            rows.append(DetailRow(id: "gpu", label: t(.graphics), value: value))
        }
        if features.isAvailable(.monitorMemory), let used = snapshot.memoryUsed, let total = snapshot.memoryTotal {
            rows.append(DetailRow(id: "mem", label: t(.memory),
                                  value: GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes(total),
                                                     language: lang)))
        }
        if features.isAvailable(.monitorNetwork), let down = snapshot.netDownBytesPerSec,
           let up = snapshot.netUpBytesPerSec {
            rows.append(DetailRow(id: "net", label: t(.network),
                                  value: "↓ \(MetricFormat.bytesPerSec(down))    ↑ \(MetricFormat.bytesPerSec(up))"))
        }
        if features.isAvailable(.monitorDisk), let reading = snapshot.disk {
            let read = reading.uniqueIODevices.compactMap(\.readBytesPerSec).reduce(0, +)
            let write = reading.uniqueIODevices.compactMap(\.writeBytesPerSec).reduce(0, +)
            rows.append(DetailRow(id: "disk", label: t(.diskActivity),
                                  value: GuideText.f(.diskReadWrite, MetricFormat.bytesPerSec(read),
                                                     MetricFormat.bytesPerSec(write), language: lang)))
        }
        if features.isAvailable(.monitorPower), let power = snapshot.power, power.hasBattery {
            var parts: [String] = []
            if let health = power.healthPercent {
                parts.append(GuideText.f(.health, "\(Int(health.rounded()))%", language: lang).capitalizedFirst)
            }
            if let cycles = power.cycleCount { parts.append("\(cycles) cycles") }
            if let watts = power.systemWatts { parts.append(MetricFormat.watts(watts)) }
            if !parts.isEmpty {
                rows.append(DetailRow(id: "power", label: t(.battery), value: parts.joined(separator: "  ·  ")))
            }
        }
        for drive in otherDrives {
            rows.append(DetailRow(id: "drive-\(drive.id)", label: drive.name,
                                  value: GuideText.f(.freeOf, MetricFormat.diskBytes(drive.freeBytes),
                                                     MetricFormat.diskBytes(drive.totalBytes), language: lang)))
        }
        return rows
    }

    @ViewBuilder
    private var detailsSection: some View {
        let rows = detailRows
        if !rows.isEmpty {
            DisclosureGroup(isExpanded: $detailsExpanded) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.l, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            SanityHairline().gridCellColumns(2)
                        }
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .gridColumnAlignment(.leading)
                            Text(row.value)
                                .monospacedDigit()
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(Typo.body)
                        .padding(.vertical, 7)
                    }
                }
                .padding(.top, Space.xs)
            } label: {
                Text(t(.moreDetails))
                    .font(Typo.section)
                    .foregroundStyle(.primary)
            }
            .disclosureGroupStyle(SanityDisclosureStyle())
        }
    }
}

// MARK: - Components

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Disclosure with the chevron on the leading edge and a full-width hit
/// area, matching Finder's Get Info sections.
private struct SanityDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                              ? nil : .easeOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "expanded" : "collapsed")
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

/// Processor and memory history on one plot with a quiet percentage scale.
private struct ActivityChart: View {
    let cpu: [Double]
    let memory: [Double]
    let cpuColor: Color
    let memoryColor: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: SanityDesign.Space.xs) {
            ZStack {
                VStack(spacing: 0) {
                    SanityHairline()
                    Spacer()
                    SanityHairline().opacity(0.6)
                    Spacer()
                    SanityHairline()
                }
                if memory.count >= 2 {
                    Sparkline(values: memory, color: memoryColor.opacity(0.9), maxValue: 1,
                              fillOpacity: 0.0, lineWidth: 1.5)
                }
                if cpu.count >= 2 {
                    Sparkline(values: cpu, color: cpuColor, maxValue: 1, fillOpacity: 0.12, lineWidth: 1.75)
                }
            }
            VStack(alignment: .leading) {
                Text("100%")
                Spacer()
                Text("50%")
                Spacer()
                Text("0%")
            }
            .font(SanityDesign.Typography.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 34, alignment: .leading)
            .padding(.vertical, -6)
        }
    }
}

/// A native table of the busiest processes. Double-click brings an app to
/// the front; right-click offers Quit for ordinary apps.
private struct ProcessTable: View {
    let rows: [ProcessUsage]
    let kind: BreakdownKind
    let appTitle: String
    let valueTitle: String
    let quitTitle: String
    @State private var selection: ProcessUsage.ID?

    private func value(_ row: ProcessUsage) -> String {
        kind == .cpu ? String(format: "%.1f", row.value) : MetricFormat.bytes(UInt64(max(0, row.value)))
    }

    private static func regularApp(_ pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn(appTitle) { row in
                HStack(spacing: 8) {
                    Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TableColumn(valueTitle) { row in
                Text(value(row))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 96, max: 120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollDisabled(true)
        .contextMenu(forSelectionType: ProcessUsage.ID.self) { ids in
            if let pid = ids.first, let app = Self.regularApp(pid) {
                Button(quitTitle + " " + (app.localizedName ?? "")) { app.terminate() }
            }
        } primaryAction: { ids in
            if let pid = ids.first, let row = rows.first(where: { $0.pid == pid }),
               ProcessUsageService.shared.canActivate(row) {
                ProcessUsageService.shared.activate(row)
            }
        }
    }
}

// MARK: - Setup strip

/// First-run guidance as a single line rather than a card: progress, the
/// next step and its button. The full list sits in a popover. It removes
/// itself once every step is done or the person dismisses it.
private struct SetupStrip: View {
    let onDismiss: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var showingSteps = false
    @AppStorage("dashboardGettingStartedVisited") private var visitedRaw = ""
    @Environment(\.colorScheme) private var scheme

    private func t(_ key: GuideKey) -> String { GuideText.t(key, l10n.language) }
    private var visited: Set<String> { Set(visitedRaw.split(separator: ",").map(String.init)) }
    private func markVisited(_ id: String) {
        visitedRaw = visited.union([id]).sorted().joined(separator: ",")
    }

    private struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let button: String
        let isDone: Bool
        let action: () -> Void
    }

    private var steps: [Step] {
        [
            Step(id: "accessibility", title: t(.gsAccessTitle), detail: t(.gsAccessDetail),
                 button: t(.openSystemSettings), isDone: permissions.accessibility,
                 action: { permissions.requestAccessibility() }),
            Step(id: "features", title: t(.gsFeaturesTitle), detail: t(.gsFeaturesDetail),
                 button: t(.gsFeaturesButton), isDone: visited.contains("features"),
                 action: { markVisited("features"); router.request(FeatureSettingsDestination(.features)) }),
            Step(id: "login", title: t(.gsLoginTitle), detail: t(.gsLoginDetail),
                 button: t(.gsLoginButton), isDone: launchesAtLogin,
                 action: { router.request(FeatureSettingsDestination(.general)) }),
            Step(id: "shortcuts", title: t(.gsShortcutsTitle), detail: t(.gsShortcutsDetail),
                 button: t(.gsShortcutsButton), isDone: visited.contains("shortcuts"),
                 action: { markVisited("shortcuts"); router.request(FeatureSettingsDestination(.shortcuts)) }),
        ]
    }

    var body: some View {
        let steps = steps
        let done = steps.filter(\.isDone).count
        if let next = steps.first(where: { !$0.isDone }) {
            HStack(spacing: SanityDesign.Space.s) {
                Button {
                    showingSteps.toggle()
                } label: {
                    HStack(spacing: 6) {
                        ProgressRing(fraction: Double(done) / Double(steps.count))
                        Text(GuideText.f(.gsProgress, "\(done)", "\(steps.count)", language: l10n.language))
                            .monospacedDigit()
                    }
                    .font(SanityDesign.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t(.allSteps))
                .popover(isPresented: $showingSteps, arrowEdge: .bottom) { stepsPopover(steps) }

                Text(next.title)
                    .font(SanityDesign.Typography.body.weight(.medium))
                    .lineLimit(1)
                    .help(next.detail)
                Spacer(minLength: SanityDesign.Space.s)
                Button(next.button, action: next.action)
                    .controlSize(.small)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t(.hideHelp))
                .accessibilityLabel(t(.hide))
            }
            .padding(.horizontal, SanityDesign.Space.s)
            .padding(.vertical, SanityDesign.Space.xs)
            .background(Color.primary.opacity(scheme == .dark ? 0.06 : 0.04),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onAppear {
                permissions.refresh()
                launchesAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    private func stepsPopover(_ steps: [Step]) -> some View {
        VStack(alignment: .leading, spacing: SanityDesign.Space.s) {
            Text(t(.gettingStarted))
                .font(SanityDesign.Typography.section)
            ForEach(steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: SanityDesign.Space.xs) {
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.isDone ? PanelMetricColor.green(for: scheme) : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(SanityDesign.Typography.body.weight(.medium))
                            .foregroundStyle(step.isDone ? .secondary : .primary)
                        Text(step.detail)
                            .font(SanityDesign.Typography.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !step.isDone {
                            Button(step.button) { showingSteps = false; step.action() }
                                .controlSize(.small)
                                .padding(.top, 2)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(SanityDesign.Space.m)
        .frame(width: 320, alignment: .leading)
    }
}

private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
