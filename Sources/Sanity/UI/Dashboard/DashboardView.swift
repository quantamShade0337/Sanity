// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI
import SystemConfiguration

/// The parts of the Dashboard a person can switch off.
enum DashboardCard: String, CaseIterable, Identifiable {
    case vitals, activity, processes, alerts, details
    var id: String { rawValue }

    static let hiddenKey = "dashboardHiddenCards.v2"

    static func decodeHidden(_ raw: String) -> Set<DashboardCard> {
        Set(raw.split(separator: ",").compactMap { DashboardCard(rawValue: String($0)) })
    }

    static func encodeHidden(_ cards: Set<DashboardCard>) -> String {
        cards.map(\.rawValue).sorted().joined(separator: ",")
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .vitals:
            return [GuideKey.processor, .memory, .storage, .battery]
                .map { GuideText.t($0, language) }.joined(separator: ", ")
        case .activity: return GuideText.t(.activity, language)
        case .processes: return GuideText.t(.whatsUsing, language)
        case .alerts: return GuideText.t(.recentAlerts, language)
        case .details: return GuideText.t(.moreDetails, language)
        }
    }
}

/// Spacing and type steps for the Dashboard, on an 8-point grid.
private enum DS {
    static let page: CGFloat = 32
    static let section: CGFloat = 32
    static let card: CGFloat = 20
    static let gap: CGFloat = 16
    static let radius: CGFloat = 14
    static let maxWidth: CGFloat = 880

    /// A neutral surface that reads on both the light and dark window
    /// background without borders.
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
    }
}

/// What the Dashboard says at the top: one plain-language verdict about the Mac.
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

