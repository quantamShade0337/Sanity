// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanControlIdentifiers {
    /// The Apple Developer Team ID that signs both the app and the root fan
    /// helper. The helper only talks to an app signed by this team, so fan
    /// control needs a Developer ID release. `nil` (an ad-hoc build) leaves
    /// the feature unavailable, and the requirements below then match no
    /// signature at all.
    static let teamID: String? = nil
    static var isConfigured: Bool { teamID != nil }
    private static var requiredTeam: String { teamID ?? "UNCONFIGURED" }

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.ethansoh.Sanity.dev"
    #else
    static let appBundleID = "com.ethansoh.Sanity"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    static let appCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(requiredTeam)\" and identifier \"\(appBundleID)\""
    static let helperCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(requiredTeam)\" and identifier \"\(helperID)\""
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
