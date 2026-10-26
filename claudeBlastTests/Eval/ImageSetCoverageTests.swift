// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ImageSetCoverageTests.swift
//  claudeBlastTests
//
//  Enforces the norm from the Playful-3D work: anything we ship must be complete.
//  Every ImageSetID marked `isShippable` must provide real art for every key in
//  the bundled vocabulary — no relying on the master-set backfill or the
//  letter-on-color placeholder to paper over gaps. Incomplete sets (High
//  Contrast today) are `isShippable == false` and are exempt until reviewed +
//  regenerated. Runs offline (tests are app-hosted, so Bundle.main is the app
//  bundle and the tile PNGs + vocabulary.json are present).

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct ImageSetCoverageTests {

    /// All vocabulary keys from the bundled vocabulary.json.
    /// The keys art is actually stored under — the alias where a word has one.
    ///
    /// A word key is not always an art key. `him` deliberately carries no picture
    /// of its own: it reuses `he`, because they are the same image and different
    /// grammar, and generating a second would cost money to produce something a
    /// child cannot tell apart. Coverage means "every word resolves to art", so
    /// it has to be measured where the art lives.
    private func vocabularyArtKeys() throws -> [String] {
        let url = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
                               "vocabulary.json missing from the app bundle")
        let entries = try JSONDecoder().decode([TileModelCodable].self, from: Data(contentsOf: url))
        return entries.map { entry in
            guard let alias = entry.bundleImage, !alias.isEmpty else { return entry.key }
            return alias
        }
    }

    private func vocabularyKeys() throws -> [String] {
        let url = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
                               "vocabulary.json missing from the app bundle")
        struct Entry: Decodable { let key: String }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        return entries.map(\.key)
    }

    /// Known, tracked gaps in otherwise-shippable sets. Currently empty:
    /// ARASAAC was the only set with tracked gaps, and as of 2026-07-28 it is
    /// demoted to legacy/non-shippable (see `ImageSetID.isShippable`) — an
    /// external corpus we never generate against, so it permanently lags the
    /// vocabulary. It's excluded from the coverage bar entirely rather than
    /// allowlisted. The map stays for any future shippable set that needs a
    /// temporary tracked-gap window; the test fails on any NEW gap.
    ///
    /// **Open window, session 14:** BlasterAI 60's new folder tiles have Classic
    /// art only, so the structure could be judged before every style was drawn
    /// (Mark's call). The other sets fall back to Classic's picture for them.
    /// They close in the word pass, when the other four styles are drawn.
    private static let folderTiles: Set<String> = [
        "folder_small_words", "folder_moving", "folder_taking_care", "folder_talking",
        "folder_thinking", "folder_playing", "folder_cooking", "folder_senses", "folder_doing",
        "folder_size", "folder_how_it_feels", "folder_opinions", "folder_where", "folder_how_much",
        "folder_what_its_like", "folder_house", "folder_school", "folder_fun_places",
        "folder_out_and_about",
        "folder_breakfast", "folder_lunch_dinner", "folder_fruit", "folder_veggies", "folder_snacks",
        "folder_family", "folder_toys", "folder_art", "folder_games", "folder_sports",
        "folder_outside_play",
    ]
    /// **Open window, session 14 word pass:** the words of
    /// `tools/board_spec/word_pass_1.json` landed before their art (Mark's
    /// order: structure, then words, then images), in every set, Classic
    /// included. Read from the pass itself, so the window is exactly that list
    /// and closes when the images PR deletes this.
    private static let awaitingArt: Set<String> = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/board_spec/word_pass_1.json")
        struct Pass: Decodable {
            struct Folder: Decodable { let key: String }
            struct Page: Decodable { let folder: Folder?; let words: [Word] }
            let pages: [Page]
        }
        /// A word, or a run of words: `"key|Label"` or `["key", …]`.
        enum Word: Decodable {
            case one(String), run([String])
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .one(s) } else { self = .run(try c.decode([String].self)) }
            }
            var keys: [String] {
                switch self { case .one(let s): [s]; case .run(let r): r }
            }
        }
        guard let data = try? Data(contentsOf: url),
              let pass = try? JSONDecoder().decode(Pass.self, from: data) else { return [] }
        let words = pass.pages.flatMap { $0.words.flatMap(\.keys) }
            .map { String($0.split(separator: "|", maxSplits: 1)[0]) }
        return Set(words + pass.pages.compactMap(\.folder?.key))
    }()

    private static let knownIncompleteShippable: [String: Set<String>] = [
        "classic": awaitingArt,
        "classic_medium": folderTiles.union(awaitingArt),
        "classic_medium_dark": folderTiles.union(awaitingArt),
        "playful_3d": folderTiles.union(awaitingArt),
        "high_contrast": folderTiles.union(awaitingArt),
    ]

    @Test func theWordPassIsReadable() {
        #expect(Self.awaitingArt.count > 400, "word_pass_1.json not found or empty: \(Self.awaitingArt.count)")
    }

    /// Every distinct tile key introduced by a bundled pack/starter scene
    /// (starter_*.json, pack_*.json). These are the "extension" words beyond core
    /// vocabulary.json — the ones a caregiver sees when they instantiate a starter
    /// scene like Farm or Tide Pools. Nothing guarded these before, which let
    /// classic art for them go unnoticed when a build shipped without it.
    private func extensionSceneKeys() throws -> [String] {
        struct Tile: Decodable { let key: String }
        struct Scene: Decodable { let tiles: [Tile]? }
        var keys = Set<String>()
        for prefix in ["starter_", "pack_"] {
            let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
            for url in urls where url.lastPathComponent.hasPrefix(prefix) {
                guard let scene = try? JSONDecoder().decode(Scene.self, from: Data(contentsOf: url)),
                      let tiles = scene.tiles else { continue }
                tiles.forEach { keys.insert($0.key) }
            }
        }
        return keys.sorted()
    }

    /// Extension words that intentionally ship WITHOUT art — they are the "new
    /// words" a starter scene surfaces to demo the Generate-art flow, plus page /
    /// home keys that never render as a tile. They lack art in every set (not just
    /// classic), so they are not a coverage regression.
    private static let extensionWordsWithoutArt: Set<String> = [
        "mealtime", "tidepools",           // home/page keys, not tiles
        "placemat", "scarecrow", "seahorse", // intentional generate-art demo words
    ]

    /// The authored generation sets (Playful-3D + Classic) must carry real art for
    /// every word a starter/pack scene adds — otherwise a caregiver in Classic mode
    /// who picks that scene sees the Playful-3D master backfill, not Classic. This
    /// is the exact bug behind the `starterart_*` p3d sidecars: they baked p3d into
    /// `userImageData`, masking the active set. ARASAAC is deliberately excluded —
    /// it's a legacy reference set that never received pack extensions and relies
    /// on the master backfill for them.
    @Test func authoredSetsCoverExtensionSceneWords() throws {
        let keys = try extensionSceneKeys()
        #expect(!keys.isEmpty, "no bundled starter/pack scene keys found")

        let resolver = TileImageResolver()
        for set in ImageSetCatalog.generationTargets.flatMap(\.setIDs) {
            let missing = Set(keys.filter { resolver.image(for: $0, in: set) == nil })
            let unexpected = missing.subtracting(Self.extensionWordsWithoutArt).sorted()
            #expect(unexpected.isEmpty,
                    "Authored set \(set.rawValue) is missing art for \(unexpected.count) starter/pack word(s) — a caregiver picking that scene in \(set.displayName) mode sees the master-set fallback, not \(set.displayName): \(unexpected.prefix(20).joined(separator: ", "))")
        }
    }

    @Test func shippableSetsCoverEntireVocabulary() throws {
        let keys = try vocabularyArtKeys()
        #expect(!keys.isEmpty)

        let resolver = TileImageResolver()
        for set in ImageSetCatalog.all.map(\.id) where set.isShippable {
            // Real art only — bypasses photo overrides, master-set backfill, and
            // placeholders by querying the specific set.
            let missing = Set(keys.filter { resolver.image(for: $0, in: set) == nil })
            let allowed = Self.knownIncompleteShippable[set.rawValue] ?? []
            let unexpected = missing.subtracting(allowed).sorted()
            #expect(unexpected.isEmpty,
                    "Shippable set \(set.rawValue) has NEW missing art for \(unexpected.count) tile(s): \(unexpected.prefix(20).joined(separator: ", "))")

            // Surface when a tracked gap has been filled so the allowlist can shrink.
            let filled = allowed.subtracting(missing).sorted()
            if !filled.isEmpty {
                print("[eval] \(set.rawValue): tracked gaps now filled — remove from knownIncompleteShippable: \(filled.joined(separator: ", "))")
            }
        }
    }

    /// Guards the inverse: if a set has no gaps, it ought to be marked shippable.
    /// Surfaces "High Contrast is now complete — flip isShippable" without a code
    /// dive. A soft signal (record, not a failure) so finishing art doesn't
    /// require a test edit in the same change.
    @Test func reportsNonShippableSetsThatAreActuallyComplete() throws {
        let keys = try vocabularyKeys()
        let resolver = TileImageResolver()
        for set in ImageSetCatalog.all.map(\.id) where !set.isShippable {
            let missing = keys.filter { resolver.image(for: $0, in: set) == nil }
            if missing.isEmpty {
                print("[eval] \(set.rawValue) now has full coverage — consider marking it isShippable.")
            }
        }
    }
}
