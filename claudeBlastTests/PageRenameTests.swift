// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageRenameTests.swift
//  claudeBlastTests
//
//  A page's name is a label; its key is its identity.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PageRenameTests {

    @Test("An unnamed page shows a name derived from its key")
    func derivedTitle() {
        let page = PageSpec(key: "play_activities", tiles: [])
        #expect(page.title == "Play Activities")
        #expect(!page.hasCustomName)
    }

    @Test("A named page shows the name")
    func customTitle() {
        let page = PageSpec(key: "play_activities", displayName: "Recess", tiles: [])
        #expect(page.title == "Recess")
        #expect(page.hasCustomName)
    }

    /// Clearing the name is the undo, so it has to restore the derived form
    /// rather than leave the page blank.
    @Test("Clearing the name goes back to the derived one")
    func clearingRestoresDerived() {
        var page = PageSpec(key: "play_activities", displayName: "Recess", tiles: [])
        page.displayName = ""
        #expect(page.title == "Play Activities")
    }

    /// Keys are unique, names are not. Forbidding duplicates would only produce
    /// "Food " with a trailing space.
    @Test("Two pages may share a name")
    func namesNeedNotBeUnique() {
        let a = PageSpec(key: "food", displayName: "Food", tiles: [])
        let b = PageSpec(key: "snacks", displayName: "Food", tiles: [])
        #expect(a.title == b.title)
        #expect(a.key != b.key)
        #expect(a.id != b.id, "identity must still come from the key")
    }

    // MARK: - Everything that points at a page keeps pointing at it

    /// The reason rename does not touch the key. Each of these is a reference
    /// that a key change would break or, worse, silently rewrite.
    @Test("Renaming leaves every reference intact")
    func referencesSurviveARename() {
        var scene = [
            PageSpec(key: "home", tiles: [TileEntry(key: "page_food", link: "food")]),
            PageSpec(key: "food", tiles: [TileEntry(key: "pizza")]),
        ]
        let homePageKey = "home"

        scene[1].displayName = "Dinner"

        #expect(scene[1].key == "food", "the key is identity and must not move")
        #expect(scene[0].tiles[0].link == "food", "a link still resolves")
        #expect(scene.contains { $0.key == homePageKey })
        #expect(PageLink.key(forPage: scene[1].key) == "page_food",
                "the minted link tile keeps its key")
        #expect(scene[1].title == "Dinner")
    }

    // MARK: - Transfer

    @Test("A page name survives export and import")
    func nameRoundTrips() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        let pizza = TileModel(key: "pizza", wordClass: "food")
        context.insert(pizza)

        let scene = BlasterScene(name: "Test", descriptionText: "", homePageKey: "food")
        scene.pages = [PageSpec(key: "food", displayName: "Dinner",
                                tiles: [TileEntry(key: "pizza")])]
        context.insert(scene)

        let exportable = SceneExporter.export(scene, defaultTileKeys: ["pizza"],
                                              tileLookup: ["pizza": pizza])
        #expect(exportable.pages.first?.displayName == "Dinner")

        let data = try JSONEncoder().encode(exportable)
        let result = try SceneImporter.importJSON(data, context: context)
        let landed = try #require(result.scene.pages.first)
        #expect(landed.key == "food")
        #expect(landed.title == "Dinner")
    }

    /// A page still using its derived name adds nothing to the wire.
    @Test("An unnamed page carries no name on the wire")
    func unnamedPageOmitsTheField() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        let pizza = TileModel(key: "pizza", wordClass: "food")
        context.insert(pizza)

        let scene = BlasterScene(name: "Test", descriptionText: "", homePageKey: "food")
        scene.pages = [PageSpec(key: "food", tiles: [TileEntry(key: "pizza")])]
        context.insert(scene)

        let exportable = SceneExporter.export(scene, defaultTileKeys: ["pizza"],
                                              tileLookup: ["pizza": pizza])
        #expect(exportable.pages.first?.displayName == nil)
    }

    /// The case that fails in a stranger's hands: a file written before rename
    /// existed. Swift's synthesized decoder would throw on the missing key.
    @Test("A scene file without page names still imports")
    func legacyFileImports() throws {
        let json = """
        {"@type":"\(BlasterSceneFormat.mediaType)","version":"\(BlasterSceneFormat.currentVersion)",\
        "name":"Legacy","description":"","homePageKey":"food",\
        "pages":[{"key":"food","tiles":[{"key":"pizza","isAudible":true,"link":""}]}],"tiles":[]}
        """
        let container = TestStore.freshContainer()
        let context = container.mainContext
        context.insert(TileModel(key: "pizza", wordClass: "food"))

        let result = try SceneImporter.importJSON(Data(json.utf8), context: context)
        let page = try #require(result.scene.pages.first)
        #expect(page.title == "Food", "a legacy page falls back to its derived name")
        #expect(!page.hasCustomName)
    }

    // MARK: - Print

    @Test("A printed sheet is captioned with the page's name")
    func printedSheetUsesTheName() {
        let sheets = BoardPagination.paginate(
            [PageSpec(key: "play_activities", displayName: "Recess",
                      tiles: [TileEntry(key: "ball")])],
            perSheet: 10)
        #expect(sheets.first?.caption == "Recess")
    }

    @Test("An unnamed page still captions from its key")
    func printedSheetFallsBack() {
        let sheets = BoardPagination.paginate(
            [PageSpec(key: "play_activities", tiles: [TileEntry(key: "ball")])],
            perSheet: 10)
        #expect(sheets.first?.caption == "Play Activities")
    }
}
}
