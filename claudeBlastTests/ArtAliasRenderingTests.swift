// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ArtAliasRenderingTests.swift
//  claudeBlastTests
//
//  A tile's picture lives at `bundleImage`, which is not always its key.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ArtAliasRenderingTests {

    /// The pronouns that borrow art, and the words they borrow it from.
    ///
    /// These are the four that showed up as letter placeholders in the coverage
    /// grid while `he`, `she`, `they` and `we` rendered beside them — the tell
    /// that an alias was not being followed rather than that art was missing.
    private let aliasPairs = [("him", "he"), ("her", "she"),
                              ("them", "they"), ("us", "we")]

    /// The bundled vocabulary really does alias these, so the rendering rule has
    /// something to be right about. If the aliases are ever given their own art,
    /// this fails and the tests below become moot rather than silently vacuous.
    @Test func theBundledVocabularyAliasesThePronouns() throws {
        let url = try #require(Bundle.main.url(forResource: "vocabulary",
                                               withExtension: "json"))
        let decoded = try JSONDecoder().decode([TileModelCodable].self,
                                               from: Data(contentsOf: url))
        let byKey = Dictionary(decoded.map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })

        for (alias, source) in aliasPairs {
            let entry = try #require(byKey[alias], "\(alias) missing from vocabulary")
            #expect(entry.bundleImage == source,
                    "\(alias) should borrow \(source)'s art")
        }
    }

    /// A tile built from the bundle carries the alias onto the model, which is
    /// what every rendering site reads.
    @Test func theAliasSurvivesOntoTheModel() throws {
        let url = try #require(Bundle.main.url(forResource: "vocabulary",
                                               withExtension: "json"))
        let decoded = try JSONDecoder().decode([TileModelCodable].self,
                                               from: Data(contentsOf: url))
        let byKey = Dictionary(decoded.map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })

        let codable = try #require(byKey["him"])
        let tile = TileModel(from: codable)
        #expect(tile.key == "him")
        #expect(tile.bundleImage == "he")
    }

    // MARK: - The resolver owns it

    /// The container has to outlive the body.
    ///
    /// Returning just the resolver and its context lets the `ModelContainer`
    /// deallocate at the end of the helper, and the context goes with it — every
    /// fetch then crashes rather than failing an expectation, which is why the
    /// first run reported five crashes and no messages. `withExtendedLifetime`
    /// is what the other suites here use for the same reason.
    private func withResolver(_ body: (TileImageResolver, ModelContext) throws -> Void) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let resolver = TileImageResolver()
        resolver.configure(modelContext: container.mainContext)
        try body(resolver, container.mainContext)
        withExtendedLifetime(container) {}
    }

    /// The resolver follows the alias, so a bare key is correct at every call
    /// site.
    ///
    /// This used to be each caller's job, and `TileImageView` takes a bare key —
    /// so being right meant remembering to pass `bundleImage` instead. Sixteen
    /// sites did; the coverage grid and the activity log's tile strip did not,
    /// and both drew placeholders for words whose art exists. The failure is
    /// silent by construction: a placeholder reads as "art not generated yet",
    /// never as "alias dropped".
    @Test func theResolverFollowsTheAlias() throws {
        try withResolver { resolver, ctx in
            let tile = TileModel(key: "him", value: "him", wordClass: "core")
            tile.bundleImage = "he"
            ctx.insert(tile)
            try ctx.save()

            #expect(resolver.artKey(for: "him") == "he")
        }
    }

    /// Idempotent, which is what lets the sixteen existing `bundleImage`-passing
    /// callers stay exactly as they are: an alias is one level deep and
    /// terminates on a key that aliases itself, so resolving twice is resolving
    /// once.
    @Test func resolvingAnAliasTwiceIsResolvingItOnce() throws {
        try withResolver { resolver, ctx in
            let him = TileModel(key: "him", value: "him", wordClass: "core")
            him.bundleImage = "he"
            let he = TileModel(key: "he", value: "he", wordClass: "core")
            he.bundleImage = "he"
            ctx.insert(him)
            ctx.insert(he)
            try ctx.save()

            let once = resolver.artKey(for: "him")
            #expect(resolver.artKey(for: once) == once)
        }
    }

    /// A key with no tile at all comes back unchanged — `packcover_space` is an
    /// art asset, not a word, and callers pass it directly.
    @Test func anUnknownKeyPassesThrough() throws {
        try withResolver { resolver, _ in
            #expect(resolver.artKey(for: "packcover_space") == "packcover_space")
        }
    }

    /// A tile whose `bundleImage` is its own key needs no entry, and one that is
    /// empty falls back to the key rather than resolving to nothing.
    @Test func selfAliasesAndEmptyAliasesResolveToTheKey() throws {
        try withResolver { resolver, ctx in
            let same = TileModel(key: "rocket", value: "rocket", wordClass: "object")
            same.bundleImage = "rocket"
            let empty = TileModel(key: "moon", value: "moon", wordClass: "object")
            empty.bundleImage = ""
            ctx.insert(same)
            ctx.insert(empty)
            try ctx.save()

            #expect(resolver.artKey(for: "rocket") == "rocket")
            #expect(resolver.artKey(for: "moon") == "moon")
        }
    }

    /// The table is cached, so a tile arriving later — by import or by sync —
    /// is invisible until the cache is dropped. That is the same stale-negative
    /// shape `invalidateSyncedArt` exists to cure for variants.
    @Test func aTileArrivingAfterTheFirstLookupNeedsInvalidation() throws {
        try withResolver { resolver, ctx in
            #expect(resolver.artKey(for: "him") == "him")   // loads an empty table

            let tile = TileModel(key: "him", value: "him", wordClass: "core")
            tile.bundleImage = "he"
            ctx.insert(tile)
            try ctx.save()

            #expect(resolver.artKey(for: "him") == "him")   // still stale, by design
            resolver.invalidateAliases()
            #expect(resolver.artKey(for: "him") == "he")
        }
    }
}
}
