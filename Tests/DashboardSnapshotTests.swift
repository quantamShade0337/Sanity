import AppKit
import SwiftUI
import XCTest
@testable import Sanity

/// Renders Sanity's main screens with live data into PNGs for design review.
/// Skipped unless SANITY_SNAPSHOT_DIR is set (pass it to xcodebuild as
/// TEST_RUNNER_SANITY_SNAPSHOT_DIR=/some/folder). Any preference a scene
/// changes is restored afterwards.
@MainActor
final class DashboardSnapshotTests: XCTestCase {
    private var dir: String!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["SANITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set SANITY_SNAPSHOT_DIR to render snapshots")
        }
        self.dir = dir
    }

    func testRenderScreens() throws {
        let router = SettingsRouter.shared
        let originalPage = router.page
        defer { router.page = originalPage }

        let window = NSSize(width: 1060, height: 760)
        for (name, page, appearance, size) in [
            ("window-dashboard-light", SettingsPage.dashboard, NSAppearance.Name.aqua, window),
            ("window-dashboard-dark", .dashboard, .darkAqua, window),
            ("window-dashboard-min", .dashboard, .aqua, NSSize(width: 780, height: 640)),
            ("window-general", .general, .aqua, window),
            ("window-monitor", .monitor, .aqua, window),
            ("window-clipboard", .clipboard, .darkAqua, window),
            ("window-features", .features, .aqua, window),
            ("window-notch", .notch, .aqua, window),
            ("window-general-min", .general, .aqua, NSSize(width: 780, height: 640)),
            ("window-about", .about, .aqua, window),
            ("window-whatsnew", .releaseNotes, .aqua, window),
            ("window-support", .support, .aqua, window),
            ("window-energy", .energy, .aqua, window),
            ("window-shortcuts", .shortcuts, .aqua, window),
        ] {
            router.page = page
            try render(SettingsView(), name: name, appearance: appearance, size: size, settle: 6)
        }
        let detailsKey = "dashboardDetailsExpanded"
        let detailsWas = UserDefaults.standard.object(forKey: detailsKey)
        defer {
            if let detailsWas { UserDefaults.standard.set(detailsWas, forKey: detailsKey) }
            else { UserDefaults.standard.removeObject(forKey: detailsKey) }
        }
        UserDefaults.standard.set(true, forKey: detailsKey)
        try render(DashboardView(), name: "dashboard-full", appearance: .aqua,
                   size: NSSize(width: 840, height: 1400), settle: 3)
    }

    func testRenderMenuPanel() throws {
        for (name, appearance) in [("panel-light", NSAppearance.Name.aqua), ("panel-dark", .darkAqua)] {
            try render(FocusedMenuBarPanel(), name: name, appearance: appearance,
                       size: NSSize(width: 356, height: 420), settle: 3)
        }
    }

    func testRenderIsland() throws {
        let events: [(String, IslandCompact.Trailing, Bool)] = [
            ("speaker.wave.2.fill", .level(0.55, showsPercentage: false), true),
            ("speaker.slash.fill", .level(0, showsPercentage: false), false),
            ("sun.max.fill", .level(0.8, showsPercentage: true), true),
            ("mic.slash.fill", .text(GuideText.t(.evOff, .enUS)), false),
            ("cup.and.heat.waves.fill", .text(GuideText.t(.on, .enUS)), true),
            ("doc.on.clipboard.fill", .text(GuideText.t(.evCopied, .enUS)), true),
            ("camera.viewfinder", .text(GuideText.t(.evSaved, .enUS)), true),
            ("airpodspro", .batteryRing(0.72), true),
            ("hifispeaker.fill", .text("MacBook Air Speakers"), true),
        ]
        let battery: [(String, String, Color)] = [
            (GuideText.t(.batteryCharging, .enUS), "72%", .green),
            (GuideText.t(.batteryCharged, .enUS), "100%", .green),
            (GuideText.t(.batteryNotCharging, .enUS), "80%", .green),
            (GuideText.t(.batteryLowPower, .enUS), "18%", .yellow),
            (GuideText.t(.batteryLowPower, .ru), "18%", .yellow),
        ]
        let island = VStack(spacing: 14) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                IslandCompact(icon: event.0, trailing: event.1, isActive: event.2,
                              notchWidth: 185, height: 32)
                    .background(Color.black, in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            }
            ForEach(Array(battery.enumerated()), id: \.offset) { _, item in
                IslandCompact(icon: "battery.100percent", trailing: .tintedText(item.1, item.2),
                              leadingText: item.0, notchWidth: 185, height: 32)
                    .background(Color.black, in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            }
        }
        .padding(30)
        .frame(width: 560, height: 740)
        .background(Color(white: 0.85))
        try render(island, name: "island", appearance: .aqua, size: NSSize(width: 560, height: 740), settle: 1)
    }

    func testRenderOnboarding() throws {
        let key = DefaultsKey.onboardingStep
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for step in 0..<3 {
            UserDefaults.standard.set(step, forKey: key)
            try render(OnboardingView(onFinish: {}), name: "onboarding-\(step)", appearance: .aqua,
                       size: NSSize(width: 620, height: 640), settle: 1)
        }
    }

    private func render<V: View>(_ view: V, name: String, appearance: NSAppearance.Name,
                                 size: NSSize, settle: TimeInterval) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap"); return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
