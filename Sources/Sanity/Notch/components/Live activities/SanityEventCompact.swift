// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import SwiftUI

/// The one compact presentation every short-lived notch alert uses, modelled
/// on the iPhone Dynamic Island: the island keeps its height and widens
/// sideways, with a glyph leading the camera and one small piece of
/// information trailing it. Both sides get the same width so the camera
/// stays centred. Silent mode, a Focus or AirPods connecting all work this
/// way on iPhone; nothing here drops below the camera or adds decoration.
struct IslandCompact: View {
    enum Trailing: Equatable {
        /// One short word: "On", "Off", "Copied", "Saved", a device name.
        case text(String)
        /// A level from 0 to 1 (volume, brightness), as a short bar, or as
        /// a percentage when the person prefers numbers.
        case level(Double, showsPercentage: Bool)
        /// A battery charge from 0 to 1 as a ring, like AirPods connecting
        /// on iPhone: green, red at 20% or below, no number.
        case batteryRing(Double)
        /// Glyph only (for example AirPods before macOS reports a charge).
        case none
    }

    let icon: String
    let trailing: Trailing
    /// Dimmed for "off" states, as iPhone does for Silent off or Focus off.
    var isActive: Bool = true
    let notchWidth: CGFloat
    let height: CGFloat

    /// Compact regions are narrow on iPhone; long text truncates rather than
    /// stretching the island.
    static let sideWidth: CGFloat = 72
    static let edgeInset: CGFloat = 14

    private var ink: Color { isActive ? .white : .white.opacity(0.55) }

    /// The content fades itself in once the island has (nearly) finished
    /// widening, however the island was opened. Done here rather than as a
    /// transition because opening from closed rebuilds the surrounding
    /// layout, which skips transitions on this view.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.sideWidth, height: height, alignment: .leading)
                .padding(.leading, Self.edgeInset)

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth - 20, height: height)

            trailingView
                .frame(width: Self.sideWidth, height: height, alignment: .trailing)
                .padding(.trailing, Self.edgeInset)
        }
        .frame(height: height)
        .opacity(revealed ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18).delay(0.24)) {
                revealed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .text(let label):
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.tail)
        case .level(let value, let showsPercentage):
            if showsPercentage {
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
            } else {
                IslandLevelBar(value: value)
                    .frame(width: 44, height: 5)
            }
        case .batteryRing(let charge):
            IslandBatteryRing(charge: charge)
                .frame(width: 18, height: 18)
        case .none:
            Color.clear
        }
    }

    private var accessibilityText: String {
        switch trailing {
        case .text(let label): return label
        case .level(let value, _), .batteryRing(let value): return "\(Int((value * 100).rounded()))%"
        case .none: return ""
        }
    }
}

/// A short white level bar on a faint track, like the volume slider in
/// Control Center, sized for the island's trailing region.
private struct IslandLevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: value <= 0.001 ? 0 : max(5, geometry.size.width * min(1, value)))
            }
        }
        .animation(.smooth(duration: 0.18), value: value)
    }
}

/// The iPhone's AirPods battery ring: a thick stroke on a faint track,
/// green when charged, red at 20% or below.
private struct IslandBatteryRing: View {
    let charge: Double

    var body: some View {
        let level = min(1, max(0, charge))
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: level)
                .stroke(level <= 0.2 ? Color.red : Color.green,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.5)
        .animation(.smooth(duration: 0.4), value: level)
    }
}

extension IslandCompact {
    /// Glyphs for the system HUD alerts, matching Control Center's symbols.
    static func glyph(for type: SneakContentType, value: CGFloat, override: String) -> String {
        switch type {
        case .volume:
            if !override.isEmpty { return override }
            if value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .backlight:
            return value < 0.5 ? "light.min" : "light.max"
        case .mic:
            return value > 0 ? "mic.fill" : "mic.slash.fill"
        default:
            return override.isEmpty ? "sparkles" : override
        }
    }
}
