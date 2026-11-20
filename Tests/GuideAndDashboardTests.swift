import XCTest
@testable import Sanity

/// Covers the Dashboard, the beginner guide and their translations.
final class GuideStringsTests: XCTestCase {
    func testEveryLanguageHasEveryKey() {
        for language in AppLanguage.allCases {
            let table = GuideText.table(language)
            let missing = GuideKey.allCases.filter { table[$0]?.isEmpty ?? true }
            XCTAssertTrue(missing.isEmpty, "\(language.rawValue) is missing \(missing.map(\.rawValue))")
        }
    }

    func testTranslationsKeepTheSameFormatSlots() {
        func slots(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }
        for language in AppLanguage.allCases {
            for key in GuideKey.allCases {
                let english = GuideText.t(key, .enUS)
                let local = GuideText.t(key, language)
                XCTAssertEqual(slots(local), slots(english),
                               "\(language.rawValue).\(key.rawValue) has the wrong number of %@ slots")
                XCTAssertFalse(local.contains("%d") || local.contains("%s"),
                               "\(language.rawValue).\(key.rawValue) must only use %@")
            }
        }
    }

    func testFormattingFillsArguments() {
        XCTAssertEqual(GuideText.f(.showAllPages, "20", language: .enUS), "Show all pages (20 more)")
        XCTAssertEqual(GuideText.f(.freeOf, "10 GB", "500 GB", language: .enUS), "10 GB free of 500 GB")
    }

    func testFallsBackToEnglishWhenAKeyIsMissing() {
        // zh-HK is built from zh-TW plus overrides, so it must still be complete.
        XCTAssertEqual(GuideText.table(.zhHK).count, GuideKey.allCases.count)
    }
}

final class SettingsPageGuideTests: XCTestCase {
    /// Pages that intentionally have no summary header.
    private let headerless: Set<SettingsPage> = [.dashboard, .notch, .about, .releaseNotes, .credits]

    func testEveryOtherPageHasASummary() {
        for page in SettingsPage.allCases where !headerless.contains(page) {
            XCTAssertNotNil(SettingsPageGuide.summary(for: page, language: .enUS), "\(page) has no summary")
        }
        for page in headerless {
            XCTAssertNil(SettingsPageGuide.summaryKey(for: page))
        }
    }

    func testSummaryKeysAreUnique() {
        let keys = SettingsPage.allCases.compactMap(SettingsPageGuide.summaryKey(for:))
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testDashboardIsAlwaysVisible() {
        XCTAssertTrue(FeatureVisibilitySupport.features(for: .dashboard).isEmpty)
        XCTAssertTrue(FeatureVisibilitySupport.isPageVisible(.dashboard) { _ in false })
    }
}

final class DashboardStatusTests: XCTestCase {
    private func evaluate(cpu: Double? = 0.2, temp: Double? = 50, pressure: MemoryPressure = .normal,
                          free: UInt64? = 500_000_000_000, total: UInt64? = 1_000_000_000_000,
                          battery: PowerReading? = nil) -> DashboardStatus {
        DashboardStatus.evaluate(cpu: cpu, cpuTemperature: temp, pressure: pressure,
                                 mainDiskFree: free, mainDiskTotal: total, battery: battery,
                                 formatTemperature: { "\($0)" })
    }

    func testHealthyMacIsGood() {
        XCTAssertEqual(evaluate().level, .good)
        XCTAssertEqual(evaluate().title, .statusGood)
    }

    func testAlmostFullDiskOffersTheCleaner() {
        let status = evaluate(free: 5_000_000_000)
        XCTAssertEqual(status.title, .statusDisk)
        XCTAssertEqual(status.action, .cleaner)
    }

    func testWorstProblemWins() {
        // A full disk outranks a busy processor and memory pressure.
        XCTAssertEqual(evaluate(cpu: 0.95, pressure: .warning, free: 1_000_000_000).title, .statusDisk)
        XCTAssertEqual(evaluate(cpu: 0.95, pressure: .warning).title, .statusMemory)
        XCTAssertEqual(evaluate(cpu: 0.95).title, .statusBusy)
        XCTAssertEqual(evaluate(temp: 99).title, .statusHot)
    }

