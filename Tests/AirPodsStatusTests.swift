import XCTest
@testable import Sanity

final class AirPodsStatusTests: XCTestCase {
    private func json(_ devices: [String: [String: String]], connected: Bool = true) -> Data {
        let entries = devices.map { [$0.key: $0.value] }
        let controller: [String: Any] = [connected ? "device_connected" : "device_not_connected": entries]
        return try! JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [controller]])
    }

    func testProductIDsMapToTheExactModelGlyph() {
        XCTAssertEqual(AirPodsStatus.glyph(productID: 0x2027, name: "x"), "airpodspro")
        XCTAssertEqual(AirPodsStatus.glyph(productID: 0x2014, name: "x"), "airpodspro")
        XCTAssertEqual(AirPodsStatus.glyph(productID: 0x200A, name: "x"), "airpodsmax")
        XCTAssertEqual(AirPodsStatus.glyph(productID: 0x2013, name: "x"), "airpods.gen3")
        XCTAssertEqual(AirPodsStatus.glyph(productID: 0x200F, name: "x"), "airpods")
        XCTAssertEqual(AirPodsStatus.glyph(productID: nil, name: "Ethan's AirPods Max"), "airpodsmax")
        XCTAssertEqual(AirPodsStatus.glyph(productID: nil, name: "Powerbeats Pro"), "beats.headphones")
    }

    func testParsesTheLowerEarbudFromARealReport() {
        // The shape macOS reports for this Mac's AirPods Pro.
        let data = json(["Ethan’s AirPods Pro": [
            "device_batteryLevelCase": "45%", "device_batteryLevelLeft": "100%",
            "device_batteryLevelRight": "82%", "device_minorType": "Headphones",
            "device_productID": "0x2027",
        ]])
        let status = AirPodsStatus.parse(systemProfilerJSON: data, outputName: "Ethan's AirPods Pro")
        XCTAssertEqual(status?.glyph, "airpodspro")
        XCTAssertEqual(status?.battery ?? -1, 0.82, accuracy: 0.001, "The case must not count")
    }

    func testMissingBatteryGivesGlyphOnly() {
        let data = json(["AirPods": ["device_productID": "0x200F"]])
        let status = AirPodsStatus.parse(systemProfilerJSON: data, outputName: "AirPods")
        XCTAssertEqual(status?.glyph, "airpods")
        XCTAssertNil(status?.battery)
    }

    func testIgnoresDevicesThatAreNotConnected() {
        let data = json(["AirPods Pro": ["device_batteryLevelLeft": "50%", "device_productID": "0x2027"]],
                        connected: false)
        XCTAssertNil(AirPodsStatus.parse(systemProfilerJSON: data, outputName: "AirPods Pro"))
    }

    func testRecognisesAirPodsOutputs() {
        XCTAssertTrue(AirPodsStatus.looksLikeAirPods("Ethan’s AirPods Pro"))
        XCTAssertTrue(AirPodsStatus.looksLikeAirPods("Beats Studio Buds"))
        XCTAssertFalse(AirPodsStatus.looksLikeAirPods("MacBook Air Speakers"))
    }
}

@MainActor
final class IslandSizingTests: XCTestCase {
    private func island(_ icon: String, _ trailing: IslandCompact.Trailing, leadingText: String? = nil) -> IslandCompact {
        IslandCompact(icon: icon, trailing: trailing, leadingText: leadingText, notchWidth: 180, height: 32)
    }

    func testSidesHugTheirContent() {
        let airPods = island("airpodspro", .batteryRing(0.7))
        XCTAssertLessThan(airPods.sideWidth, 30, "AirPods is a glyph and a ring; the island should barely widen")
        XCTAssertEqual(island("speaker.wave.2.fill", .level(0.5, showsPercentage: false)).sideWidth,
                       IslandCompact.levelBarWidth)
        let charging = island("battery.100percent.bolt", .tintedText("80%", .green), leadingText: "Charging")
        XCTAssertEqual(charging.sideWidth, IslandCompact.textWidth("Charging"))
    }

    func testSidesNeverExceedTheCap() {
        let long = island("hifispeaker.fill", .text("A Very Long Speaker Name"))
        XCTAssertLessThanOrEqual(long.sideWidth, IslandCompact.maxSideWidth)
    }

    func testPercentageWidthIsStable() {
        XCTAssertEqual(island("speaker.wave.1.fill", .level(0.05, showsPercentage: true)).sideWidth,
                       island("speaker.wave.3.fill", .level(1, showsPercentage: true)).sideWidth)
    }
}

@MainActor
final class AirPodsConnectionWatcherTests: XCTestCase {
    func testOneConnectionShowsOneAlert() {
        let watcher = AirPodsConnectionWatcher()
        var shown: [String] = []
        watcher.onConnect = { shown.append($0) }
        // Bluetooth connects, then the audio device appears, then sound switches.
        watcher.report("Ethan’s AirPods Pro")
        watcher.report("Ethan's AirPods Pro")
        watcher.report("ethan's airpods pro")
        XCTAssertEqual(shown.count, 1)
        watcher.report("Studio Display Speakers")
        XCTAssertEqual(shown.count, 1, "Only AirPods and Beats get the AirPods alert")
        watcher.report("Beats Studio Buds")
        XCTAssertEqual(shown.count, 2)
    }
}
