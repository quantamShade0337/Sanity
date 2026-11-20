// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Which per-app breakdown is expanded in the System section.
enum BreakdownKind {
    case cpu, gpu, memory, energy, network

    func processRefreshInterval(configuredMonitorInterval: Int) -> TimeInterval {
        switch self {
        case .cpu, .gpu, .energy:
            return TimeInterval(SanityDefaults.sanitizedMonitorInterval(configuredMonitorInterval))
        case .memory, .network:
            return 4
        }
    }
}

