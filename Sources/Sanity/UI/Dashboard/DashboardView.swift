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

/// Sanity's home screen and the reference for its design language.
///
/// Composition, top to bottom:
/// 1. Identity line: the Sanity mark, this Mac's name, its uptime.
/// 2. The verdict: one display-size sentence. The single focal point.
/// 3. Four readings on one rule-bounded strip. Fast-changing values carry a
///    short history line in Sanity Indigo; capacities carry a bar showing
///    what is left, so the bar always agrees with the number above it.
/// 4. What's using the Mac: apps, with background daemons folded into one row.
/// 5. Recent alerts (only when there are some) and the technical details.
///
/// Separation is hairlines and whitespace only. While visible the page is a
/// full monitor surface; sampling stops when the person navigates away.
struct DashboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var alertHistory = MonitorAlertHistory.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @AppStorage(SettingsPageGuide.gettingStartedDismissedKey) private var gettingStartedDismissed = false
    @AppStorage("dashboardDetailsExpanded") private var detailsExpanded = false
    @AppStorage("dashboardProcessSort") private var processSortRaw = "cpu"
    @Environment(\.colorScheme) private var scheme

    @State private var topCPU: [ProcessUsage] = []
    @State private var topMemory: [ProcessUsage] = []
    @State private var processesLoaded = false

    private typealias Space = SanityDesign.Space
    private typealias Typo = SanityDesign.Typography

    private var lang: AppLanguage { l10n.language }
    private func t(_ key: GuideKey) -> String { GuideText.t(key, lang) }
    private var snapshot: SystemSnapshot { monitor.snapshot }
    private var brand: Color { SanityDesign.brand(scheme) }
    private var showsCPU: Bool { features.isAvailable(.monitorCPU) }
    private var showsMemory: Bool { features.isAvailable(.monitorMemory) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityLine
                    .padding(.bottom, Space.m)
                verdict
                if !gettingStartedDismissed {
                    SetupLine(onDismiss: { gettingStartedDismissed = true })
                        .padding(.top, Space.s)
                }

                readingsStrip
                    .padding(.top, 28)

                if showsCPU || showsMemory {
                    processesSection
                        .padding(.top, 36)
                }
                if !alertHistory.entries.isEmpty {
                    alertsSection
                        .padding(.top, 36)
                }
                detailsSection
                    .padding(.top, 36)
            }
            // Same column as the grouped forms on every other page.
            .padding(.horizontal, GroupedFormMetrics.rowInset)
            .frame(maxWidth: GroupedFormMetrics.maxWidth, alignment: .leading)
            .padding(.horizontal, GroupedFormMetrics.outerMargin)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { SystemMonitor.shared.panelDidAppear() }
        .onDisappear { SystemMonitor.shared.panelDidDisappear() }
        .task(id: showsCPU || showsMemory) { await refreshProcessesLoop() }
    }

    // MARK: - Identity and verdict

    private static let computerName: String? =
        SCDynamicStoreCopyComputerName(nil, nil) as String?

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    /// One duration style everywhere on the page ("4d 3h", "3h 2m").
    private static func duration(_ seconds: TimeInterval) -> String {
        durationFormatter.string(from: max(60, seconds)) ?? MetricFormat.uptime(Int(seconds))
    }

    private var identityLine: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            BrandMark(width: 16, tint: brand)
                .accessibilityHidden(true)
            eyebrow(Self.computerName ?? t(.thisMac))
            Spacer(minLength: Space.m)
            eyebrow(GuideText.f(.dashSubtitle, "", Self.duration(ProcessInfo.processInfo.systemUptime),
                                language: lang)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased(with: Locale.current))
            .font(Typo.eyebrow)
            .tracking(Typo.eyebrowTracking)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    private func temp(_ value: Double) -> String { MetricFormat.temperature(value, unit: temperatureUnit) }

    private var mainDisk: DiskDeviceReading? {
        guard let devices = snapshot.disk?.devices else { return nil }
        return devices.first { $0.mountPath == "/" }
            ?? devices.filter(\.isInternal).max { $0.totalBytes < $1.totalBytes }
    }

    private var otherDrives: [DiskDeviceReading] {
        guard let devices = snapshot.disk?.devices, let main = mainDisk else { return [] }
        // Real drives and partitions only: mounted installer disk images are
        // small and would bury the useful rows.
        return devices.filter { $0.id != main.id && $0.totalBytes >= 8_000_000_000 }
    }

    private var status: DashboardStatus {
        DashboardStatus.evaluate(cpu: snapshot.cpuUsage, cpuTemperature: snapshot.cpuTemperature,
                                 pressure: snapshot.memoryPressure,
                                 mainDiskFree: mainDisk?.freeBytes, mainDiskTotal: mainDisk?.totalBytes,
                                 battery: snapshot.power, formatTemperature: temp)
    }

    private var verdict: some View {
        let status = status
        let tint: Color = status.level == .good ? PanelMetricColor.green(for: scheme)
                                                : PanelMetricColor.orange(for: scheme)
        let detail = status.detailArgument.map { GuideText.f(status.detailKey, $0, language: lang) }
            ?? t(status.detailKey)
        return HStack(alignment: .center, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
                        .accessibilityHidden(true)
                    Text(t(status.title))
                        .font(Typo.display)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail)
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 19)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if status.action == .cleaner,
               FeatureVisibilitySupport.isPageVisible(.cleaner, isAvailable: { features.isAvailable($0) }) {
                Button(t(.openCleaner)) { router.request(FeatureSettingsDestination(.cleaner)) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Readings

    private enum Graphic {
        case history([Double])
        case remaining(Double)
        case none
    }

    private struct Reading: Identifiable {
        let id: String
        let label: String
        let number: String
        let unit: String
        let caption: String
        let graphic: Graphic
        let severity: SanityDesign.Severity
        var help: String? = nil
    }

    /// Splits "552 GB" into ("552", "GB") and "43%" into ("43", "%"), so the
    /// unit can be set smaller than the figure.
    private static func split(_ formatted: String) -> (String, String) {
        if formatted.hasSuffix("%") { return (String(formatted.dropLast()), "%") }
        if let space = formatted.lastIndex(of: " ") {
            return (String(formatted[..<space]), String(formatted[formatted.index(after: space)...]))
        }
        return (formatted, "")
    }

    private var readings: [Reading] {
        var items: [Reading] = []
        if showsCPU {
            let cpu = snapshot.cpuUsage
            let load: GuideKey = (cpu ?? 0) >= 0.7 ? .loadHeavy : (cpu ?? 0) >= 0.35 ? .loadModerate : .loadLight
            let (number, unit) = cpu.map { Self.split(MetricFormat.percent($0)) } ?? ("—", "")
            items.append(Reading(id: "cpu", label: t(.processor), number: number, unit: unit,
                                 caption: cpu == nil ? "" : t(load),
                                 graphic: .history(snapshot.cpuHistory),
                                 severity: (cpu ?? 0) >= 0.95 ? .critical : (cpu ?? 0) >= 0.85 ? .warning : .normal,
                                 help: snapshot.cpuTemperature.map(temp)))
        }
        if showsMemory {
            let fraction: Double? = {
                guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return nil }
                return Double(used) / Double(total)
            }()
            // Caption by pressure, the honest measure: macOS uses spare memory
            // for cache, so a high percentage alone is not a problem.
            let (word, severity): (GuideKey, SanityDesign.Severity) = switch snapshot.memoryPressure {
            case .critical: (.pressureCritical, .critical)
            case .warning: (.pressureWarning, .warning)
            default: (.pressureNormal, .normal)
            }
            let (number, unit) = fraction.map { Self.split(MetricFormat.percent($0)) } ?? ("—", "")
            let amounts = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.map {
                    GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes($0), language: lang)
                }
            }
            items.append(Reading(id: "memory", label: t(.memory), number: number, unit: unit,
                                 caption: fraction == nil ? "" : t(word).capitalizedFirst,
                                 graphic: .history(snapshot.memoryHistory),
                                 severity: severity, help: amounts))
        }
        if features.isAvailable(.monitorDisk), let disk = mainDisk {
            let free = 1 - disk.usedFraction
            let (number, unit) = Self.split(MetricFormat.diskBytes(disk.freeBytes))
            items.append(Reading(id: "storage", label: t(.storage), number: number, unit: unit,
                                 caption: GuideText.f(.freeOfTotal, MetricFormat.diskBytes(disk.totalBytes),
                                                      language: lang).capitalizedFirst,
                                 graphic: .remaining(free),
                                 severity: free <= 0.05 ? .critical : free <= 0.1 ? .warning : .normal))
        }
        if features.isAvailable(.monitorPower), let power = snapshot.power, !power.isEmpty {
            if power.hasBattery, let charge = power.chargePercent {
                let caption: String
                if power.isCharging {
                    caption = t(.charging).capitalizedFirst
                } else if power.externalConnected {
                    caption = t(.onAdapter).capitalizedFirst
                } else if let seconds = power.timeRemainingSeconds, seconds > 0 {
                    caption = GuideText.f(.timeLeft, Self.duration(seconds), language: lang).capitalizedFirst
                } else {
                    caption = ""
                }
                let draining = !power.isCharging && !power.externalConnected
                items.append(Reading(id: "battery", label: t(.battery), number: "\(charge)", unit: "%",
                                     caption: caption, graphic: .remaining(Double(charge) / 100),
                                     severity: draining && charge <= 10 ? .critical
                                         : draining && charge <= 20 ? .warning : .normal,
                                     help: power.healthPercent.map {
                                         GuideText.f(.health, "\(Int($0.rounded()))%", language: lang)
                                     }))
            } else if let watts = power.systemWatts {
                let (number, unit) = Self.split(MetricFormat.watts(watts))
                items.append(Reading(id: "power", label: t(.power), number: number, unit: unit,
                                     caption: "", graphic: .history(snapshot.systemPowerHistory),
                                     severity: .normal))
            }
        }
        return items
    }

    @ViewBuilder
    private var readingsStrip: some View {
        let items = readings
        if !items.isEmpty {
            VStack(spacing: 0) {
                SanityHairline()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                SanityHairline(axis: .vertical)
                                    .padding(.horizontal, Space.l)
                            }
                            // Equal flexible frames, gaps on the dividers:
                            // every column gets the same width.
                            readingView(item)
                                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Grid(alignment: .topLeading, horizontalSpacing: Space.xl, verticalSpacing: Space.l) {
                        ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { row in
                            GridRow {
                                readingView(items[row])
                                if row + 1 < items.count {
                                    readingView(items[row + 1])
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
                SanityHairline()
            }
        }
    }

    private func readingView(_ item: Reading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.label.uppercased(with: Locale.current))
                .font(Typo.eyebrow)
                .tracking(Typo.eyebrowTracking)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.number)
                    .font(Typo.metric)
                Text(item.unit)
                    .font(Typo.metricUnit)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 6)
            Text(item.caption.isEmpty ? " " : item.caption)
                .font(Typo.secondary)
                .foregroundStyle(item.severity.label(scheme))
                .lineLimit(1)
                .padding(.top, 2)
            graphic(item)
                .frame(height: 22)
                .padding(.top, Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue([item.number + item.unit, item.caption].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    @ViewBuilder
    private func graphic(_ item: Reading) -> some View {
        switch item.graphic {
        case .history(let values):
            Sparkline(values: values,
                      color: item.severity == .normal ? brand : item.severity.tint(scheme),
                      maxValue: item.id == "power" ? nil : 1,
                      fillOpacity: 0.14, lineWidth: 1.5, showsZeroBaseline: true)
                .accessibilityHidden(true)
        case .remaining(let fraction):
            VStack {
                Spacer(minLength: 0)
                SanityMeter(fraction: fraction, severity: item.severity)
            }
            .padding(.bottom, 1)
        case .none:
            Color.clear
        }
    }

    // MARK: - What's using your Mac

    private var processSort: BreakdownKind {
        if !showsCPU { return .memory }
        if !showsMemory { return .cpu }
        return processSortRaw == "memory" ? .memory : .cpu
    }

    private struct UsageRow: Identifiable {
        let id: String
        let name: String
        let pid: pid_t?
        let value: Double
        let app: NSRunningApplication?
    }

    /// Ordinary apps first, merged by name (helpers of one app report under
    /// their responsible app's name); everything else becomes one
    /// "Background processes" row so system daemons don't crowd the list.
    private var usageRows: [UsageRow] {
        let source = processSort == .cpu ? topCPU : topMemory
        var apps: [String: UsageRow] = [:]
        var order: [String] = []
        var background = 0.0
        for row in source {
            if let app = NSRunningApplication(processIdentifier: row.pid), app.activationPolicy == .regular {
                let name = app.localizedName ?? row.name
                if let existing = apps[name] {
                    apps[name] = UsageRow(id: name, name: name, pid: existing.pid,
                                          value: existing.value + row.value, app: existing.app)
                } else {
                    apps[name] = UsageRow(id: name, name: name, pid: row.pid, value: row.value, app: app)
                    order.append(name)
                }
            } else {
                background += row.value
            }
        }
        var rows = order.compactMap { apps[$0] }.sorted { $0.value > $1.value }.prefix(5).map { $0 }
        if background > 0 {
            rows.append(UsageRow(id: "background", name: t(.backgroundProcesses), pid: nil,
                                 value: background, app: nil))
        }
        return rows
    }

    private func formatted(_ value: Double) -> String {
        processSort == .cpu ? String(format: "%.1f%%", value) : MetricFormat.bytes(UInt64(max(0, value)))
    }

    private var processesSection: some View {
        let rows = usageRows
        return VStack(alignment: .leading, spacing: Space.xs) {
            SanitySectionHeader(t(.whatsUsing)) {
                if showsCPU && showsMemory {
                    // A borderless menu that reads as part of the label row.
                    Menu {
                        Picker("", selection: Binding(get: { processSort == .memory ? "memory" : "cpu" },
                                                      set: { processSortRaw = $0 })) {
                            Text(t(.processor)).tag("cpu")
                            Text(t(.memory)).tag("memory")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Text(processSort == .cpu ? t(.processor) : t(.memory))
                            .font(Typo.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.visible)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                }
            }
            if rows.isEmpty {
                Text(processesLoaded ? t(.nothingToShow) : t(.sampling))
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SanityHairline().padding(.leading, 30) }
                        UsageRowView(name: row.name, pid: row.pid, value: formatted(row.value),
                                     app: row.app, quitTitle: t(.quitAppShort))
                    }
                }
            }
        }
    }

    /// Refreshes the process lists off the main thread while the page is
    /// visible. The `.task` modifier cancels this loop on disappear.
    private func refreshProcessesLoop() async {
        while !Task.isCancelled {
            let interval = TimeInterval(SanityDefaults.sanitizedMonitorInterval(monitorInterval))
            let cpuPercent = monitor.snapshot.cpuUsage.map { $0 * 100 }
            let wantCPU = showsCPU
            let wantMemory = showsMemory
            guard wantCPU || wantMemory else { return }
            let rows = await Task.detached(priority: .utility) { () -> ([ProcessUsage], [ProcessUsage]) in
                let service = ProcessUsageService.shared
                let cpu = wantCPU ? service.top(.cpu, limit: 16, sampleInterval: interval, cpuPercentage: cpuPercent) : []
                let memory = wantMemory ? service.top(.memory, limit: 16) : []
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
                    if index > 0 { SanityHairline().padding(.leading, 16) }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(PanelMetricColor.orange(for: scheme))
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .accessibilityHidden(true)
                        Text(entry.title).font(Typo.body)
                        Text(entry.body).font(Typo.body).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: Space.s)
                        Text(entry.date, style: .relative)
                            .font(Typo.secondary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 9)
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
        if showsCPU, let cpuTemp = snapshot.cpuTemperature {
            rows.append(DetailRow(id: "cputemp", label: t(.processor), value: temp(cpuTemp)))
        }
        if features.isAvailable(.monitorGPU), let gpu = snapshot.gpuUsage {
            let value = [MetricFormat.percent(gpu), snapshot.gpuTemperature.map(temp)]
                .compactMap { $0 }.joined(separator: "  ·  ")
            rows.append(DetailRow(id: "gpu", label: t(.graphics), value: value))
        }
        if showsMemory, let used = snapshot.memoryUsed, let total = snapshot.memoryTotal {
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
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, Space.xs)
            } label: {
                Text(t(.moreDetails).uppercased(with: Locale.current))
                    .font(Typo.eyebrow)
                    .tracking(Typo.eyebrowTracking)
                    .foregroundStyle(.secondary)
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
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
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

/// One row of "What's using your Mac". Apps can be brought forward with a
/// double-click and quit from the context menu or the hover button.
private struct UsageRowView: View {
    let name: String
    let pid: pid_t?
    let value: String
    let app: NSRunningApplication?
    let quitTitle: String
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let pid {
                    Image(nsImage: ResponsibleProcess.icon(for: pid))
                        .resizable()
                } else {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            Text(name)
                .font(SanityDesign.Typography.body)
                .foregroundStyle(pid == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: SanityDesign.Space.s)
            if hovering, let app {
                Button(quitTitle) { app.terminate() }
                    .controlSize(.small)
            }
            Text(value)
                .font(SanityDesign.Typography.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { app?.activate() }
        .contextMenu {
            if let app {
                Button(quitTitle + " " + name) { app.terminate() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(quitTitle)) { app?.terminate() }
    }
}

// MARK: - Setup line

/// First-run guidance as one quiet line of text, not a box: progress, the
/// next step as a link, the full checklist in a popover. It disappears once
/// every step is done or the person dismisses it.
private struct SetupLine: View {
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
            HStack(spacing: 8) {
                Button {
                    showingSteps.toggle()
                } label: {
                    HStack(spacing: 6) {
                        ProgressRing(fraction: Double(done) / Double(steps.count),
                                     tint: SanityDesign.brand(scheme))
                        Text(GuideText.f(.gsProgress, "\(done)", "\(steps.count)", language: l10n.language))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t(.allSteps))
                .popover(isPresented: $showingSteps, arrowEdge: .bottom) { stepsPopover(steps) }

                Text("·").foregroundStyle(.tertiary)

                Button {
                    next.action()
                } label: {
                    HStack(spacing: 2) {
                        Text(next.title)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(SanityDesign.brand(scheme))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(next.detail)

                Spacer(minLength: SanityDesign.Space.s)

                Button(t(.hide), action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help(t(.hideHelp))
            }
            .font(SanityDesign.Typography.secondary)
            .padding(.leading, 19)
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
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
    }
}