    func testLowBatteryOnlyWhenUnplugged() {
        var battery = PowerReading()
        battery.hasBattery = true
        battery.chargePercent = 10
        XCTAssertEqual(evaluate(battery: battery).title, .statusBattery)
        battery.isCharging = true
        XCTAssertEqual(evaluate(battery: battery).title, .statusGood)
    }
}

final class MonitorAlertHistoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SanityTests.MonitorAlertHistory"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNewestFirstAndCapped() {
        var entries: [MonitorAlertHistory.Entry] = []
        for index in 0..<(MonitorAlertHistory.capacity + 5) {
            let entry = MonitorAlertHistory.Entry(id: UUID(), date: Date(timeIntervalSince1970: Double(index)),
                                                  title: "t\(index)", body: "")
            entries = MonitorAlertHistory.appending(entry, to: entries)
        }
        XCTAssertEqual(entries.count, MonitorAlertHistory.capacity)
        XCTAssertEqual(entries.first?.title, "t\(MonitorAlertHistory.capacity + 4)")
    }

    func testRecordPersistsAndClearRemoves() {
        let history = MonitorAlertHistory(defaults: defaults)
        history.record(title: "CPU is hot", body: "92 °C")
        XCTAssertEqual(history.entries.first?.title, "CPU is hot")

        let reloaded = MonitorAlertHistory(defaults: defaults)
        XCTAssertEqual(reloaded.entries.map(\.title), ["CPU is hot"])

        reloaded.clear()
        XCTAssertTrue(MonitorAlertHistory(defaults: defaults).entries.isEmpty)
    }
}

@MainActor
final class NotchAndPanelTests: XCTestCase {
    func testNotchEventDefaults() {
        let defaults = UserDefaults(suiteName: "SanityTests.NotchEvents")!
        defaults.removePersistentDomain(forName: "SanityTests.NotchEvents")
        XCTAssertTrue(NotchSanityEvent.keepAwake.isEnabled(defaults))
        XCTAssertTrue(NotchSanityEvent.capture.isEnabled(defaults))
        XCTAssertTrue(NotchSanityEvent.output.isEnabled(defaults))
        XCTAssertFalse(NotchSanityEvent.copied.isEnabled(defaults), "Copy alerts are opt-in")

        defaults.set(true, forKey: NotchSanityEvent.copied.defaultsKey)
        XCTAssertTrue(NotchSanityEvent.copied.isEnabled(defaults))
        defaults.removePersistentDomain(forName: "SanityTests.NotchEvents")
    }

    func testNotchEventKeysAreDistinct() {
        let keys = NotchSanityEvent.allCases.map(\.defaultsKey)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testSimplePanelKeepsSoundKeepAwakeAndSystem() {
        XCTAssertEqual(PanelLayout.simplePresetSections, [.mixer, .keepAwake, .system])
        XCTAssertTrue(PanelLayout.simplePresetSections.isSubset(of: Set(PanelSectionID.allCases)))
    }
}

final class MetricFormatTests: XCTestCase {
    func testPercentClampsAndRounds() {
        XCTAssertEqual(MetricFormat.percent(0.456), "46%")
        XCTAssertEqual(MetricFormat.percent(-1), "0%")
        XCTAssertEqual(MetricFormat.percent(2), "100%")
    }

    func testUptime() {
        XCTAssertEqual(MetricFormat.uptime(59), "0min")
        XCTAssertEqual(MetricFormat.uptime(3_660), "1h 1min")
        XCTAssertEqual(MetricFormat.uptime(90_000), "1d 1h")
    }
}

final class FittedHistoryTests: XCTestCase {
    func testFlatSeriesSitsMidHeightNotAtTheTop() {
        let fitted = DashboardView.fittedHistory([0.76, 0.76, 0.77, 0.76])
        XCTAssertTrue(fitted.allSatisfy { $0 > 0.3 && $0 < 0.7 }, "\(fitted)")
    }

    func testRealChangeUsesTheHeight() {
        let fitted = DashboardView.fittedHistory([0.40, 0.70])
        XCTAssertLessThan(fitted[0], 0.25)
        XCTAssertGreaterThan(fitted[1], 0.75)
    }

    func testStaysInRange() {
        let fitted = DashboardView.fittedHistory([0.0, 1.0, 0.5])
        XCTAssertTrue(fitted.allSatisfy { (0...1).contains($0) })
    }
}
