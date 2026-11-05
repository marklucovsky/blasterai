// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageCoverTests.swift
//  claudeBlastTests
//
//  A page's cover (`PageCover`): its default, folders following it, and the
//  `[word] > page` override in a cell.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PageCoverTests {

    /// Every BlasterAI 60 page has its cover written down, and it is the
    /// picture its folder already showed — including the pages a folder in the
    /// inherited row opens, which no stored page holds, and the pages only a
    /// spoken word opens.
    @Test func blasterAI60sCoversAreItsFolders() {
        let ctx = TestStore.freshContext()
        let scene = BootstrapLoader.loadDefaultVocabulary(context: ctx).scene
        #expect(scene.pages.allSatisfy { !$0.cover.isEmpty })
        func cover(_ key: String) -> String? { scene.page(withKey: key)?.cover }
        #expect(cover("places") == "places")
        #expect(cover("small_words") == "folder_small_words")
        #expect(cover("people_family") == "folder_family")
        #expect(cover("questions") == "question")
        #expect(cover("food") == "eat")
    }

    private let pages = [
        PageSpec(key: "home", tiles: [TileEntry(key: "folder_zoo", link: "zoo", isAudible: false),
                                      TileEntry(key: "lion", link: "zoo", isAudible: false),
                                      TileEntry(key: "go", link: "zoo")]),
        PageSpec(key: "zoo", tiles: [TileEntry(key: "lion")]),
    ]

    @Test func theDefaultIsTheFolderThatOpensThePage() {
        #expect(PageCover.key(of: pages[1], in: pages) == "folder_zoo")
        #expect(PageCover.key(of: pages[0], in: pages) == PageLink.key(forPage: "home"))
    }

    /// The folders showing the old cover move with it; one showing something
    /// else was chosen, and stays; a spoken doorway is not a folder.
    @Test func defaultFoldersFollowANewCover() {
        let moved = PageCover.setting("tiger", forPage: "zoo", in: pages)
        #expect(moved[1].cover == "tiger")
        #expect(moved[0].tiles.map(\.key) == ["tiger", "lion", "go"])
    }

    @Test func aPictureInBracketsIsAFolderShowingThatWord() {
        let parsed = BoardCell.parse("[lion] > zoo")
        #expect(parsed == .cell(word: nil, link: .init(page: "zoo", isSystem: false, picture: "lion")))
        let lookup = ["lion": TileModel(key: "lion", value: "lion", wordClass: "animal"),
                      "folder_zoo": TileModel(key: "folder_zoo", value: "Zoo", wordClass: "navigation")]
        guard case .plan(let plan) = BoardCell.resolve(parsed, lookup: lookup, scenePages: pages, systemPages: [PageSpec(key: "x", tiles: [])]) else {
            Issue.record("no plan"); return
        }
        #expect(plan.entry.key == "lion")
        #expect(plan.entry.isAudible == false)
        #expect(plan.entry.link == "zoo")
        if case .invalid = BoardCell.parse("[lion]") {} else { Issue.record("a picture with no page parsed") }
    }

    /// A folder showing its page's cover is written `> page`; one showing
    /// anything else says which picture.
    @Test func formatSaysWhenAFolderIsNotItsPagesCover() {
        let cover = BoardCell.covers(scenePages: pages, systemPages: [PageSpec(key: "x", tiles: [])])
        #expect(BoardCell.format(pages[0].tiles[0], cover: cover) == "> zoo")
        #expect(BoardCell.format(pages[0].tiles[1], cover: cover) == "[lion] > zoo")
        #expect(BoardCell.format(pages[0].tiles[2], cover: cover) == "go > zoo")
    }

    /// A typed `> zoo` shows the page's cover.
    @Test func aTypedFolderShowsThePagesCover() {
        var withCover = pages
        withCover[1].cover = "tiger"
        let lookup = ["tiger": TileModel(key: "tiger", value: "tiger", wordClass: "animal")]
        guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse("> zoo"), lookup: lookup,
                                                      scenePages: withCover, systemPages: [PageSpec(key: "x", tiles: [])]) else {
            Issue.record("no plan"); return
        }
        #expect(plan.entry.key == "tiger")
    }

    /// The scene preview follows a `sys:` link into BlasterAI 60, and a plain
    /// link on that system page stays in BlasterAI 60.
    @Test func thePreviewFollowsSystemLinks() {
        let scene = BlasterScene(name: "S")
        scene.pages = [PageSpec(key: "home", tiles: [])]
        let system = [PageSpec(key: "home", tiles: []), PageSpec(key: "i_page", tiles: []),
                      PageSpec(key: "actions", tiles: [])]
        let sysI = TileToken.systemLink(to: "i_page")
        #expect(ScenePreviewBoardView.destination(of: sysI, fromPage: "home", scene: scene,
                                                  systemPages: system, systemHomePageKey: "home") == sysI)
        #expect(ScenePreviewBoardView.destination(of: "actions", fromPage: sysI, scene: scene,
                                                  systemPages: system, systemHomePageKey: "home")
                == TileToken.systemLink(to: "actions"))
        #expect(ScenePreviewBoardView.destination(of: TileToken.home, fromPage: sysI, scene: scene,
                                                  systemPages: system, systemHomePageKey: "home") == "home")
        #expect(ScenePreviewBoardView.destination(of: TileToken.systemLink(to: "nowhere"), fromPage: "home",
                                                  scene: scene, systemPages: system, systemHomePageKey: "home") == nil)
    }

    /// A page's own picture is a tile of its scene: a copy shares it until it
    /// picks its own, and making one keeps the picture the page had.
    @Test func aPagesOwnCoverIsItsScenes() throws {
        let ctx = TestStore.freshContext()
        let folder = TileModel(key: "folder_zoo", value: "Zoo", wordClass: "navigation")
        ctx.insert(folder)
        let a = BlasterScene(name: "A"); a.sceneID = "me/a"; a.pages = pages
        let b = BlasterScene(name: "B"); b.sceneID = "me/b"; b.pages = pages
        ctx.insert(a); ctx.insert(b)
        #expect(PageCover.ownKey(forPage: "zoo", in: a) != PageCover.ownKey(forPage: "zoo", in: b))
        let own = PageCover.ensureOwn(forPage: "zoo", in: a, context: ctx)
        #expect(own.key == "pagecover_me_a_zoo")
        #expect(own.bundleImage == "folder_zoo")
        #expect(a.page(withKey: "zoo")?.cover == own.key)
        #expect(a.page(withKey: "home")?.tiles.first?.key == own.key)
        #expect(b.page(withKey: "home")?.tiles.first?.key == "folder_zoo")
    }
}
}
