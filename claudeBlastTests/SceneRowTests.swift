// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneRowTests.swift
//  claudeBlastTests
//
//  A scene's own row 1: stored with its pages but not one of them, drawn in
//  place of BlasterAI 60's, and carried by copies, share files and
//  spreadsheets.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneRowTests {

    private func makeScene() -> BlasterScene {
        let s = BlasterScene(name: "Sunday School", homePageKey: "home", isDefault: false, isActive: false)
        s.designedFor = "ipad-10x6"
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "pray")]),
                   PageSpec(key: "bible", tiles: [TileEntry(key: "jesus")])]
        return s
    }

    private func ownRow() -> PageSpec {
        PageSpec(key: BlasterScene.rowPageKey, tiles: [
            TileEntry(key: "bible", link: "bible", isAudible: false),
            TileEntry(key: "actions", link: "<system>:actions", isAudible: false),
            TileEntry(key: "yes"),
        ])
    }

    // MARK: - Storage

    @Test func theRowIsKeptApartFromThePages() {
        let scene = makeScene()
        scene.ownRow = ownRow()

        #expect(scene.pages.map(\.key) == ["home", "bible"])
        #expect(scene.ownRow?.tiles.count == 3)

        // Writing the pages keeps the row; clearing the row keeps the pages.
        var pages = scene.pages
        pages.append(PageSpec(key: "songs", tiles: []))
        scene.pages = pages
        #expect(scene.ownRow?.tiles.count == 3)
        scene.ownRow = nil
        #expect(scene.ownRow == nil)
        #expect(scene.pages.map(\.key) == ["home", "bible", "songs"])
    }

    @Test func theEditorWritesTheRowLikeAPage() {
        let scene = makeScene()
        scene.ownRow = ownRow()

        scene.updatePage(BlasterScene.rowPageKey) { $0.tiles.append(TileEntry(key: "no")) }

        #expect(scene.editablePage(BlasterScene.rowPageKey)?.tiles.map(\.key) == ["bible", "actions", "yes", "no"])
        #expect(scene.pages.count == 2)
    }

    // MARK: - Drawing

    @Test func aSceneWithItsOwnRowDrawsIt() {
        let scene = makeScene()
        let inherited = BoardChrome.row(for: scene, level: nil)
        #expect(inherited.map(\.key) == BoardChrome.row(inSystemScene: false).map(\.key))

        scene.ownRow = ownRow()

        #expect(BoardChrome.row(for: scene, level: nil).filter { !$0.isSpacer }.map(\.key)
                == ["bible", "actions", "yes"])
        // Its own pages are ways in from every page; its links into the core
        // board are the system pages it reaches.
        #expect(BoardChrome.rowPages(of: scene) == ["bible"])
        #expect(BoardChrome.systemPageKeys(of: scene) == ["actions"])
    }

    /// A bar stored as far as its last word still takes the grid's width, so
    /// a page laid out after it starts on the next row.
    @Test func aShortBarFillsTheGridWidth() {
        let scene = makeScene()
        scene.ownRow = ownRow()

        let bar = BoardChrome.row(for: scene, level: nil)
        #expect(bar.count == 10)
        #expect(bar.suffix(7).allSatisfy { $0.isSpacer })
        // The same gaps every time, so the views are not rebuilt.
        #expect(BoardChrome.row(for: scene, level: nil).map(\.key) == bar.map(\.key))
    }

    /// `> people` to a scene's own People page shows People's picture, and
    /// `> love` the word's; a name nothing has keeps its initial.
    @Test func aNewFolderBorrowsAPicture() {
        let system = [PageSpec(key: "home", tiles: [TileEntry(key: "people", link: "people", isAudible: false)]),
                      PageSpec(key: "people", tiles: [])]
        let lookup = ["love": TileModel(key: "love", value: "love", wordClass: "feeling")]

        #expect(BoardCell.borrowedCover(forPage: "people", systemPages: system, lookup: lookup) == "people")
        #expect(BoardCell.borrowedCover(forPage: "love", systemPages: system, lookup: lookup) == "love")
        #expect(BoardCell.borrowedCover(forPage: "locations", systemPages: system, lookup: lookup) == nil)
    }

    /// `love > people` on Home must not make love the picture of the first
    /// real folder to People: that borrows People's.
    @Test func aSpokenLinkDoesNotPictureTheFolder() {
        let system = [PageSpec(key: "home", tiles: [TileEntry(key: "people", link: "people", isAudible: false)]),
                      PageSpec(key: "people", tiles: [])]
        let scenePages = [PageSpec(key: "home", tiles: [TileEntry(key: "love", link: "people", isAudible: true)]),
                          PageSpec(key: "people", tiles: [])]
        let lookup = Dictionary(uniqueKeysWithValues: ["love", "people"].map {
            ($0, TileModel(key: $0, value: $0, wordClass: "people"))
        })

        guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse("> people"), lookup: lookup,
                                                       scenePages: scenePages, systemPages: system)
        else { Issue.record("no plan"); return }
        #expect(plan.entry.key == "people")
    }

    /// A word above the board's level is an empty cell, as on a page.
    @Test func theRowFollowsTheLevel() {
        let scene = makeScene()
        var row = ownRow()
        row.tiles[2].revealLevel = 3
        scene.ownRow = row

        let shown = BoardChrome.row(for: scene, level: 2)
        #expect(shown[2].isConcealed)
        #expect(!shown[0].isConcealed)
    }

    /// Making the row your own starts from BlasterAI 60's, opening its pages.
    @Test func makingTheRowYourOwnStartsFromBlasterAI60s() {
        let start = BoardChrome.ownRowStart()
        #expect(start.key == BlasterScene.rowPageKey)
        #expect(start.tiles.map(\.link) == BoardChrome.pageKeys.map(TileToken.systemLink(to:)))
    }

    // MARK: - Copies and files

    @Test func aDuplicateKeepsTheRow() {
        let ctx = TestStore.freshContext()
        let scene = makeScene()
        scene.ownRow = ownRow()
        ctx.insert(scene)

        let dup = BlasterScene.duplicate(of: scene, in: ctx, authorID: "a", authorName: "")

        #expect(dup.ownRow?.tiles.map(\.key) == ["bible", "actions", "yes"])
    }

    @Test func aSharedSceneCarriesItsRow() throws {
        let ctx = TestStore.freshContext()
        var lookup: [String: TileModel] = [:]
        for key in ["pray", "jesus", "bible", "actions", "yes"] {
            let t = TileModel(key: key, value: key, wordClass: "object")
            ctx.insert(t); lookup[key] = t
        }
        let scene = makeScene()
        scene.ownRow = ownRow()
        ctx.insert(scene)

        let file = SceneExporter.export(scene, tileLookup: lookup)
        #expect(file.pages.map(\.key).contains(BlasterScene.rowPageKey))

        // Arrives as a new scene on a device that never had it.
        ctx.delete(scene)
        try ctx.save()
        let result = try SceneImporter.importJSON(JSONEncoder().encode(file), context: ctx)

        #expect(result.scene.pages.map(\.key) == ["home", "bible"])
        #expect(result.scene.ownRow?.tiles.map(\.key) == ["bible", "actions", "yes"])
    }

    @Test func aSystemRowTabIsTheRow() {
        #expect(BoardWorkbook.isRowTab("SystemRow"))
        #expect(BoardWorkbook.isRowTab("system row"))
        #expect(BoardWorkbook.isRowTab("Row 1"))
        #expect(BoardWorkbook.isRowTab("Navigation Bar"))
        #expect(BoardWorkbook.isRowTab("navbar"))
        #expect(!BoardWorkbook.isRowTab("Rows"))

        let lookup = Dictionary(uniqueKeysWithValues: ["yes", "no", "pray"].map {
            ($0, TileModel(key: $0, value: $0, wordClass: "social"))
        })
        let tabs = [SpreadsheetTab(name: "SystemRow", rows: [["yes", "no"]]),
                    SpreadsheetTab(name: "home", rows: [["pray"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: [])

        #expect(preview.pages.map(\.key) == [BlasterScene.rowPageKey, "home"])
        #expect(preview.homeKey == "home")
    }

    @Test func aSpreadsheetExportWritesTheRowTab() {
        let scene = makeScene()
        let tabs = BoardWorkbook.tabs(for: scene.pages, homeKey: "home", cols: 10, row: ownRow())
        let row = tabs.first { $0.name == BoardWorkbook.rowTab }
        #expect(row?.rows.first?.count == 3)
        #expect(tabs.map(\.name).first == "home")
    }
}
}
