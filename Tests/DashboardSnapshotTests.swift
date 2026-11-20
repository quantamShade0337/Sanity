import AppKit
import SwiftUI
import XCTest
@testable import Sanity

/// Renders the Dashboard with live data into PNGs for design review.
/// Skipped unless SANITY_SNAPSHOT_DIR is set (pass it to xcodebuild as
/// TEST_RUNNER_SANITY_SNAPSHOT_DIR=/some/folder).
@MainActor
final class DashboardSnapshotTests: XCTestCase {
    func testRenderDashboard() throws {
        guard let dir = ProcessInfo.processInfo.environment["SANITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set SANITY_SNAPSHOT_DIR to render snapshots")
        }
        for (name, appearance, size) in [
            ("dashboard-light", NSAppearance.Name.aqua, NSSize(width: 820, height: 1100)),
            ("dashboard-dark", NSAppearance.Name.darkAqua, NSSize(width: 820, height: 1100)),
            ("dashboard-narrow", NSAppearance.Name.aqua, NSSize(width: 580, height: 1100)),
        ] {
            try render(DashboardView(), name: name, appearance: appearance, size: size, dir: dir)
        }
    }

    private func render<V: View>(_ view: V, name: String, appearance: NSAppearance.Name,
                                 size: NSSize, dir: String) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        window.orderFrontRegardless()
        // Let the monitor sample and the process lists load.
        RunLoop.main.run(until: Date().addingTimeInterval(7))
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