/// The first page of the Sanity window. It answers "is my Mac OK?" in one
/// sentence, shows four numbers anyone understands, and keeps the technical
/// readings one click away. It registers as a full monitor surface while
/// visible, so the samplers only run while the page is on screen.
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
    @AppStorage("dashboardDetailsExpanded") private var detailsExpanded = false
    @Environment(\.colorScheme) private var scheme

    @State private var topCPU: [ProcessUsage] = []
    @State private var topMemory: [ProcessUsage] = []
    @State private var processesLoaded = false
    @State private var processKind: BreakdownKind = .cpu

    private var lang: AppLanguage { l10n.language }
    private func t(_ key: GuideKey) -> String { GuideText.t(key, lang) }
    private var hidden: Set<DashboardCard> { DashboardCard.decodeHidden(hiddenCardsRaw) }
    private func shows(_ card: DashboardCard) -> Bool { !hidden.contains(card) }
    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.section) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusBanner
                }
                if !gettingStartedDismissed {
                    GettingStartedCard(onDismiss: { gettingStartedDismissed = true })
                }
                if shows(.vitals) { vitals }
                if shows(.activity), features.isAvailable(.monitorCPU) || features.isAvailable(.monitorMemory) {
                    activitySection
                }
                if shows(.processes) { processesSection }
                if shows(.alerts), !alertHistory.entries.isEmpty { alertsSection }
                if shows(.details) { detailsSection }
            }
            .padding(.horizontal, DS.page)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: DS.maxWidth, alignment: .leading)
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(.dashTitle))
                    .font(.system(size: 26, weight: .bold))
                Text(GuideText.f(.dashSubtitle,
                                 Self.computerName ?? t(.thisMac),
                                 MetricFormat.uptime(Int(ProcessInfo.processInfo.systemUptime)),
                                 language: lang))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            optionsMenu
        }
    }

    private var optionsMenu: some View {
        Menu {
            Section(t(.showOnDashboard)) {
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
            Divider()
            if gettingStartedDismissed {
                Button(t(.gettingStarted)) { gettingStartedDismissed = false }
            }
            Button(t(.monitorSettings)) { router.request(FeatureSettingsDestination(.monitor)) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(t(.moreOptions))
        .accessibilityLabel(t(.moreOptions))
    }

    // MARK: - Status

    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    private func temp(_ value: Double) -> String { MetricFormat.temperature(value, unit: temperatureUnit) }

    private var mainDisk: DiskDeviceReading? {
        guard let devices = snapshot.disk?.devices else { return nil }
        return devices.first { $0.mountPath == "/" }
            ?? devices.filter(\.isInternal).max { $0.totalBytes < $1.totalBytes }
    }

    private var otherDrives: [DiskDeviceReading] {
        guard let devices = snapshot.disk?.devices, let main = mainDisk else { return [] }
        return devices.filter { $0.id != main.id }
    }

    private var status: DashboardStatus {
        DashboardStatus.evaluate(cpu: snapshot.cpuUsage, cpuTemperature: snapshot.cpuTemperature,
                                 pressure: snapshot.memoryPressure,
                                 mainDiskFree: mainDisk?.freeBytes, mainDiskTotal: mainDisk?.totalBytes,
                                 battery: snapshot.power, formatTemperature: temp)
    }

    private var statusBanner: some View {
        let status = status
        let tint: Color = status.level == .good ? PanelMetricColor.green(for: scheme) : PanelMetricColor.orange(for: scheme)
        let detail = status.detailArgument.map { GuideText.f(status.detailKey, $0, language: lang) } ?? t(status.detailKey)
        return HStack(spacing: 16) {
            Image(systemName: status.level == .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(t(status.title))
                    .font(.system(size: 17, weight: .semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if status.action == .cleaner,
               FeatureVisibilitySupport.isPageVisible(.cleaner, isAvailable: { features.isAvailable($0) }) {
                Button(t(.openCleaner)) { router.request(FeatureSettingsDestination(.cleaner)) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(DS.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(scheme == .dark ? 0.14 : 0.09),
                    in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Vitals

    private struct Vital: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        let caption: String
        let fraction: Double?
        let warn: Bool
        var help: String? = nil
    }

    private var vitalItems: [Vital] {
        var items: [Vital] = []
        if features.isAvailable(.monitorCPU) {
            let cpu = snapshot.cpuUsage
            let load: GuideKey = (cpu ?? 0) >= 0.7 ? .loadHeavy : (cpu ?? 0) >= 0.35 ? .loadModerate : .loadLight
            items.append(Vital(id: "cpu", icon: "cpu", label: t(.processor),
                               value: cpu.map(MetricFormat.percent) ?? "—",
                               caption: cpu == nil ? " " : t(load),
                               fraction: cpu, warn: (cpu ?? 0) >= 0.85,
                               help: snapshot.cpuTemperature.map(temp)))
        }
        if features.isAvailable(.monitorMemory) {
            let fraction: Double? = {
                guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return nil }
                return Double(used) / Double(total)
            }()
            let word: GuideKey = switch snapshot.memoryPressure {
            case .critical: .memLow
            case .warning: .memTight
            default: .memRoomy
            }
            let amounts = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.map {
                    GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes($0), language: lang)
                }
            }
            items.append(Vital(id: "memory", icon: "memorychip", label: t(.memory),
                               value: fraction.map(MetricFormat.percent) ?? "—",
                               caption: fraction == nil ? " " : t(word),
                               fraction: fraction,
                               warn: snapshot.memoryPressure == .warning || snapshot.memoryPressure == .critical,
                               help: amounts))
        }
        if features.isAvailable(.monitorDisk), let disk = mainDisk {
            items.append(Vital(id: "storage", icon: "internaldrive", label: t(.storage),
                               value: MetricFormat.diskBytes(disk.freeBytes),
                               caption: t(.free),
                               fraction: disk.usedFraction, warn: disk.usedFraction >= 0.92,
                               help: GuideText.f(.freeOf, MetricFormat.diskBytes(disk.freeBytes),
                                                 MetricFormat.diskBytes(disk.totalBytes), language: lang)))
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
                    caption = " "
                }
                items.append(Vital(id: "battery", icon: batteryIcon(power), label: t(.battery),
                                   value: "\(charge)%", caption: caption,
                                   fraction: Double(charge) / 100,
                                   warn: charge <= 15 && !power.isCharging,
                                   help: power.healthPercent.map {
                                       GuideText.f(.health, "\(Int($0.rounded()))%", language: lang)
                                   }))
            } else if let watts = power.systemWatts {
                items.append(Vital(id: "power", icon: "bolt", label: t(.power),
                                   value: MetricFormat.watts(watts), caption: " ",
                                   fraction: nil, warn: false))
            }
        }
        return items
    }

    @ViewBuilder
    private var vitals: some View {
        let items = vitalItems
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: DS.gap)],
                      alignment: .leading, spacing: DS.gap) {
                ForEach(items) { item in
                    VitalTile(icon: item.icon, label: item.label, value: item.value,
                              caption: item.caption, fraction: item.fraction, warn: item.warn)
                        .help(item.help ?? "")
                }
            }
        }
    }

    private func batteryIcon(_ power: PowerReading) -> String {
        if power.isCharging { return "battery.100percent.bolt" }
        switch power.chargePercent ?? 100 {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: - Activity

    private var cpuColor: Color { .accentColor }
    private var memoryColor: Color { PanelMetricColor.pink(for: scheme) }

    private var activitySection: some View {
        DashboardSection(title: t(.activity), subtitle: t(.activityCaption)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    if features.isAvailable(.monitorCPU) { legend(t(.processor), cpuColor) }
                    if features.isAvailable(.monitorMemory) { legend(t(.memory), memoryColor) }
                }
                ZStack {
                    VStack(spacing: 0) {
                        Divider().opacity(0.5)
                        Spacer()
                        Divider().opacity(0.5)
                        Spacer()
                        Divider().opacity(0.8)
                    }
                    if features.isAvailable(.monitorMemory) {
                        Sparkline(values: snapshot.memoryHistory, color: memoryColor, maxValue: 1,
                                  fillOpacity: 0.10, lineWidth: 2)
                    }
                    if features.isAvailable(.monitorCPU) {
                        Sparkline(values: snapshot.cpuHistory, color: cpuColor, maxValue: 1,
                                  fillOpacity: 0.16, lineWidth: 2)
                    }
                }
                .frame(height: 120)
                .accessibilityHidden(true)
            }
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - What's using your Mac

    @ViewBuilder
    private var processesSection: some View {
        let showCPU = features.isAvailable(.monitorCPU)
        let showMemory = features.isAvailable(.monitorMemory)
        if showCPU || showMemory {
            let kind: BreakdownKind = showCPU && showMemory ? processKind : (showCPU ? .cpu : .memory)
            let rows = Array((kind == .cpu ? topCPU : topMemory).prefix(5))
            DashboardSection(title: t(.whatsUsing), accessory: {
                if showCPU && showMemory {
                    Picker("", selection: $processKind) {
                        Text(t(.processor)).tag(BreakdownKind.cpu)
                        Text(t(.memory)).tag(BreakdownKind.memory)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }) {
                if rows.isEmpty {
                    Text(processesLoaded ? t(.nothingToShow) : t(.sampling))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().padding(.leading, 34) }
                            ProcessRow(row: row,
                                       value: kind == .cpu ? String(format: "%.1f%%", row.value)
                                                           : MetricFormat.bytes(UInt64(max(0, row.value))),
                                       quitTitle: t(.quitAppShort),
                                       quitHelp: { GuideText.f(.quitApp, $0, language: lang) + ". " + t(.quitHelp) })
                        }
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
            let wantCPU = features.isAvailable(.monitorCPU)
            let wantMemory = features.isAvailable(.monitorMemory)
            let rows = await Task.detached(priority: .utility) { () -> ([ProcessUsage], [ProcessUsage]) in
                let service = ProcessUsageService.shared
                let cpu = wantCPU ? service.top(.cpu, limit: 5, sampleInterval: interval, cpuPercentage: cpuPercent) : []
                let memory = wantMemory ? service.top(.memory, limit: 5) : []
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
        DashboardSection(title: t(.recentAlerts), accessory: {
            Button(t(.clear)) { alertHistory.clear() }
                .buttonStyle(.borderless)
        }) {
            VStack(spacing: 0) {
                ForEach(Array(alertHistory.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 30) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(PanelMetricColor.orange(for: scheme))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).fontWeight(.medium)
                            Text(entry.body).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, style: .relative)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - More details

    private struct DetailRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if features.isAvailable(.monitorGPU), let gpu = snapshot.gpuUsage {
            let value = [MetricFormat.percent(gpu), snapshot.gpuTemperature.map(temp)]
                .compactMap { $0 }.joined(separator: " · ")
            rows.append(DetailRow(id: "gpu", label: t(.graphics), value: value))
        }
        if features.isAvailable(.monitorCPU), let cpuTemp = snapshot.cpuTemperature {
            rows.append(DetailRow(id: "cputemp", label: t(.processor), value: temp(cpuTemp)))
        }
        if features.isAvailable(.monitorMemory), let used = snapshot.memoryUsed, let total = snapshot.memoryTotal {
            rows.append(DetailRow(id: "mem", label: t(.memory),
                                  value: GuideText.f(.amountOf, MetricFormat.bytes(used), MetricFormat.bytes(total),
                                                     language: lang)))
        }
        if features.isAvailable(.monitorNetwork), let down = snapshot.netDownBytesPerSec,
           let up = snapshot.netUpBytesPerSec {
            rows.append(DetailRow(id: "net", label: t(.network),
                                  value: "↓ \(MetricFormat.bytesPerSec(down))   ↑ \(MetricFormat.bytesPerSec(up))"))
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
                parts.append(GuideText.f(.health, "\(Int(health.rounded()))%", language: lang))
            }
            if let watts = power.systemWatts { parts.append(MetricFormat.watts(watts)) }
            if !parts.isEmpty {
                rows.append(DetailRow(id: "power", label: t(.battery), value: parts.joined(separator: " · ")))
            }
        }
        for drive in otherDrives {
            rows.append(DetailRow(id: "drive-\(drive.id)", label: drive.name,
                                  value: GuideText.f(.freeOf, MetricFormat.diskBytes(drive.freeBytes),
                                                     MetricFormat.diskBytes(drive.totalBytes), language: lang)))
        }
        return rows
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.2)) {
                    detailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(detailsExpanded ? 90 : 0))
                    Text(t(.moreDetails))
                        .font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(detailsExpanded ? "expanded" : "collapsed")

            if detailsExpanded {
                let rows = detailRows
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(row.value)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .font(.callout)
                    }
                }
                .padding(DS.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.cardFill(scheme),
                            in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            }
        }
    }
}

// MARK: - Building blocks

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct DashboardSection<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    init(title: String, subtitle: String? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                accessory
            }
            content
                .padding(.horizontal, DS.card)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.cardFill(scheme),
                            in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }
}

