// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import Combine
import Foundation

/// The last few monitor alerts Sanity actually sent, so the Dashboard can
/// show what happened while nobody was looking. Kept small and local.
final class MonitorAlertHistory: ObservableObject {
    static let shared = MonitorAlertHistory()

    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let body: String
    }

    static let capacity = 30
    static let defaultsKey = "monitorAlertHistory"

    @Published private(set) var entries: [Entry] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func record(title: String, body: String, at date: Date = Date()) {
        let entry = Entry(id: UUID(), date: date, title: title, body: body)
        let apply = { [weak self] in
            guard let self else { return }
            entries = Self.appending(entry, to: entries)
            save()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Newest first, capped at `capacity`.
    static func appending(_ entry: Entry, to entries: [Entry]) -> [Entry] {
        Array(([entry] + entries).prefix(capacity))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
