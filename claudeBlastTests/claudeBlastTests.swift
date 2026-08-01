// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  claudeBlastTests.swift
//  claudeBlastTests
//
//  Created by MARK LUCOVSKY on 2/16/26.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct claudeBlastTests {

    private func makeTestContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    @Test func tileModelKeyNormalization() throws {
        let tile = TileModel(key: "Graham_Cracker", wordClass: "food")
        #expect(tile.key == "graham_cracker")
        #expect(tile.displayName == "graham cracker")
        #expect(tile.value == "graham cracker")
        #expect(tile.bundleImage == "graham_cracker")
        #expect(tile.wordClass == "food")
        #expect(tile.type == .word)
    }

    @Test func metricEventCreation() throws {
        let event = MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected)
        #expect(event.subjectType == "tile")
        #expect(event.subjectKey == "eat")
        #expect(event.eventType == .selected)
    }

    @Test func metricEventInsertAndQuery() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        context.insert(MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected))
        context.insert(MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected))
        context.insert(MetricEvent(subjectType: "tile", subjectKey: "pizza", eventType: .selected))
        context.insert(MetricEvent(subjectType: "cache", subjectKey: "eat,mom", eventType: .hit))

        let eatSelected = try context.fetch(
            FetchDescriptor<MetricEvent>(predicate: #Predicate {
                $0.subjectKey == "eat" && $0.subjectType == "tile"
            })
        )
        #expect(eatSelected.count == 2)

        let allTileEvents = try context.fetch(
            FetchDescriptor<MetricEvent>(predicate: #Predicate {
                $0.subjectType == "tile"
            })
        )
        #expect(allTileEvents.count == 3)
    }

    @Test func pageSpecWithOrderedTiles() throws {
        let page = PageSpec(key: "home", tiles: [
            TileEntry(key: "eat", link: "eat", isAudible: true)
        ])
        #expect(page.key == "home")
        #expect(page.tiles.count == 1)
        #expect(page.tiles.first?.key == "eat")
    }

    @Test func tileEntryDefaults() throws {
        let entry = TileEntry(key: "home")
        #expect(entry.link == "")
        #expect(entry.isAudible == true)
    }

    @Test func sentenceCacheOrderIndependentKey() throws {
        let sels = [
            TileSelection(key: "mom", value: "mom", wordClass: "people"),
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]
        let cache1 = SentenceCache(tiles: sels, grade: 2, sentence: "test")
        let cache2 = SentenceCache(tiles: sels.reversed(), grade: 2, sentence: "test")
        #expect(cache1.cacheKey == cache2.cacheKey)
        // Key folds in the model/prompt version + grade + per-tile word class; tiles remain sorted.
        #expect(cache1.cacheKey == "\(CacheKeyPolicy.versionToken)/g2#eat:actions,mom:people,pizza:food")
    }

    @Test func tileSelectionLogic() throws {
        let eat = TileModel(key: "eat", wordClass: "actions")
        let pizza = TileModel(key: "pizza", wordClass: "food")
        let mom = TileModel(key: "mom", wordClass: "people")
        let drink = TileModel(key: "drink", wordClass: "actions")
        let water = TileModel(key: "water", wordClass: "food")

        let maxTiles = 4
        var selectedTiles: [TileModel] = []

        // Add tiles up to max
        for tile in [eat, pizza, mom, drink] {
            if selectedTiles.count < maxTiles {
                selectedTiles.append(tile)
            }
        }
        #expect(selectedTiles.count == 4)

        // Cannot exceed max
        if selectedTiles.count < maxTiles {
            selectedTiles.append(water)
        }
        #expect(selectedTiles.count == 4)

        // Remove by index (tap-to-remove)
        selectedTiles.remove(at: 1) // removes pizza
        #expect(selectedTiles.count == 3)
        #expect(selectedTiles[0].key == "eat")
        #expect(selectedTiles[1].key == "mom")

        // Clear all
        selectedTiles.removeAll()
        #expect(selectedTiles.isEmpty)
    }

    @Test func navigationTileHasLink() throws {
        let navTile = TileEntry(key: "food", link: "food_page", isAudible: false)
        #expect(!navTile.link.isEmpty)
        #expect(!navTile.isAudible)

        let audibleNavTile = TileEntry(key: "food", link: "food_page", isAudible: true)
        #expect(!audibleNavTile.link.isEmpty)
        #expect(audibleNavTile.isAudible)
    }

    @Test func bootstrapLoaderIntegration() throws {
        let container = try makeTestContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)

        #expect(result.tiles.count > 400)
        #expect(result.pages.count > 5)

        let homePage = result.pages.first { $0.key == "home" }
        #expect(homePage != nil)
        #expect(homePage!.tiles.count > 0)

        let snackTile = result.tiles.first { $0.key == "snack" }
        #expect(snackTile != nil)
        #expect(snackTile!.displayName == "snack")
    }

    @Test func bootstrapCreatesDefaultScene() throws {
        let container = try makeTestContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)

        #expect(result.scene.isDefault)
        #expect(result.scene.isActive)
        #expect(result.scene.name == "Core-First")
        #expect(result.scene.homePageKey == "home")
        // Core-First is now sourced from scenes/core_first.json — 13 pages:
        // home + food_drinks + 11 topic pages (people/social/actions/describe/
        // food/drinks/places/play_activities/body_health/colors_shapes/weather).
        // result.pages is the same materialized list, so the counts match.
        #expect(result.scene.pages.count == result.pages.count)
        #expect(result.scene.pages.count == 13)
        // The bundled scene is tagged as system-defined.
        #expect(result.scene.systemSceneKey == "core_first")
    }

    @Test func bundledTopicPagesKeepHomeLinkLiteral() throws {
        // Step J: <home> is no longer rewritten at scene-build time. Topic-page
        // back tiles store the literal "<home>" token; TileGridView resolves it
        // to the active scene's homePageKey at navigation time.
        let container = try makeTestContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
        let people = result.scene.pages.first { $0.key == "people" }
        #expect(people != nil)
        let backTile = people?.tiles.first { $0.key == "home" }
        #expect(backTile?.link == "<home>")
    }

    @Test func userSceneHasNoSystemKey() throws {
        // Only bundled scenes carry a systemSceneKey; hand-built ones don't.
        let scene = BlasterScene(name: "Therapy", homePageKey: "home")
        #expect(scene.systemSceneKey == "")
    }

    @Test func duplicateProducesPeerCopyWithProvenance() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let source = BlasterScene(name: "Core-First",
                                   descriptionText: "built-in",
                                   homePageKey: "home",
                                   isDefault: true,
                                   isActive: true)
        source.systemSceneKey = "core_first"
        source.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]
        context.insert(source)

        let copy = BlasterScene.duplicate(of: source, in: context, authorID: "test-author", authorName: "Tester")
        #expect(copy.name == "duplicate-of:Core-First")
        #expect(copy.descriptionText.hasPrefix("duplicated from Core-First::"))
        #expect(copy.homePageKey == "home")
        // Duplicates are never the active or default scene, and they shed the
        // systemSceneKey so they're not protected by the force-refresh path.
        #expect(copy.isDefault == false)
        #expect(copy.isActive == false)
        #expect(copy.systemSceneKey == "")
        // Deep page copy: same content, independent storage.
        #expect(copy.pages.count == 1)
        #expect(copy.pages.first?.tiles.first?.key == "eat")
    }

    @Test func duplicateCollisionUsesSuffix() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let source = BlasterScene(name: "Core-First", homePageKey: "home")
        context.insert(source)
        try context.save()

        let first = BlasterScene.duplicate(of: source, in: context, authorID: "test-author", authorName: "Tester")
        try context.save()
        #expect(first.name == "duplicate-of:Core-First")

        let second = BlasterScene.duplicate(of: source, in: context, authorID: "test-author", authorName: "Tester")
        try context.save()
        #expect(second.name == "duplicate-of:Core-First-2")

        let third = BlasterScene.duplicate(of: source, in: context, authorID: "test-author", authorName: "Tester")
        try context.save()
        #expect(third.name == "duplicate-of:Core-First-3")
    }

    @Test func sceneActivationDeactivatesOthers() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let scene1 = BlasterScene(name: "Default", isDefault: true, isActive: true)
        let scene2 = BlasterScene(name: "Therapy", isActive: false)
        context.insert(scene1)
        context.insert(scene2)

        try scene2.activate(context: context)

        #expect(!scene1.isActive)
        #expect(scene2.isActive)
    }

    @Test func deactivateRestoresDefault() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let defaultScene = BlasterScene(name: "Default", isDefault: true, isActive: false)
        let therapyScene = BlasterScene(name: "Therapy", isActive: true)
        context.insert(defaultScene)
        context.insert(therapyScene)

        try therapyScene.deactivateAndRestoreDefault(context: context)

        #expect(!therapyScene.isActive)
        #expect(defaultScene.isActive)
    }

    @Test func sceneOwnsPages() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tile = TileModel(key: "eat", wordClass: "actions")
        let page = PageSpec(key: "therapy_page",
                            tiles: [TileEntry(key: "eat", link: "", isAudible: true)])

        let scene = BlasterScene(name: "Therapy Session", homePageKey: "therapy_page")
        scene.pages = [page]

        context.insert(tile)
        context.insert(scene)

        #expect(scene.pages.count == 1)
        #expect(scene.pages.first?.key == "therapy_page")
        #expect(scene.homePageKey == "therapy_page")
    }
}
}