/// One of the four headline numbers: a quiet label, a big value, a plain
/// word that says whether the value is fine, and a thin gauge.
private struct VitalTile: View {
    let icon: String
    let label: String
    let value: String
    let caption: String
    let fraction: Double?
    let warn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(label, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 10)
            Text(caption)
                .font(.callout)
                .foregroundStyle(warn ? PanelMetricColor.orange(for: scheme) : .secondary)
                .lineLimit(1)
                .padding(.top, 2)
            gauge
                .padding(.top, 14)
        }
        .padding(DS.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.cardFill(scheme),
                    in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), \(caption)")
    }

    private var gauge: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let fraction {
                    Capsule()
                        .fill(warn ? PanelMetricColor.orange(for: scheme) : Color.accentColor)
                        .frame(width: max(4, geometry.size.width * min(1, max(0, fraction))))
                }
            }
        }
        .frame(height: 4)
        .opacity(fraction == nil ? 0 : 1)
        .accessibilityHidden(true)
    }
}

/// A process with its usage; a Quit button appears on hover for normal apps.
private struct ProcessRow: View {
    let row: ProcessUsage
    let value: String
    let quitTitle: String
    let quitHelp: (String) -> String
    @State private var hovering = false

    private var app: NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: row.pid),
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            if hovering, let app {
                Button(quitTitle) { app.terminate() }
                    .controlSize(.small)
                    .help(quitHelp(app.localizedName ?? row.name))
            }
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(quitTitle)) { app?.terminate() }
    }
}

