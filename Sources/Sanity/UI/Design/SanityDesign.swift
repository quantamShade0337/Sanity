// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import SwiftUI

/// Sanity's small design system for the main window. Deliberately short:
/// one spacing scale, a handful of type roles, semantic colours, and the
/// two or three primitives the screens share. Native controls do the rest.
enum SanityDesign {
    // MARK: Spacing (4-point scale)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Type roles

    enum Typography {
        /// The one sentence a page leads with.
        static let lead = Font.system(size: 15, weight: .semibold)
        /// Section titles inside a page (13 pt semibold, the macOS norm).
        static let section = Font.system(size: 13, weight: .semibold)
        /// Headline numbers. Regular weight reads calmer than bold at size.
        static let metric = Font.system(size: 26, weight: .regular).monospacedDigit()
        static let body = Font.system(size: 13)
        static let secondary = Font.system(size: 12)
        static let caption = Font.system(size: 11)
    }

    // MARK: Semantic colour

    /// Severity drives colour; everything healthy stays neutral.
    enum Severity: Equatable {
        case normal, warning, critical

        func tint(_ scheme: ColorScheme) -> Color {
            switch self {
            case .normal: return Color.primary.opacity(scheme == .dark ? 0.55 : 0.45)
            case .warning: return PanelMetricColor.orange(for: scheme)
            case .critical: return PanelMetricColor.red(for: scheme)
            }
        }

        /// Text colour for a short status word next to a value.
        func label(_ scheme: ColorScheme) -> Color {
            self == .normal ? .secondary : tint(scheme)
        }
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.12 : 0.10)
    }
}

/// A thin capacity meter. Neutral when healthy, coloured only when it
/// needs attention.
struct SanityMeter: View {
    let fraction: Double
    var severity: SanityDesign.Severity = .normal
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.07))
                Capsule()
                    .fill(severity.tint(scheme))
                    .frame(width: max(3, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// A section title with an optional trailing accessory, aligned to the
/// page grid. No container: whitespace does the grouping.
struct SanitySectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SanityDesign.Typography.section)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: SanityDesign.Space.s)
            accessory
        }
    }
}

/// A one-pixel rule in the system separator colour.
struct SanityHairline: View {
    var axis: Axis = .horizontal
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(1, displayScale)
        Rectangle()
            .fill(SanityDesign.hairline(scheme))
            .frame(width: axis == .vertical ? thickness : nil,
                   height: axis == .horizontal ? thickness : nil)
            .accessibilityHidden(true)
    }
}
