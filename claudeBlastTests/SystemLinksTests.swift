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
