// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import SwiftUI

/// Sanity's notch alerts in the iPhone Dynamic Island's compact
/// presentation: the island keeps its height and widens sideways, with one
/// glyph leading the camera and one short word trailing it. Both sides get
/// the same width so the camera stays centred, exactly like Silent mode,
/// a Focus turning on, or AirPods connecting on iPhone.
struct SanityEventCompact: View {
    let icon: String
    let label: String
    /// Dimmed for "off" states, as iPhone does for Silent off / Focus off.
    let isActive: Bool
    let notchWidth: CGFloat
    let height: CGFloat

    /// Compact leading/trailing regions are narrow on iPhone; long text
    /// (a device name) truncates rather than stretching the island.
    private let sideWidth: CGFloat = 72

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: sideWidth, height: height, alignment: .leading)
                .padding(.leading, 14)

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth - 20, height: height)

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: sideWidth, height: height, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
