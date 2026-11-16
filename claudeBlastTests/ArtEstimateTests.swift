// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ArtEstimateTests.swift
//  claudeBlastTests
//
//  The cost and time a board's Artwork page quotes before a run starts.
//

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct ArtEstimateTests {
    private func event(_ endpoint: String, micros: Int, at seconds: TimeInterval) -> APIUsageEvent {
        APIUsageEvent(cause: .tileImageGenerate, model: "gpt-image-2", endpoint: endpoint,
                      imageCount: 1, costMicros: micros,
                      timestamp: Date(timeIntervalSince1970: seconds))
    }

    /// Drawings and recolors are priced apart from this device's own history,
    /// and the time per picture is the typical gap inside a run, not the hours
    /// between one sitting and the next.
    @Test func estimatesFromThisDevicesOwnRuns() {
        let events = [
            event("/v1/images/generations", micros: 40_000, at: 0),
            event("/v1/images/edits", micros: 20_000, at: 20),
            event("/v1/images/generations", micros: 40_000, at: 40),
            event("/v1/images/edits", micros: 20_000, at: 60),
            event("/v1/images/generations", micros: 40_000, at: 10_000),  // next day's run
        ]
        let e = ArtEstimate.from(events)
        #expect(e.drawMicros == 40_000)
        #expect(e.recolorMicros == 20_000)
        #expect(e.secondsPerPicture == 20)
        // 10 drawings + 20 recolors = $0.80; 30 pictures × 20 s = 10 minutes.
        #expect(e.line(draws: 10, recolors: 20) == "Up to 30 pictures, about $0.80, about 10 minutes.")
    }

    /// With nothing to go on it gives the count and says why there is no
    /// price, rather than inventing one.
    @Test func saysSoWhenThereIsNoHistory() {
        let line = ArtEstimate.from([]).line(draws: 3, recolors: 6)
        #expect(line.hasPrefix("Up to 9 pictures."))
        #expect(line.contains("once this device has made some pictures"))
    }
}
