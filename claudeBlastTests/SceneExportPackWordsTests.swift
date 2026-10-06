// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExportPackWordsTests.swift
//  claudeBlastTests
//
//  A scene built from bundled packs must survive being shared.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneExportPackWordsTests {

    /// A pack word is first-party AND absent from a fresh install.
    ///
    /// This is the distinction the exporter got wrong. `defaultTileKeys` was
    /// `isSystem`, which is true for bundled pack words because they are ours —
    /// but a pack installs on demand, so the recipient does not have them. Every
    /// pack word was dropped from the file.
    ///
    /// Measured on the real failure: a scene of 43 tiles across Space, Vehicles,
    /// Tide Pools and Dinosaurs exported **6** — two hand-added words and the
    /// four page links, the only tiles that happened to be `isSystem == false`.
    /// Four pages arrived empty, and an empty board has no Home cell, so the
    /// receiving device had no way back into Admin.
    @Test func packWordsAreCarriedEvenThoughTheyAreSystem() {
        // A pack word the built-in vocabulary does not also have — since session
        // 8 some pack words (the Vehicles pack, cow and pig) are built in too.
        let word = try! #require(PackCatalog.all.lazy
            .flatMap(\.words).first { !BundledVocabulary.contains($0.key) })

        // Exactly as `PackInstaller` mints it.
        let tile = TileModel(key: word.key, value: word.displayName, wordClass: word.wordClass)
        tile.isSystem = true

        let scene = BlasterScene(name: "Packed", homePageKey: "home")
        scene.pages = [PageSpec(key: "home",
                                tiles: [TileEntry(key: word.key, link: "", isAudible: true)])]

        let exported = SceneExporter.export(
            scene,
            defaultTileKeys: BundledVocabulary.keys,
            tileLookup: [tile.key: tile]
        )

        #expect(exported.tiles?.contains { $0.key == word.key } == true)
    }

    /// The other half: a word from `vocabulary.json` still costs nothing to
    /// share, because the recipient already has it. Without this the fix would
    /// simply be "carry everything", which fattens every file for no gain.
    @Test func coreVocabularyWordsAreStillNotCarried() {
        let key = try! #require(BundledVocabulary.keys.sorted().first)
        let tile = TileModel(key: key, value: key, wordClass: "actions")
        tile.isSystem = true

        let scene = BlasterScene(name: "Core", homePageKey: "home")
        scene.pages = [PageSpec(key: "home",
                                tiles: [TileEntry(key: key, link: "", isAudible: true)])]

        let exported = SceneExporter.export(
            scene,
            defaultTileKeys: BundledVocabulary.keys,
            tileLookup: [tile.key: tile]
        )

        #expect(exported.tiles?.contains { $0.key == key } != true)
        // The page still references it — the recipient resolves it locally.
        #expect(exported.pages.first?.tiles.first?.key == key)
    }

    /// The index must actually load. An empty set would silently make every
    /// export carry everything — safe, but it would hide a broken bundle
    /// resource behind merely-large files.
    @Test func bundledVocabularyLoads() {
        #expect(BundledVocabulary.keys.count > 400)
    }

    /// A word can be in a pack *and* built in. Session 8 brought the Vehicles
    /// pack and a few Farm, Mealtime and Tide Pools words into the vocabulary;
    /// the packs keep them, because the "Things that go" AI example builds its
    /// page from the Vehicles pack's word list.
    ///
    /// That is safe because both paths already treat a built-in word as present:
    /// installing a pack skips any key the store has, and an exported scene does
    /// not carry a word the recipient's vocabulary already holds. This pins the
    /// second half for exactly the overlapping words.
    @Test func aPackWordThatIsAlsoBuiltInIsNotCarried() {
        let shared = PackCatalog.all.flatMap(\.words).filter { BundledVocabulary.contains($0.key) }
        #expect(!shared.isEmpty, "the overlap this test is about exists")
        let word = try! #require(shared.first)
        let tile = TileModel(key: word.key, value: word.displayName, wordClass: word.wordClass)
        tile.isSystem = true
        let scene = BlasterScene(name: "Shared", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: [TileEntry(key: word.key, link: "", isAudible: true)])]
        let exported = SceneExporter.export(scene, defaultTileKeys: BundledVocabulary.keys,
                                            tileLookup: [tile.key: tile])
        #expect(exported.tiles?.contains { $0.key == word.key } != true)
    }
}
}
