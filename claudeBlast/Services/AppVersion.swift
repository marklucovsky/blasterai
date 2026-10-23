// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppVersion.swift
//  claudeBlast
//
//  The version a tester reports, in the form TestFlight shows it.
//

import Foundation

/// "0.9.0 (9)" — the marketing version and build number, read from the bundle.
///
/// A bug report names a build, and the release tag `v0.9.0-9` is how that
/// build is found again (`docs/release-runbook.md`). Testers could only read the
/// number off TestFlight until it was on About & Stats.
///
/// The build number is bumped at the start of the first session after an
/// upload, not at upload time, so a Debug build from main already says which
/// build its changes will ship in.
nonisolated enum AppVersion {
    static var display: String { display(info: Bundle.main.infoDictionary ?? [:]) }

    static func display(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
