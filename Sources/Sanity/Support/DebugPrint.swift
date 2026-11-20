// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

/// Sanity's `print`: shadows `Swift.print` for the whole module so the many
/// diagnostic prints (most inherited from Boring Notch) only write to the
/// console in Debug builds. Release builds stay silent. `print(_:to:)` with
/// an explicit stream still resolves to the standard library.
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
#endif
}
