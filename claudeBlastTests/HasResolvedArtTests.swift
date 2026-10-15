// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  HasResolvedArtTests.swift
//  claudeBlastTests
//
//  `hasResolvedArt(for:)` is `image(for:) != nil` without the decode. The scene
//  editor's "words still need a picture" count moved onto it after Instruments
//  showed the decoding version costing ~600 ms per render on an iPad mini. It
//  is only a fix if it gives the same answer, so every test here is parity.
//

import Testing
import Foundation
import SwiftData
import UIKit
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct HasResolvedArtTests {

    /// See `ArtAliasRenderingTests.withResolver`: the container must outlive the body.
    private func withResolver(_ body: (TileImageResolver, ModelContext) throws -> Void) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let resolver = TileImageResolver()
        resolver.configure(modelContext: container.mainContext)
        try body(resolver, container.mainContext)
        withExtendedLifetime(container) {}
    }

    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func expectParity(_ resolver: TileImageResolver, _ key: String,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        let decoded = resolver.image(for: key) != nil
        #expect(resolver.hasResolvedArt(for: key) == decoded,
                "\(key) in \(resolver.activeSet.rawValue): image(for:) says \(decoded)",
                sourceLocation: sourceLocation)
    }

    /// The bundled vocabulary, glyphs and an invented word, in every shipped set.
    /// Sampled rather than exhaustive — every decode is real work — but the
    /// stride walks every word class and the alias pronouns are named outright.
    @Test func agreesWithImageForAcrossEveryShippedSet() throws {
        let url = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"))
        let vocab = try JSONDecoder().decode([TileModelCodable].self, from: Data(contentsOf: url))
        let sampled = stride(from: 0, to: vocab.count, by: 7).map { vocab[$0].bundleImage ?? vocab[$0].key }
        let keys = sampled + ["him", "he", "letter_a", "number_0", "zzz_invented_word"]
        #expect(keys.count > 50)

        try withResolver { resolver, _ in
            for set in ImageSetCatalog.system.map(\.id) {
                resolver.activeSet = set
                for key in keys { expectParity(resolver, key) }
            }
        }
    }

    /// A custom word arted in one style still shows in another, through the
    /// any-variant fallback, and must not be counted as needing art there.
    @Test func aVariantInAnotherStyleCounts() throws {
        try withResolver { resolver, ctx in
            ctx.insert(TileModel(key: "zzz_custom", value: "custom", wordClass: "core"))
            ctx.insert(TileArtVariant(tileKey: "zzz_custom", imageSet: .classic, imageData: pngData()))
            try ctx.save()

            for set in ImageSetCatalog.system.map(\.id) {
                resolver.activeSet = set
                #expect(resolver.hasResolvedArt(for: "zzz_custom"), "\(set.rawValue)")
                expectParity(resolver, "zzz_custom")
            }
        }
    }

    /// A caregiver photo is art, in every set.
    @Test func aPhotoCounts() throws {
        try withResolver { resolver, ctx in
            let tile = TileModel(key: "zzz_photo", value: "photo", wordClass: "core")
            tile.userImageData = pngData()
            ctx.insert(tile)
            try ctx.save()

            for set in ImageSetCatalog.system.map(\.id) {
                resolver.activeSet = set
                #expect(resolver.hasResolvedArt(for: "zzz_photo"), "\(set.rawValue)")
                expectParity(resolver, "zzz_photo")
            }
        }
    }

    /// A custom word with nothing is the case the count exists for.
    @Test func aBareCustomWordNeedsArt() throws {
        try withResolver { resolver, ctx in
            ctx.insert(TileModel(key: "zzz_bare", value: "bare", wordClass: "core"))
            try ctx.save()

            resolver.activeSet = .playful3D
            #expect(!resolver.hasResolvedArt(for: "zzz_bare"))
            for set in ImageSetCatalog.system.map(\.id) {
                resolver.activeSet = set
                expectParity(resolver, "zzz_bare")
            }
        }
    }
}
}
