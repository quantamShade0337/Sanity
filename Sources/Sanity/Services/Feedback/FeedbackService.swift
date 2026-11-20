// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 Ethan Soh

import Foundation

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature

    /// A new GitHub issue on Sanity's repository, labelled by kind. Feedback
    /// used to be posted to Vorssaint's server; Sanity has none of its own,
    /// and issues are public, so nothing is sent without the person seeing it.
    var issueURL: URL {
        var components = URLComponents(url: AppInfo.issuesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "labels", value: self == .bug ? "bug" : "enhancement")]
        return components?.url ?? AppInfo.issuesURL
    }
}
