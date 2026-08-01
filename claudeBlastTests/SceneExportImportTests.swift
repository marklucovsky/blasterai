// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExportImportTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneExportImportTests {

    private func makeTestContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    /// Build a minimal scene with known tiles for testing.
    private func makeScene(context: ModelContext) -> (BlasterScene, Set<String>, [String: TileModel]) {
        let eat = TileModel(key: "eat", wordClass: "actions")
        let pizza = TileModel(key: "pizza", wordClass: "food")
        let mom = TileModel(key: "mom", wordClass: "people")
        context.insert(eat)
        context.insert(pizza)
        context.insert(mom)

        let homePage = PageSpec(key: "home", tiles: [
            TileEntry(key: "eat", link: "food", isAudible: true),
            TileEntry(key: "mom", link: "", isAudible: true),
        ])
        let foodPage = PageSpec(key: "food", tiles: [
            TileEntry(key: "pizza", link: "", isAudible: true),
        ])

        let scene = BlasterScene(
            name: "Test Scene",
            descriptionText: "A test",
            homePageKey: "home"
        )
        scene.pages = [homePage, foodPage]
        context.insert(scene)

        let defaultKeys: Set<String> = ["eat", "pizza", "mom"]
        let tileLookup: [String: TileModel] = ["eat": eat, "pizza": pizza, "mom": mom]
        return (scene, defaultKeys, tileLookup)
    }

    // MARK: - Export tests

    @Test func exportProducesCorrectTypeAndVersion() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        #expect(exportable.type == BlasterSceneFormat.mediaType)
        #expect(exportable.version == BlasterSceneFormat.currentVersion)
    }

    @Test func exportPreservesSceneMetadata() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        #expect(exportable.name == "Test Scene")
        #expect(exportable.description == "A test")
        #expect(exportable.homePageKey == "home")
    }

    @Test func exportIncludesAllPagesAndTiles() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        #expect(exportable.pages.count == 2)

        let homePage = exportable.pages.first { $0.key == "home" }
        #expect(homePage != nil)
        #expect(homePage!.tiles.count == 2)

        let foodPage = exportable.pages.first { $0.key == "food" }
        #expect(foodPage != nil)
        #expect(foodPage!.tiles.count == 1)
        #expect(foodPage!.tiles[0].key == "pizza")
    }

    @Test func exportPreservesLinkAndAudible() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)
        let homePage = exportable.pages.first { $0.key == "home" }!
        let eatTile = homePage.tiles.first { $0.key == "eat" }!

        #expect(eatTile.link == "food")
        #expect(eatTile.isAudible == true)
    }

    @Test func exportOmitsTilesArrayWhenAllDefault() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        // All tiles are in the default vocabulary and have no custom images
        #expect(exportable.tiles == nil)
    }

    @Test func exportIncludesNonDefaultTiles() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        var (scene, defaultKeys, tileLookup) = makeScene(context: context)

        // Add a custom tile not in the default vocabulary
        let custom = TileModel(key: "therapy_goal", wordClass: "actions")
        context.insert(custom)
        tileLookup["therapy_goal"] = custom
        var pages = scene.pages
        pages[0].tiles.append(TileEntry(key: "therapy_goal", link: "", isAudible: true))
        scene.pages = pages

        let exportable = SceneExporter.export(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        #expect(exportable.tiles != nil)
        #expect(exportable.tiles!.count == 1)
        #expect(exportable.tiles![0].key == "therapy_goal")
        #expect(exportable.tiles![0].wordClass == "actions")
        #expect(exportable.tiles![0].displayName == "therapy goal")
    }

    @Test func exportToJSONRoundTrips() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let jsonData = try SceneExporter.exportJSON(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)
        let decoded = try JSONDecoder().decode(ExportableScene.self, from: jsonData)

        #expect(decoded.type == BlasterSceneFormat.mediaType)
        #expect(decoded.name == "Test Scene")
        #expect(decoded.pages.count == 2)
    }

    @Test func exportJSONContainsAtTypeKey() throws {
        let container = try makeTestContainer()
        let (scene, defaultKeys, tileLookup) = makeScene(context: container.mainContext)

        let jsonData = try SceneExporter.exportJSON(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"@type\""))
        #expect(jsonString.contains(BlasterSceneFormat.mediaType))
    }

    // MARK: - Import tests

    @Test func importBasicScene() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Pre-populate vocabulary
        let eat = TileModel(key: "eat", wordClass: "actions")
        let pizza = TileModel(key: "pizza", wordClass: "food")
        context.insert(eat)
        context.insert(pizza)

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "1.0.0",
            "name": "Imported Scene",
            "description": "Test import",
            "homePageKey": "home",
            "pages": [
                {
                    "key": "home",
                    "tiles": [
                        { "key": "eat", "isAudible": true, "link": "" },
                        { "key": "pizza", "isAudible": true, "link": "" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try SceneImporter.importJSON(json, context: context)

        #expect(result.scene.name == "Imported Scene")
        #expect(result.scene.pages.count == 1)
        #expect(result.scene.pages[0].tiles.count == 2)
        #expect(result.skippedKeys.isEmpty)
        #expect(result.newTileCount == 0)
    }

    @Test func importSkipsUnknownTileKeys() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let eat = TileModel(key: "eat", wordClass: "actions")
        context.insert(eat)

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "1.0.0",
            "name": "Sparse",
            "description": "",
            "homePageKey": "home",
            "pages": [
                {
                    "key": "home",
                    "tiles": [
                        { "key": "eat", "isAudible": true, "link": "" },
                        { "key": "nonexistent", "isAudible": true, "link": "" },
                        { "key": "also_missing", "isAudible": true, "link": "" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try SceneImporter.importJSON(json, context: context)

        #expect(result.scene.pages[0].tiles.count == 1)
        #expect(result.skippedKeys.count == 2)
        #expect(result.skippedKeys.contains("nonexistent"))
        #expect(result.skippedKeys.contains("also_missing"))
    }

    @Test func importCreatesNewTilesFromTilesArray() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "1.0.0",
            "name": "Custom Vocab",
            "description": "",
            "homePageKey": "home",
            "tiles": [
                { "key": "therapy_goal", "wordClass": "actions", "displayName": "therapy goal" }
            ],
            "pages": [
                {
                    "key": "home",
                    "tiles": [
                        { "key": "therapy_goal", "isAudible": true, "link": "" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try SceneImporter.importJSON(json, context: context)

        #expect(result.newTileCount == 1)
        #expect(result.scene.pages[0].tiles.count == 1)
        #expect(result.scene.pages[0].tiles[0].key == "therapy_goal")
        // Verify the underlying TileModel got created with the right metadata.
        let descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == "therapy_goal" })
        let imported = try context.fetch(descriptor).first
        #expect(imported?.displayName == "therapy goal")
    }

    @Test func importDeviceVocabularyWins() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Device already has "eat" with wordClass "actions"
        let eat = TileModel(key: "eat", wordClass: "actions")
        context.insert(eat)

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "1.0.0",
            "name": "Override Attempt",
            "description": "",
            "homePageKey": "home",
            "tiles": [
                { "key": "eat", "wordClass": "food", "displayName": "EAT OVERRIDE" }
            ],
            "pages": [
                {
                    "key": "home",
                    "tiles": [
                        { "key": "eat", "isAudible": true, "link": "" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try SceneImporter.importJSON(json, context: context)

        // Device tile should NOT be overridden
        #expect(result.newTileCount == 0)
        let descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == "eat" })
        let tile = try context.fetch(descriptor).first
        #expect(tile?.wordClass == "actions")  // not "food"
        #expect(tile?.displayName == "eat")     // not "EAT OVERRIDE"
    }

    @Test func importRejectsInvalidType() throws {
        let container = try makeTestContainer()

        let json = """
        {
            "@type": "application/json",
            "version": "1.0.0",
            "name": "Bad",
            "description": "",
            "homePageKey": "home",
            "pages": []
        }
        """.data(using: .utf8)!

        #expect(throws: SceneImportError.self) {
            try SceneImporter.importJSON(json, context: container.mainContext)
        }
    }

    @Test func importRejectsUnsupportedMajorVersion() throws {
        let container = try makeTestContainer()

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "2.0.0",
            "name": "Future",
            "description": "",
            "homePageKey": "home",
            "pages": [{ "key": "home", "tiles": [] }]
        }
        """.data(using: .utf8)!

        #expect(throws: SceneImportError.self) {
            try SceneImporter.importJSON(json, context: container.mainContext)
        }
    }

    @Test func importAcceptsMinorVersionBump() throws {
        let container = try makeTestContainer()

        let json = """
        {
            "@type": "application/vnd.claudeblast.scene+json",
            "version": "1.1.0",
            "name": "Compatible",
            "description": "",
            "homePageKey": "home",
            "pages": [{ "key": "home", "tiles": [] }]
        }
        """.data(using: .utf8)!

        let result = try SceneImporter.importJSON(json, context: container.mainContext)
        #expect(result.scene.name == "Compatible")
    }

    @Test func exportThenImportRoundTrip() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (scene, defaultKeys, tileLookup) = makeScene(context: context)

        // Export
        let jsonData = try SceneExporter.exportJSON(scene, defaultTileKeys: defaultKeys, tileLookup: tileLookup)

        // Import into fresh context (but same container, so tiles exist)
        let result = try SceneImporter.importJSON(jsonData, context: context)

        #expect(result.scene.name == scene.name)
        #expect(result.scene.homePageKey == scene.homePageKey)
        #expect(result.scene.pages.count == scene.pages.count)
        #expect(result.skippedKeys.isEmpty)
    }
}
}
