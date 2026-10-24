// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SystemLinksTests.swift
//  claudeBlastTests
//
//  Links from any scene into BlasterAI 60's own pages.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SystemLinksTests {

    private let sceneHome = "zoo"
    private let systemHome = "home"

    private func destination(_ link: String, from page: String) -> String {
        SystemLinks.destination(of: link, fromPage: page,
                                homePageKey: sceneHome, systemHomePageKey: systemHome)
    }

    // MARK: - Where a tap goes

    @Test func aSystemLinkIsItsOwnDestination() {
        #expect(destination("<system>:actions", from: sceneHome) == "<system>:actions")
    }

    @Test func aFolderOnASystemPageStaysInTheSystemScene() {
        // Groups → Animals on BlasterAI 60, reached from a zoo scene.
        #expect(destination("animals", from: "<system>:groups") == "<system>:animals")
    }

    @Test func theSystemHomeFromASystemPageIsTheScenesHome() {
        #expect(destination("home", from: "<system>:keyboard") == sceneHome)
        #expect(destination(TileToken.home, from: "<system>:actions") == sceneHome)
    }

    @Test func anOrdinaryLinkStaysInTheScene() {
        #expect(destination("animals", from: sceneHome) == "animals")
        #expect(destination(TileToken.home, from: "animals") == sceneHome)
    }

    // MARK: - Which page shows

    @Test func aSystemKeyShowsTheSystemScenesPage() {
        let scenePages = [PageSpec(key: "actions", tiles: [TileEntry(key: "roar")])]
        let systemPages = [PageSpec(key: "actions", tiles: [TileEntry(key: "run")])]
        let system = SystemLinks.page(forKey: "<system>:actions",
                                      scenePages: scenePages, systemPages: systemPages)
        let own = SystemLinks.page(forKey: "actions",
                                   scenePages: scenePages, systemPages: systemPages)
        #expect(system?.tiles.map(\.key) == ["run"])
        #expect(own?.tiles.map(\.key) == ["roar"])
    }

    @Test func everySystemRowLinkOpensABundledPage() {
        // The row a scene copies from BlasterAI 60's home must point at pages
        // that exist, or a child taps a folder that does nothing.
        let scene = BootstrapLoader.loadDefaultVocabulary(
            context: TestStore.freshContainer().mainContext).scene
        let home = try? #require(scene.page(withKey: scene.homePageKey))
        let links = (home?.tiles ?? []).filter { !$0.link.isEmpty }
        #expect(!links.isEmpty)
        for entry in links {
            let page = SystemLinks.page(forKey: TileToken.systemLink(to: entry.link),
                                        scenePages: [], systemPages: scene.pages)
            #expect(page != nil, "no BlasterAI 60 page for \(entry.link)")
        }
    }

    @Test func aSystemLinkReadsAsTheCoreBoard() {
        #expect(SystemLinks.displayName(of: "<system>:time_when") == "BlasterAI › Time When")
        #expect(SystemLinks.displayName(of: "animals") == "Animals")
    }

    // MARK: - One dial for both boards

    /// A zoo scene with `levels` levels whose home links to the core board's
    /// Actions, and a core board with 5: Actions holds a word per level, and a
    /// Groups page nothing links to.
    private func boards(levels: Int, linked: Bool = true) -> (BlasterScene, BlasterScene) {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let system = BlasterScene(name: "BlasterAI 60", descriptionText: "", homePageKey: "home")
        system.isDefault = true
        system.pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "actions", link: "actions", isAudible: false)]),
            PageSpec(key: "actions", tiles: (1...5).map { TileEntry(key: "verb\($0)", revealLevel: $0) }),
            PageSpec(key: "groups", tiles: [TileEntry(key: "animal", revealLevel: 1)]),
        ]
        system.setRevealLevelCount(5)
        let zoo = BlasterScene(name: "Zoo", descriptionText: "", homePageKey: sceneHome)
        zoo.pages = [PageSpec(key: sceneHome, tiles: [
            TileEntry(key: "lion", revealLevel: 1),
            TileEntry(key: "roar", revealLevel: 2),
            TileEntry(key: "actions", link: linked ? "<system>:actions" : "", isAudible: false),
        ])]
        zoo.setRevealLevelCount(levels)
        context.insert(system)
        context.insert(zoo)
        return (zoo, system)
    }

    @Test func theDialSpansTheWiderBoard() {
        let (zoo, system) = boards(levels: 2)
        let levels = BoardLevels(scene: zoo, system: system)
        #expect(levels.count == 5)
        levels.setLevel(4)
        #expect(levels.level == 4)
        // The zoo's own pages are at their top; the core board is at 4.
        #expect(zoo.visiblePages[0].tiles.allSatisfy { !$0.isConcealed })
        let actions = levels.systemPages.first { $0.key == "actions" }!
        #expect(actions.tiles.map(\.isConcealed) == [false, false, false, false, true])
    }

    @Test func aLowBoardOpensOntoALowCorePage() {
        let (zoo, system) = boards(levels: 2)
        let levels = BoardLevels(scene: zoo, system: system)
        levels.setLevel(1)
        #expect(zoo.visiblePages[0].tiles.map(\.isConcealed) == [false, true, false])
        let actions = levels.systemPages.first { $0.key == "actions" }!
        #expect(actions.tiles.count { !$0.isConcealed } == 1)
    }

    @Test func aBoardWithoutLevelsOpensAtTheTop() {
        let (zoo, system) = boards(levels: 0)
        let levels = BoardLevels(scene: zoo, system: system)
        #expect(levels.count == 5)
        #expect(levels.level == 5)
        #expect(levels.systemPages.flatMap(\.tiles).allSatisfy { !$0.isConcealed })
    }

    @Test func aBoardThatNeverLinksKeepsItsOwnDial() {
        let (zoo, system) = boards(levels: 2, linked: false)
        #expect(BoardLevels(scene: zoo, system: system).count == 2)
        #expect(BoardLevels(scene: zoo, system: system).systemPages.isEmpty)
        // The core board's own dial is its own.
        #expect(BoardLevels(scene: system, system: system).count == 5)
    }

    @Test func theWordCountIncludesOnlyCorePagesTheBoardReaches() {
        let (zoo, system) = boards(levels: 2)
        // Level 3: lion + roar + the Actions folder, and verb1–3. Groups is
        // unreachable, so its word does not count.
        #expect(BoardLevels(scene: zoo, system: system).visibleTileCount(atLevel: 3) == 6)
    }

    // MARK: - Away from the board

    @Test func aScriptMayNavigateIntoTheSystemScene() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        _ = BootstrapLoader.loadDefaultVocabulary(context: context)
        let yaml = """
        name: Into the core board
        description: test
        scene: "<default>"
        script:
          - tiles:
            - <<system>:actions>, <<system>:nowhere>
        """
        let script = try? TileScriptParser.parse(yaml)
        guard let script else { Issue.record("script did not parse"); return }
        let result = TileScriptValidator.validate(script, context: context)
        #expect(result.missingPages == ["<system>:nowhere"])
    }

    @Test func aSilentSystemLinkLeavesAnOBFAsAGap() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let eat = TileModel(key: "eat", value: "eat", wordClass: "actions")
        let actions = TileModel(key: "actions", value: "actions", wordClass: "actions")
        let lion = TileModel(key: "lion", value: "lion", wordClass: "animals")
        for tile in [eat, actions, lion] { context.insert(tile) }
        let scene = BlasterScene(name: "Zoo", descriptionText: "", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: [
            TileEntry(key: "actions", link: "<system>:actions", isAudible: false),
            TileEntry(key: "eat", link: "<system>:food", isAudible: true),
            TileEntry(key: "lion"),
        ])]
        context.insert(scene)

        let built = OBFExporter.boards(for: scene, tileLookup: [
            "eat": eat, "actions": actions, "lion": lion])
        let board = built.boards[0]
        let keys = board.buttons.map(\.ext_blasterai_tile_key)
        #expect(!keys.contains("actions"))
        #expect(keys.contains("eat"))
        // A word that also opened BlasterAI 60 is still a word, with nowhere to go.
        #expect(board.buttons.first { $0.ext_blasterai_tile_key == "eat" }?.load_board == nil)
    }
}
}