// MARK: - Getting started

/// A compact checklist for someone new: progress, the next step with its
/// button, and the full list one click away. It disappears once every step
/// is done.
private struct GettingStartedCard: View {
    let onDismiss: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var showAll = false
    @AppStorage("dashboardGettingStartedVisited") private var visitedRaw = ""
    @Environment(\.colorScheme) private var scheme

    private func t(_ key: GuideKey) -> String { GuideText.t(key, l10n.language) }
    private var visited: Set<String> { Set(visitedRaw.split(separator: ",").map(String.init)) }
    private func markVisited(_ id: String) {
        visitedRaw = (visited.union([id])).sorted().joined(separator: ",")
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
        let doneCount = steps.filter(\.isDone).count
        if let next = steps.first(where: { !$0.isDone }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Text(t(.gettingStarted))
                        .font(.headline)
                    Text(GuideText.f(.gsProgress, "\(doneCount)", "\(steps.count)", language: l10n.language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(doneCount), total: Double(steps.count))
                        .progressViewStyle(.linear)
                        .frame(width: 96)
                        .accessibilityHidden(true)
                    Spacer()
                    Button(t(.hide), action: onDismiss)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(t(.hideHelp))
                }

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(t(.nextStep)): \(next.title)")
                            .font(.system(size: 15, weight: .semibold))
                        Text(next.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Button(next.button, action: next.action)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                if showAll {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(steps) { step in
                            HStack(spacing: 10) {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.isDone ? PanelMetricColor.green(for: scheme) : .secondary)
                                    .accessibilityHidden(true)
                                Button(step.title, action: step.action)
                                    .buttonStyle(.link)
                                    .foregroundStyle(step.isDone ? .secondary : .primary)
                                    .disabled(step.isDone)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(step.isDone ? t(.done) : "")
                        }
                    }
                    .padding(.top, 2)
                }

                Button {
                    showAll.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showAll ? 90 : 0))
                        Text(t(.allSteps))
                    }
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showAll ? "expanded" : "collapsed")
            }
            .padding(DS.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.cardFill(scheme),
                        in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .onAppear {
                permissions.refresh()
                launchesAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }
}
