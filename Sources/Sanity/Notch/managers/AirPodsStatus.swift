// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import Foundation

/// Which AirPods (or Beats) just became the sound output, and how charged
/// they are, for the iPhone-style "AirPods connected" island: the model's
/// glyph left of the camera and a battery ring right of it.
struct AirPodsStatus: Equatable {
    /// SF Symbol for the exact model.
    let glyph: String
    /// The lower earbud's charge, 0...1; nil while macOS hasn't reported it.
    let battery: Double?

    /// Apple Bluetooth product IDs, mapped to the model's SF Symbol.
    static func glyph(productID: Int?, name: String) -> String {
        switch productID {
        case 0x200E, 0x2014, 0x2024, 0x2027: return "airpodspro"          // AirPods Pro (all generations)
        case 0x200A, 0x201F: return "airpodsmax"                           // AirPods Max
        case 0x2013, 0x2019, 0x201B: return "airpods.gen3"                 // AirPods 3rd and 4th generation
        case 0x2002, 0x200F: return "airpods"                              // AirPods 1st and 2nd generation
        default: break
        }
        let lower = name.lowercased()
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("beats") { return "beats.headphones" }
        return "airpods"
    }

    /// Whether an audio output with this name is AirPods or Beats.
    static func looksLikeAirPods(_ outputName: String) -> Bool {
        let lower = outputName.lowercased()
        return lower.contains("airpods") || lower.contains("beats")
    }

    /// Parses `system_profiler SPBluetoothDataType -json` for the connected
    /// device named `outputName` (or, failing that, the only connected
    /// device that reports per-earbud batteries).
    static func parse(systemProfilerJSON data: Data, outputName: String) -> AirPodsStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var candidates: [(name: String, properties: [String: Any])] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    if let properties = value as? [String: Any] { candidates.append((name, properties)) }
                }
            }
        }
        let wanted = normalized(outputName)
        let match = candidates.first { normalized($0.name) == wanted }
            ?? candidates.first { normalized($0.name).contains(wanted) || wanted.contains(normalized($0.name)) }
            ?? {
                let withBuds = candidates.filter { $0.properties["device_batteryLevelLeft"] != nil }
                return withBuds.count == 1 ? withBuds[0] : nil
            }()
        guard let match else { return nil }

        let productID = (match.properties["device_productID"] as? String).flatMap {
            Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16)
        }
        let buds = ["device_batteryLevelLeft", "device_batteryLevelRight"]
            .compactMap { PeripheralBatterySupport.percent(from: match.properties[$0]) }
        let single = ["device_batteryLevelMain", "device_batteryLevel"]
            .lazy.compactMap { PeripheralBatterySupport.percent(from: match.properties[$0]) }.first
        let percent = buds.min() ?? single
        return AirPodsStatus(glyph: glyph(productID: productID, name: match.name),
                             battery: percent.map { Double($0) / 100 })
    }

    /// Reads the current status. Blocking (runs system_profiler), so call it
    /// off the main thread.
    static func read(outputName: String) -> AirPodsStatus? {
        let result = BoundedProcessRunner.run(
            "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"],
            timeout: 4, maxOutputBytes: 4 * 1024 * 1024)
        guard result.status == 0 else { return nil }
        return parse(systemProfilerJSON: result.output, outputName: outputName)
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
