// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PerfSignposts.swift
//  claudeBlast
//

import Foundation
import os

/// Signpost intervals for Instruments. Category `.pointsOfInterest`, so they
/// show in the Points of Interest lane of the Time Profiler template without
/// adding an os_signpost instrument.
///
/// Near-free when nothing is recording: `beginInterval` checks whether the
/// signposter is enabled before doing any work.
enum PerfSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast",
        category: .pointsOfInterest)
}

extension PerfSignposts {
    /// Wrap `body` in a named interval.
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
