// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CopyOnWriteTests.swift
//  claudeBlastTests
//
//  A copy of BlasterAI 60 is sparse; a core-board page becomes the scene's
//  own only when it is edited, and every link to it then opens the copy.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CopyOnWriteTests {

    /// A small BlasterAI 60: Home opens Actions and People; Actions opens
    /// Feelings and goes back Home.
    private func makeSystem() -> BlasterScene {
        let s = BlasterScene(name: "BlasterAI 60", homePageKey: "home", isDefault: true, isActive: false)
        s.systemSceneKey = "core_first"
        s.pages = [
            PageSpec(key: "home", tiles: [
                TileEntry(key: "actions", link: "actions", isAudible: false),
                TileEntry(key: "people", link: "people", isAudible: false),
                TileEntry(key: "want"),
            ]),
            PageSpec(key: "actions", tiles: [
                TileEntry(key: "eat"),
                TileEntry(key: "feelings", link: "feelings", isAudible: false),
                TileEntry(key: "home", link: "home", isAudible: false),
            ]),
            PageSpec(key: "people", tiles: [TileEntry(key: "mom")]),
            PageSpec(key: "feelings", tiles: [TileEntry(key: "happy")]),
        ]
        return s
    }

    // MARK: - Copy

    @Test func aCopyOfBlasterAI60HoldsOnlyHome() {
        let ctx = TestStore.freshContext()
        let system = makeSystem()
        ctx.insert(system)

        let copy = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")

        #expect(copy.pages.map(\.key) == ["home"])
        #expect(copy.homePageKey == "home")
        // Its doorways now name the core board's pages.
        #expect(copy.pages[0].tiles.map(\.link) == ["<system>:actions", "<system>:people", ""])
    }

    /// Duplicate and Make a Copy make the same copy.
    @Test func duplicateMakesTheSameSparseCopy() {
        let ctx = TestStore.freshContext()
        let system = makeSystem()
        ctx.insert(system)

        let made = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")
        let dup = BlasterScene.duplicate(of: system, in: ctx, authorID: "a", authorName: "")

        #expect(dup.pages == made.pages)
    }

    /// Edit This Page on BlasterAI 60 copies the page being edited along.
    @Test func aCopyForEditThisPageBringsThatPage() {
        let ctx = TestStore.freshContext()
        let system = makeSystem()
        ctx.insert(system)

        let copy = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "",
                                                alsoShadowing: "actions")

        #expect(copy.pages.map(\.key) == ["home", "actions"])
        let actions = copy.pages[1]
        #expect(actions.shadows == "actions")
        #expect(actions.tiles.map(\.link) == ["", "<system>:feelings", TileToken.home])
    }

    /// Any other scene copies whole, as before.
    @Test func anOrdinarySceneStillCopiesWhole() {
        let ctx = TestStore.freshContext()
        let zoo = BlasterScene(name: "Zoo", homePageKey: "home", isDefault: false, isActive: false)
        zoo.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "lion", link: "cats", isAudible: false)]),
                     PageSpec(key: "cats", tiles: [TileEntry(key: "lion")])]
        ctx.insert(zoo)

        let dup = BlasterScene.duplicate(of: zoo, in: ctx, authorID: "a", authorName: "")

        #expect(dup.pages == zoo.pages)
    }

    // MARK: - Shadow

    @Test func editingASystemPageCopiesItOnce() {
        let ctx = TestStore.freshContext()
        let system = makeSystem()
        ctx.insert(system)
        let copy = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")
        let actions = system.page(withKey: "actions")!

        let key = copy.shadowSystemPage(actions, systemHomePageKey: "home")
        let again = copy.shadowSystemPage(actions, systemHomePageKey: "home")

        #expect(key == "actions")
        #expect(again == key)
        #expect(copy.pages.count == 2)
        #expect(copy.shadowedSystemKeys == ["actions"])
    }

    /// A scene page that merely shares the name is not replaced or shadowing.
    @Test func aShadowKeepsClearOfAPageOfTheSameName() {
        let ctx = TestStore.freshContext()
        let system = makeSystem()
        let zoo = BlasterScene(name: "Zoo", homePageKey: "home", isDefault: false, isActive: false)
        zoo.pages = [PageSpec(key: "home", tiles: []), PageSpec(key: "actions", tiles: [TileEntry(key: "roar")])]
        ctx.insert(system); ctx.insert(zoo)

        let key = zoo.shadowSystemPage(system.page(withKey: "actions")!, systemHomePageKey: "home")

        #expect(key == "actions_2")
        #expect(zoo.page(withKey: "actions")?.isShadow == false)
        #expect(zoo.shadowPage(for: "actions")?.key == "actions_2")
    }

    // MARK: - Where links go

    @Test func aSystemLinkOpensTheScenesCopy() {
        let system = makeSystem()
        var own = system.page(withKey: "actions")!
        own.key = "actions"; own.shadows = "actions"
        own.tiles.append(TileEntry(key: "dance"))

        let shown = SystemLinks.page(forKey: "<system>:actions", scenePages: [own],
                                     systemPages: system.pages)
        let other = SystemLinks.page(forKey: "<system>:people", scenePages: [own],
                                     systemPages: system.pages)

        #expect(shown?.tiles.map(\.key).contains("dance") == true)
        #expect(other?.key == "people")
    }

    /// On the scene's copy a plain link is a page of the scene; on BlasterAI
    /// 60's own page it is a page of the core board.
    @Test func aPlainLinkOnTheCopyIsTheScenes() {
        let onCopy = SystemLinks.destination(of: "farm", fromPage: "<system>:actions",
                                             homePageKey: "home", systemHomePageKey: "home",
                                             shadowed: ["actions"])
        let onOriginal = SystemLinks.destination(of: "feelings", fromPage: "<system>:actions",
                                                 homePageKey: "home", systemHomePageKey: "home")
        #expect(onCopy == "farm")
        #expect(onOriginal == "<system>:feelings")
    }

    // MARK: - Files

    /// A page saved before `shadows` existed reads as an ordinary page, and a
    /// shadow survives the round trip.
    @Test func shadowsSurviveEncodingAndOldPagesDecode() throws {
        let old = #"{"key":"actions","tiles":[]}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PageSpec.self, from: old).shadows == "")

        let page = PageSpec(key: "actions_2", tiles: [], shadows: "actions")
        let back = try JSONDecoder().decode(PageSpec.self, from: JSONEncoder().encode(page))
        #expect(back.shadows == "actions")
    }

    /// Outside the app the core-board pages a scene reaches come along, and
    /// every link names the page it now opens.
    @Test func anExportBringsTheReachableSystemPages() {
        let system = makeSystem()
        let home = PageSpec(key: "home", tiles: [
            TileEntry(key: "actions", link: "<system>:actions", isAudible: false),
            TileEntry(key: "lion"),
        ])
        var feelings = PageSpec(key: "feelings", tiles: [TileEntry(key: "sad")])
        feelings.shadows = ""   // the scene's own page of that name, not a copy

        let whole = ExportPages(scenePages: [home, feelings], systemPages: system.pages,
                                systemHomePageKey: "home")

        #expect(whole.pages.map(\.key) == ["home", "feelings", "actions", "blasterai_feelings"])
        #expect(whole.pages[0].tiles[0].link == "actions")
        let actions = whole.pages[2]
        #expect(actions.tiles.map(\.link) == ["", "blasterai_feelings", TileToken.home])
        // People is not reached, so it stays behind.
        #expect(!whole.pages.contains { $0.key == "people" })
    }

    /// The scene's copy is exported, not BlasterAI 60's page it replaced.
    @Test func anExportUsesTheScenesCopy() {
        let system = makeSystem()
        let home = PageSpec(key: "home", tiles: [TileEntry(key: "actions", link: "<system>:actions", isAudible: false)])
        let own = PageSpec(key: "actions", tiles: [TileEntry(key: "dance")], shadows: "actions")

        let whole = ExportPages(scenePages: [home, own], systemPages: system.pages, systemHomePageKey: "home")

        #expect(whole.pages.map(\.key) == ["home", "actions"])
        #expect(whole.pages[1].tiles.map(\.key) == ["dance"])
    }

    /// A page shared on its own prints with what it opens, through the core
    /// board too, and stops at Home.
    @Test func aPagePrintsWithThePagesItOpens() {
        let system = makeSystem()
        let home = PageSpec(key: "home", tiles: [TileEntry(key: "lion", link: "cats", isAudible: false)])
        let me = PageSpec(key: "me", tiles: [
            TileEntry(key: "actions", link: "<system>:actions", isAudible: false),
            TileEntry(key: "lion", link: "cats", isAudible: false),
            TileEntry(key: "home", link: TileToken.home, isAudible: false),
        ])
        let cats = PageSpec(key: "cats", tiles: [TileEntry(key: "lion")])

        let whole = ExportPages(scenePages: [home, me, cats], systemPages: system.pages,
                                systemHomePageKey: "home")

        #expect(whole.reachable(from: "me").map(\.key) == ["me", "actions", "feelings", "cats"])
    }

    @Test func anOpenBoardExportOfACopyCarriesTheCoreBoard() {
        let ctx = TestStore.freshContext()
        var lookup: [String: TileModel] = [:]
        for key in ["actions", "people", "want", "eat", "feelings", "home", "mom", "happy"] {
            let t = TileModel(key: key, value: key, wordClass: "actions")
            ctx.insert(t); lookup[key] = t
        }
        let system = makeSystem()
        ctx.insert(system)
        let copy = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")

        let built = OBFExporter.boards(for: copy, tileLookup: lookup,
                                       systemPages: system.pages, systemHomePageKey: "home")

        #expect(Set(built.boards.compactMap(\.ext_blasterai_page_key)) == ["home", "actions", "people", "feelings"])
        let home = built.boards.first { $0.ext_blasterai_page_key == "home" }
        let actions = home?.buttons.first { $0.ext_blasterai_tile_key == "actions" }
        #expect(actions?.load_board?.path == "boards/actions.\(OBFFormat.boardExtension)")
    }
}
}
