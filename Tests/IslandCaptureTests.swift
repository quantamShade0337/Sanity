import AppKit
import SwiftUI
import XCTest
@testable import Sanity

/// Drives the live notch through every compact alert and captures frames at
/// fixed times after each trigger, so the opening animation, live updates,
/// interruptions and the auto-dismiss can be reviewed as contact sheets.
/// Skipped unless SANITY_SNAPSHOT_DIR is set
/// (TEST_RUNNER_SANITY_SNAPSHOT_DIR=/some/folder).
@MainActor
final class IslandCaptureTests: XCTestCase {
    private struct Scenario {
        let name: String
        let steps: [(at: TimeInterval, action: () -> Void)]
    }

    /// Seconds after the trigger at which a frame is captured.
    private let frameTimes: [TimeInterval] = [0.04, 0.12, 0.22, 0.32, 0.42, 0.55, 0.7, 0.9, 1.6, 2.4, 3.2]

    func testCaptureIslandAlerts() throws {
        guard let dir = ProcessInfo.processInfo.environment["SANITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set SANITY_SNAPSHOT_DIR to capture the island")
        }
        let defaults = UserDefaults.standard
        let hudWas = defaults.object(forKey: "hudReplacement")
        let percentWas = defaults.object(forKey: "showClosedNotchHUDPercentage")
        defer {
            restore(hudWas, "hudReplacement")
            restore(percentWas, "showClosedNotchHUDPercentage")
        }
        defaults.set(true, forKey: "hudReplacement")
        defaults.set(false, forKey: "showClosedNotchHUDPercentage")

        // Let the app finish launching and the notch window appear.
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        let window = try XCTUnwrap(notchWindow(), "No notch window found")

        let coordinator = BoringViewCoordinator.shared
        func peek(_ type: SneakContentType, _ value: CGFloat, icon: String = "", label: String = "",
                  duration: TimeInterval = 1.5) -> () -> Void {
            {
                if [.volume, .brightness, .backlight, .mic].contains(type) {
                    // The volume/brightness keys only reach the island once the
                    // system-HUD replacement has Accessibility access, which a
                    // test host lacks. Set the island state the way the key
                    // handler does after that check.
                    withAnimation(.smooth) {
                        var state = coordinator.sneakPeek
                        state.show = true
                        state.type = type
                        state.value = value
                        state.icon = icon
                        state.label = label
                        coordinator.sneakPeek = state
                    }
                } else {
                    coordinator.toggleSneakPeek(status: true, type: type, duration: duration, value: value,
                                                icon: icon, label: label)
                }
            }
        }

        let scenarios: [Scenario] = [
            Scenario(name: "volume", steps: [(0, peek(.volume, 0.55))]),
            Scenario(name: "volume-rapid", steps: [(0, peek(.volume, 0.3)), (0.15, peek(.volume, 0.5)),
                                                   (0.3, peek(.volume, 0.7)), (0.45, peek(.volume, 0.9))]),
            Scenario(name: "mute", steps: [(0, peek(.volume, 0))]),
            Scenario(name: "brightness", steps: [(0, peek(.brightness, 0.8))]),
            Scenario(name: "mic-off", steps: [(0, peek(.mic, 0))]),
            Scenario(name: "keepawake-on", steps: [(0, peek(.event, 1, icon: "cup.and.heat.waves.fill",
                                                            label: "On", duration: 2))]),
            Scenario(name: "copied", steps: [(0, peek(.event, 1, icon: "doc.on.clipboard.fill",
                                                      label: "Copied", duration: 2))]),
            Scenario(name: "airpods", steps: [(0, { NotchIntegration.presentAirPods(glyph: "airpodspro", battery: 0.72) })]),
            Scenario(name: "airpods-low", steps: [(0, { NotchIntegration.presentAirPods(glyph: "airpodsmax", battery: 0.15) })]),
            Scenario(name: "airpods-unknown", steps: [(0, { NotchIntegration.presentAirPods(glyph: "airpods", battery: nil) })]),
            Scenario(name: "interrupt", steps: [(0, peek(.event, 1, icon: "doc.on.clipboard.fill", label: "Copied",
                                                         duration: 2)),
                                                (0.4, { NotchIntegration.presentAirPods(glyph: "airpodspro", battery: 0.5) })]),
            Scenario(name: "volume-then-event", steps: [(0, peek(.volume, 0.4)),
                                                        (0.3, peek(.event, 1, icon: "camera.viewfinder",
                                                                   label: "Saved", duration: 2))]),
            Scenario(name: "event-to-event", steps: [(0, peek(.event, 1, icon: "doc.on.clipboard.fill",
                                                              label: "Copied", duration: 2)),
                                                     (0.6, peek(.event, 1, icon: "camera.viewfinder",
                                                                label: "Saved", duration: 2))]),
        ]

