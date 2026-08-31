// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PackTransferTests.swift
//  claudeBlastTests
//
//  Sharing a page as a vocabulary pack, and receiving one.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PackTransferTests {

    // MARK: - Fixtures

    /// Bytes that are recognisably *not* re-encoded. The exporter must copy
    /// stored art through verbatim, so a test can assert on exact bytes.
    private func artData(_ marker: UInt8) -> Data {
        Data([marker, 0xFE, 0xED, 0xFA, 0xCE] + Array(repeating: marker, count: 64))
    }

    /// A scene with one system word and one caregiver-authored word that has art
    /// in two different image sets.
    private func makeScene(context: ModelContext) -> (BlasterScene, [String: TileModel]) {
        let eat = TileModel(key: "eat", wordClass: "actions")
        eat.isSystem = true
        let dumpling = TileModel(key: "dumpling", value: "dumpling", wordClass: "food")
        dumpling.isSystem = false
        context.insert(eat)
        context.insert(dumpling)

        TileArtVariant.upsert(tileKey: "dumpling", imageSet: .playful3D,
                              imageData: artData(0x01), context: context)
        TileArtVariant.upsert(tileKey: "dumpling", imageSet: .classic,
                              imageData: artData(0x02), context: context)

        let page = PageSpec(key: "dinner", tiles: [
            TileEntry(key: "eat", link: "", isAudible: true),
            TileEntry(key: "dumpling", link: "", isAudible: true),
        ])
        let scene = BlasterScene(name: "Dinner Board", homePageKey: "dinner")
        scene.pages = [page]
        context.insert(scene)
        try? context.save()

        return (scene, ["eat": eat, "dumpling": dumpling])
    }

    // MARK: - Export

    @Test("A custom word exports every set's art it has, not just one")
    func exportsAllVariants() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let page = scene.pages[0]

        let pack = PackExporter.exportPage(page, from: scene, tileLookup: lookup, context: context)

        let dumpling = try #require(pack.words.first { $0.key == "dumpling" })
        #expect(dumpling.art?.count == 2)
        let sets = Set((dumpling.art ?? []).map(\.imageSet))
        #expect(sets == [ImageSetID.playful3D.rawValue, ImageSetID.classic.rawValue])
    }

    @Test("A system word carries no art — the recipient already ships it")
    func systemWordsCarryNoArt() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let pack = PackExporter.exportPage(scene.pages[0], from: scene, tileLookup: lookup, context: context)

        let eat = try #require(pack.words.first { $0.key == "eat" })
        #expect(eat.art == nil || eat.art?.isEmpty == true)
        #expect(eat.imageData == nil)
    }

    @Test("Stored bytes travel verbatim — no re-encode")
    func artIsNotReEncoded() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let pack = PackExporter.exportPage(scene.pages[0], from: scene, tileLookup: lookup, context: context)
        let dumpling = try #require(pack.words.first { $0.key == "dumpling" })
        let entry = try #require(dumpling.art?.first { $0.imageSet == ImageSetID.playful3D.rawValue })

        #expect(Data(base64Encoded: entry.imageData) == artData(0x01))
    }

    @Test("Word order follows the page")
    func preservesWordOrder() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let pack = PackExporter.exportPage(scene.pages[0], from: scene, tileLookup: lookup, context: context)
        #expect(pack.words.map(\.key) == ["eat", "dumpling"])
    }

    // MARK: - Import

    /// The defining property of a pack: it delivers vocabulary, not a board.
    @Test("Importing a pack creates no scene and no page")
    func importCreatesNoScene() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        let scenesBefore = try context.fetch(FetchDescriptor<BlasterScene>()).count
        TestStore.reset()
        let fresh = TestStore.container.mainContext
        try PackImporter.importJSON(data, context: fresh)

        #expect(try fresh.fetch(FetchDescriptor<BlasterScene>()).isEmpty)
        #expect(scenesBefore == 1)  // the sender did have one
    }

    @Test("Importing a pack adds its words and records the pack")
    func importAddsWordsAndPack() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        let result = try PackImporter.importJSON(data, context: context)

        #expect(result.newWordCount == 2)
        let tiles = try context.fetch(FetchDescriptor<TileModel>())
        #expect(Set(tiles.map(\.key)) == ["eat", "dumpling"])

        let packs = ReceivedPack.all(in: context)
        #expect(packs.count == 1)
        #expect(packs.first?.words.count == 2)
    }

    /// The bug this whole design exists to prevent. Set art belongs in
    /// `TileArtVariant`; landing it in `userImageData` would make the word render
    /// the sender's style forever, because the photo override outranks every set.
    @Test("Received set art lands in TileArtVariant, never the photo override")
    func setArtNeverBecomesPhotoOverride() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        try PackImporter.importJSON(data, context: context)

        let dumpling = try #require(
            try context.fetch(FetchDescriptor<TileModel>()).first { $0.key == "dumpling" }
        )
        #expect(!dumpling.hasUserImage, "set art must not be filed as a photo override")

        let variants = try context.fetch(FetchDescriptor<TileArtVariant>())
            .filter { $0.tileKey == "dumpling" }
        #expect(variants.count == 2)
        #expect(Set(variants.map(\.imageSetRaw))
                == [ImageSetID.playful3D.rawValue, ImageSetID.classic.rawValue])
    }

    @Test("Import never overwrites art the recipient already has")
    func importDoesNotOverwriteExistingArt() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        // The recipient already drew their own dumpling for Playful-3D.
        let mine = TileModel(key: "dumpling", value: "dumpling", wordClass: "food")
        context.insert(mine)
        TileArtVariant.upsert(tileKey: "dumpling", imageSet: .playful3D,
                              imageData: artData(0x99), context: context)
        try context.save()

        try PackImporter.importJSON(data, context: context)

        let variants = try context.fetch(FetchDescriptor<TileArtVariant>())
            .filter { $0.tileKey == "dumpling" }
        let p3d = try #require(variants.first { $0.imageSetRaw == ImageSetID.playful3D.rawValue })
        #expect(p3d.imageData == artData(0x99), "the recipient's own art wins")
        // The set they had nothing for is filled in.
        #expect(variants.contains { $0.imageSetRaw == ImageSetID.classic.rawValue })
    }

    @Test("Import does not relabel words the recipient already uses")
    func importDoesNotRewriteWordIdentity() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        let mine = TileModel(key: "dumpling", value: "potsticker", wordClass: "snacks")
        context.insert(mine)
        try context.save()

        try PackImporter.importJSON(data, context: context)

        let tile = try #require(
            try context.fetch(FetchDescriptor<TileModel>()).first { $0.key == "dumpling" }
        )
        #expect(tile.value == "potsticker")
        #expect(tile.wordClass == "snacks")
    }

    @Test("Receiving the same pack twice updates it rather than duplicating")
    func reImportIsIdempotent() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        try PackImporter.importJSON(data, context: context)
        let second = try PackImporter.importJSON(data, context: context)

        #expect(second.wasUpdate)
        #expect(ReceivedPack.all(in: context).count == 1)
        #expect(try context.fetch(FetchDescriptor<TileModel>()).count == 2)
    }

    @Test("A received pack shows up alongside the bundled ones")
    func receivedPackJoinsTheCatalog() throws {
        TestStore.reset()
        var context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let data = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                   tileLookup: lookup, context: context)

        TestStore.reset()
        context = TestStore.container.mainContext
        try PackImporter.importJSON(data, context: context)

        let available = PackCatalog.available(in: context)
        #expect(available.count == PackCatalog.all.count + 1)
        #expect(available.contains { $0.displayName == "Dinner" })
    }

    // MARK: - Format

    @Test("A pack file is rejected by the scene importer, and vice versa")
    func formatsDoNotCrossImport() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let packData = try PackExporter.exportPageJSON(scene.pages[0], from: scene,
                                                       tileLookup: lookup, context: context)
        let sceneData = try SceneExporter.exportJSON(scene, defaultTileKeys: ["eat"],
                                                     tileLookup: lookup, context: context)

        #expect(throws: (any Error).self) { try SceneImporter.preview(packData) }
        #expect(throws: (any Error).self) { try PackImporter.preview(sceneData) }
    }
}
}
