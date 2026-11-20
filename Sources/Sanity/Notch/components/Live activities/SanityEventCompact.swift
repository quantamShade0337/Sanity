// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import AppKit
import SwiftUI

/// The one compact presentation every short-lived notch alert uses, modelled
/// on the iPhone Dynamic Island: the island keeps its height and widens
/// sideways, with a glyph leading the camera and one small piece of
/// information trailing it. Both sides get the same width so the camera
/// stays centred, and that width is only what the content needs. Silent mode, a Focus or AirPods connecting all work this
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
        /// Short text in a semantic colour, like the charge percentage.
        case tintedText(String, Color)
    }

    let icon: String
    let trailing: Trailing
    /// A word in place of the glyph, for alerts where iPhone leads with text
    /// (Charging, Low Power).
    var leadingText: String? = nil
    /// Dimmed for "off" states, as iPhone does for Silent off or Focus off.
    var isActive: Bool = true
    let notchWidth: CGFloat
    let height: CGFloat

    /// The most a side may take. Each side is otherwise only as wide as the
    /// wider of the two contents, so the island grows just enough to show
    /// them, as on iPhone; text longer than this is replaced by a glyph.
    static let maxSideWidth: CGFloat = 88
    /// Breathing room between the content and the island's rounded ends,
    /// on top of the closed notch's own corner padding.
    static let edgeInset: CGFloat = 4
    /// Extra room on each side of the measured notch so nothing ever sits
    /// under the camera housing. The measured width already includes 4 pt.
    static let cameraClearance: CGFloat = 8
    static let levelBarWidth: CGFloat = 44
    static let ringSize: CGFloat = 18

    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    /// Whether a label fits its side at full size. Text is never clipped or
    /// shrunk: a label that doesn't fit is replaced by a glyph instead.
    static func fits(_ label: String) -> Bool {
        textWidth(label) <= maxSideWidth
    }

    static func textWidth(_ label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: labelFont]).width) + 1
    }

    static func glyphWidth(_ name: String, pointSize: CGFloat = 14, weight: NSFont.Weight = .semibold) -> CGFloat {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return 18 }
        return ceil(image.size.width)
    }

    /// Width of what sits left of the camera.
    var leadingContentWidth: CGFloat {
        if let leadingText, Self.fits(leadingText) { return Self.textWidth(leadingText) }
        return Self.glyphWidth(icon)
    }

    /// Width of what sits right of the camera. Percentages are measured at
    /// "100%" so the island doesn't twitch as the number changes.
    var trailingContentWidth: CGFloat {
        switch trailing {
        case .text(let label):
            return Self.fits(label) ? Self.textWidth(label) : Self.glyphWidth("checkmark", pointSize: 13, weight: .bold)
        case .level(_, let showsPercentage):
            return showsPercentage ? Self.textWidth("100%") : Self.levelBarWidth
        case .batteryRing:
            return Self.ringSize
        case .none:
            return 0
        case .tintedText(let label, _):
            return max(Self.textWidth(label), Self.textWidth("100%"))
        }
    }

    /// Both sides share one width so the camera stays centred: the wider
    /// content's, never more.
    var sideWidth: CGFloat {
        min(Self.maxSideWidth, max(leadingContentWidth, trailingContentWidth, 16))
    }

    private var ink: Color { isActive ? .white : .white.opacity(0.55) }

    /// The content fades itself in once the island has (nearly) finished
    /// widening, however the island was opened. Done here rather than as a
    /// transition because opening from closed rebuilds the surrounding
    /// layout, which skips transitions on this view.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let leadingText, Self.fits(leadingText) {
                    Text(leadingText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: sideWidth, height: height, alignment: .leading)
            .padding(.leading, Self.edgeInset)

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + Self.cameraClearance, height: height)

            trailingView
                .frame(width: sideWidth, height: height, alignment: .trailing)
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
            if Self.fits(label) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                // Too long for the island (a long device name): a checkmark
                // says "done" without clipping a word.
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink)
            }
        case .level(let value, let showsPercentage):
            if showsPercentage {
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
            } else {
                IslandLevelBar(value: value)
                    .frame(width: Self.levelBarWidth, height: 5)
            }
        case .batteryRing(let charge):
            IslandBatteryRing(charge: charge)
                .frame(width: Self.ringSize, height: Self.ringSize)
        case .none:
            Color.clear
        case .tintedText(let label, let color):
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
    }

    private var accessibilityText: String {
        switch trailing {
        case .text(let label), .tintedText(let label, _): return [leadingText, label].compactMap { $0 }.joined(separator: ", ")
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