        var rows: [(String, [NSImage])] = []
        for scenario in scenarios {
            // Start each scenario from a closed, idle island.
            coordinator.toggleSneakPeek(status: false, type: .music)
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))

            let start = Date()
            var pending = scenario.steps.sorted { $0.at < $1.at }
            var frames: [NSImage] = []
            for time in frameTimes {
                while let next = pending.first, next.at <= time {
                    let wait = next.at - Date().timeIntervalSince(start)
                    if wait > 0 { RunLoop.main.run(until: Date().addingTimeInterval(wait)) }
                    next.action()
                    pending.removeFirst()
                }
                let wait = time - Date().timeIntervalSince(start)
                if wait > 0 { RunLoop.main.run(until: Date().addingTimeInterval(wait)) }
                frames.append(capture(window))
            }
            rows.append((scenario.name, frames))
        }
        let sheet = contactSheet(rows)
        try XCTUnwrap(sheet).write(to: URL(fileURLWithPath: dir).appendingPathComponent("island-frames.png"))
    }

    // MARK: - Helpers

    private func restore(_ value: Any?, _ key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func notchWindow() -> NSWindow? {
        NSApp.windows.first { window in
            let name = String(describing: type(of: window))
            return name.contains("BoringNotch") && window.isVisible
        } ?? NSApp.windows.first { String(describing: type(of: $0)).contains("BoringNotch") }
    }

    /// The top-centre band of the notch window, where the island lives.
    private func capture(_ window: NSWindow) -> NSImage {
        guard let view = window.contentView else { return NSImage() }
        let bounds = view.bounds
        let width: CGFloat = 520
        let height: CGFloat = 60
        let rect = NSRect(x: bounds.midX - width / 2,
                          y: view.isFlipped ? 0 : bounds.maxY - height,
                          width: width, height: height)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return NSImage() }
        view.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    private func contactSheet(_ rows: [(String, [NSImage])]) -> Data? {
        let cellWidth: CGFloat = 260
        let cellHeight: CGFloat = 30
        let labelWidth: CGFloat = 120
        let header: CGFloat = 18
        let columns = frameTimes.count
        let size = NSSize(width: labelWidth + CGFloat(columns) * cellWidth,
                          height: header + CGFloat(rows.count) * (cellHeight + 6))
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        NSColor(white: 0.82, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        for (column, time) in frameTimes.enumerated() {
            ("\(time)s" as NSString).draw(at: NSPoint(x: labelWidth + CGFloat(column) * cellWidth + 4, y: 3),
                                         withAttributes: attributes)
        }
        for (row, entry) in rows.enumerated() {
            let y = header + CGFloat(row) * (cellHeight + 6)
            (entry.0 as NSString).draw(at: NSPoint(x: 4, y: y + 8), withAttributes: attributes)
            for (column, frame) in entry.1.enumerated() {
                frame.draw(in: NSRect(x: labelWidth + CGFloat(column) * cellWidth, y: y,
                                      width: cellWidth, height: cellHeight),
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
