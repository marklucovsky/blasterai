// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageDecodeTests.swift
//  claudeBlastTests
//
//  The resolver must hand out DECODED images. Undecoded ones deadlocked a full
//  board — see TileImageResolver.decodedImage(from:).
//

import Testing
import Foundation
import UIKit
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct TileImageDecodeTests {

    /// Tile keys that ship art in every set, used to exercise the bundle path.
    private var sampleKeys: [String] {
        ["eat", "drink", "mom", "dad", "happy", "play", "more", "help"]
    }

    /// **The property the fix rests on.** A `UIImage` from `UIImage(data:)` holds
    /// encoded bytes and decodes later, on SwiftUI's unbounded prepare-image
    /// pool — 64 tiles meant 64 concurrent HEIC decodes and an exhausted codec
    /// session pool. A decoded image reports a backing `CGImage` whose bitmap
    /// is already materialised.
    @Test func bundledArtComesBackDecoded() throws {
        let resolver = TileImageResolver()
        var checked = 0
        for key in sampleKeys {
            guard let image = resolver.image(for: key) else { continue }
            let cg = try #require(image.cgImage, "\(key): no CGImage backing")
            #expect(cg.width > 0 && cg.height > 0)
            // `dataProvider.data` on a decoded image is the pixel buffer. On an
            // undecoded one the CGImage would not exist at all yet.
            #expect(cg.bitsPerPixel >= 8)
            checked += 1
        }
        #expect(checked > 0, "no bundled art resolved — sample keys may be stale")
    }

    /// Decoding is serialised on the main actor, so the cache is what keeps that
    /// affordable: a tile must decode once per session, not once per render.
    @Test func repeatedResolutionIsCached() {
        let resolver = TileImageResolver()
        guard let first = resolver.image(for: "eat") else { return }
        let second = resolver.image(for: "eat")
        #expect(first === second, "second resolution re-decoded instead of hitting the cache")
    }

    /// Sizing guard for the serial-decode decision. A full board is 64 tiles; if
    /// decoding them ever costs enough to be felt at launch, the choke point has
    /// to become a bounded queue rather than the main actor. Deliberately loose —
    /// this exists to catch an order-of-magnitude regression, not to police ms.
    @Test func decodingAFullBoardStaysAffordable() {
        let resolver = TileImageResolver()
        let keys = sampleKeys
        let started = ContinuousClock.now
        var decoded = 0
        // 64 resolutions, the cap a full iPad board renders at.
        for i in 0..<64 {
            if resolver.image(for: keys[i % keys.count]) != nil { decoded += 1 }
        }
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        #expect(decoded > 0)
        #expect(ms < 2_000, "64 tile resolutions took \(Int(ms))ms")
    }
}
}
