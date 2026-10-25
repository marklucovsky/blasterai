// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageSchemeTests.swift
//  claudeBlastTests
//
//  Topic words → matched → placed on the page scheme, against BlasterAI 60's
//  real home and pages recorded from gpt-6.1-sol
//  (docs/eval/runs/2026-10-21-1425-gpt-6.1-sol-low-topic-t8-sol).
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PageSchemeTests {

    // MARK: - Fixtures

    /// "Watching Bluey with my sister and playing the games from the show."
    static let bluey = """
    {"refused": false, "name": "Bluey with My Sister",
     "description": "Words for watching Bluey with a sister and joining in the family's pretend games.",
     "words": [
      {"word": "Bluey", "wordClass": "people"}, {"word": "Bingo", "wordClass": "people"},
      {"word": "sister", "wordClass": "people"}, {"word": "Bandit", "wordClass": "people"},
      {"word": "Chilli", "wordClass": "people"}, {"word": "watch", "wordClass": "actions"},
      {"word": "tv", "wordClass": "object"}, {"word": "Keepy Uppy", "wordClass": "games"},
      {"word": "balloon", "wordClass": "object"}, {"word": "Magic Xylophone", "wordClass": "games"},
      {"word": "xylophone", "wordClass": "object"}, {"word": "freeze", "wordClass": "actions"},
      {"word": "Grannies", "wordClass": "games"}, {"word": "dress_up", "wordClass": "actions"},
      {"word": "blanket", "wordClass": "object"}, {"word": "Featherwand", "wordClass": "games"},
      {"word": "feather", "wordClass": "object"}, {"word": "heavy", "wordClass": "describe"},
      {"word": "Dance Mode", "wordClass": "games"}, {"word": "dance", "wordClass": "actions"},
      {"word": "catch", "wordClass": "actions"}, {"word": "jump", "wordClass": "actions"},
      {"word": "excited", "wordClass": "feeling"}, {"word": "silly", "wordClass": "feeling"},
      {"word": "frustrated", "wordClass": "feeling"}, {"word": "Chattermax", "wordClass": "toy"},
      {"word": "Floppy", "wordClass": "toy"}, {"word": "Muffin", "wordClass": "people"},
      {"word": "Socks", "wordClass": "people"}, {"word": "hide", "wordClass": "actions"},
      {"word": "find", "wordClass": "actions"}, {"word": "backyard", "wordClass": "places"}
     ]}
    """

    /// "The playground: slide, swings, and the sandbox." — a leaf page.
    static let playground = """
    {"refused": false, "name": "Playground", "description": "Words for the playground.",
     "words": [
      {"word": "playground", "wordClass": "places"}, {"word": "slide", "wordClass": "play"},
      {"word": "swing", "wordClass": "play"}, {"word": "sandbox", "wordClass": "play"},
      {"word": "friend", "wordClass": "people"}, {"word": "push", "wordClass": "actions"},
      {"word": "climb", "wordClass": "actions"}, {"word": "wait", "wordClass": "actions"},
      {"word": "shovel", "wordClass": "object"}, {"word": "bucket", "wordClass": "object"},
      {"word": "dig", "wordClass": "actions"}, {"word": "fast", "wordClass": "describe"},
      {"word": "high", "wordClass": "describe"}, {"word": "scared", "wordClass": "feeling"}
     ]}
    """

    private struct Board {
        let tiles: [TileModel]
        let lookup: [String: TileModel]
        let system: BlasterScene
        var home: PageSpec? { system.page(withKey: system.homePageKey) }
    }

    private func board() -> Board {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let system = BootstrapLoader.loadDefaultVocabulary(context: context).scene
        let tiles = (try? context.fetch(FetchDescriptor<TileModel>())) ?? []
        return Board(tiles: tiles,
                     lookup: Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }),
                     system: system)
    }

    /// The home page as built: cell → entry, Home at 0 not included.
    private func cells(_ page: PageSpec) -> [Int: TileEntry] {
        Dictionary(uniqueKeysWithValues: page.tiles.enumerated().map { ($0.offset + 1, $0.element) })
    }

    private func placedHome(_ json: String, links: [GeneratedTile] = [], _ b: Board) throws -> PageSpec {
        var scene = try TopicWordsService.scene(from: try TopicWordsService.parse(content: json),
                                                systemHome: b.home, allTiles: b.tiles)
        scene.pages[0].tiles += links
        return try #require(scene.placedPages(systemHome: b.home, lookup: b.lookup).first)
    }

    private static let cell = PageTemplate.cell(row:col:)

    // MARK: - The home template

    @Test func theCoreWordsKeepTheirBlasterAI60Cells() throws {
        let b = board()
        let grid = cells(try placedHome(Self.bluey, b))
        let expected: [(Int, Int, String)] = [
            (1, 0, "i"), (1, 4, "go"), (1, 9, "more"), (2, 4, "want"), (3, 0, "you"),
            (3, 3, "help"), (4, 0, "yes"), (4, 1, "all_done"), (4, 2, "no"),
            (1, 11, "don't"), (2, 11, "stop"), (3, 11, "not"),
        ]
        for (row, col, key) in expected {
            #expect(grid[Self.cell(row, col)]?.key == key, "r\(row + 1) c\(col + 1) should be \(key)")
        }
        // "go" speaks and opens BlasterAI 60's Places.
        let go = try #require(grid[Self.cell(1, 4)])
        #expect(go.isAudible && go.link == TileToken.systemLink(to: "places"))
        #expect(grid[Self.cell(2, 4)]?.link.isEmpty == true)
    }

    @Test func rowOneIsTheCoreBoardsFolders() throws {
        let b = board()
        let grid = cells(try placedHome(Self.bluey, b))
        let row = (1..<PageTemplate.cols).compactMap { grid[$0] }.filter { !$0.isSpacer }
        #expect(!row.isEmpty)
        #expect(row.allSatisfy { TileToken.systemPageKey($0.link) != nil && !$0.isAudible })
        // The keyboard is pinned to column 12, with a visible gap before it.
        #expect(grid[PageTemplate.cols - 1]?.link == TileToken.systemLink(to: "keyboard"))
        #expect(grid[PageTemplate.cols - 2]?.isSpacer == true)
        // Eat, drink and play speak as well as open a page: words, not row 1.
        #expect(!row.contains { $0.key == "eat" })
        #expect(row.allSatisfy { !$0.linkColorIsAuto })
    }

    @Test func theWordsStayInColumnsOneToTen() throws {
        let b = board()
        let page = try placedHome(Self.bluey, b)
        let grid = cells(page)
        for row in 1..<PageTemplate.rows {
            #expect(grid[Self.cell(row, 10)]?.isSpacer ?? true, "column 11 holds only links")
        }
        let frame = Set(PageTemplate.homeFrame + PageTemplate.cluster)
        let words = page.tiles.filter { !$0.isSpacer && $0.link.isEmpty && !frame.contains($0.key) }
        #expect(words.count == TopicWordsService.budget)
    }

    @Test func thePageHasEnoughVerbsAndDescribingWords() throws {
        let b = board()
        let words = try TopicWordsService.scene(
            from: try TopicWordsService.parse(content: Self.bluey),
            systemHome: b.home, allTiles: b.tiles).pages[0].tiles
        let pos = words.map { TopicWordMatcher.partOfSpeech(of: $0, lookup: b.lookup) }
        #expect(pos.count { $0 == .verb } >= 5)
        #expect(pos.count { $0 == .adjective } >= 3)
        // Ranked last, and still on the page: the floor pulled it up.
        #expect(words.contains { $0.key == "frustrated" })
    }

    @Test func linksFillTheSlotsAndStopIsNeverDisplaced() throws {
        let b = board()
        let links = (1...7).map { GeneratedTile(key: "page_p\($0)", isAudible: false, link: "p\($0)") }
        let home = try placedHome(Self.bluey, links: links, b)
        let grid = cells(home)
        let slots = [Self.cell(1, 10), Self.cell(2, 10), Self.cell(3, 10), Self.cell(4, 10), Self.cell(4, 11)]
        for (n, slot) in slots.enumerated() {
            #expect(grid[slot]?.link == "p\(n + 1)", "link \(n + 1) goes to cell \(slot)")
        }
        // Past the slots, links take empty cells; the cluster keeps its words.
        let rest = home.tiles.filter { ["p6", "p7"].contains($0.link) }
        #expect(rest.count == 2)
        #expect(home.tiles.count < PageTemplate.cols * PageTemplate.rows)
        #expect(grid[Self.cell(1, 11)]?.key == "don't")
        #expect(grid[Self.cell(2, 11)]?.key == "stop")
        #expect(grid[Self.cell(3, 11)]?.key == "not")
    }

    @Test func aFewLinksLeaveTheClusterAlone() throws {
        let b = board()
        let links = [GeneratedTile(key: "page_p1", isAudible: false, link: "p1")]
        let grid = cells(try placedHome(Self.bluey, links: links, b))
        #expect(grid[Self.cell(1, 10)]?.link == "p1")
        #expect(grid[Self.cell(1, 11)]?.key == "don't")
        #expect(grid[Self.cell(3, 11)]?.key == "not")
    }

    // MARK: - The leaf template

    @Test func aLeafPageHasTheSystemRowAndNoFrame() throws {
        let b = board()
        let response = try TopicWordsService.parse(content: Self.playground)
        let frame = PageFrame(systemHome: b.home, kind: .leaf)
        let selection = TopicWordMatcher.select(response.words, excluding: frame.keys, allTiles: b.tiles)
        let tiles = PagePlacer.place(words: selection.page, links: [], kind: .leaf,
                                     frame: frame, lookup: b.lookup)
        let grid = cells(PageSpec(key: "playground", tiles: tiles))
        #expect(grid[1].map { TileToken.systemPageKey($0.link) != nil } == true)
        #expect(!tiles.contains { $0.key == "i" })
        // Bands start columns: the first word is at the top of column 1.
        #expect(grid[Self.cell(1, 0)]?.isSpacer == false)
        for row in 1..<PageTemplate.rows {
            for col in 10..<PageTemplate.cols {
                #expect(grid[Self.cell(row, col)]?.isSpacer ?? true)
            }
        }
    }

    @Test func aPageOfThingsGetsVerbsFromTheSystem() {
        let tiles = ["look", "see", "like", "play", "feel"].map {
            TileModel(key: $0, value: $0, wordClass: "actions")
        } + [TileModel(key: "read", value: "read", wordClass: "actions")]
            + (1...30).map { TileModel(key: "thing\($0)", value: "thing", wordClass: "object") }
        let lookup = Dictionary(uniqueKeysWithValues: tiles.map { ($0.key, $0) })
        let ranked = ["read"] + (1...30).map { "thing\($0)" }
        let page = TopicWordMatcher.select(ranked.map { GeneratedTile(key: $0, isAudible: true, link: "") },
                                           excluding: ["see"], lookup: lookup).page
        let verbs = page.filter { TopicWordMatcher.partOfSpeech(of: $0, lookup: lookup) == .verb }.map(\.key)
        // The model's verb first, then the system's in order; "see" is already on the page.
        #expect(verbs == ["read", "look", "like", "play", "feel"])
        #expect(page.count == TopicWordsService.budget)
    }

    // MARK: - Adding a page

    @Test func aNewPageLinkTakesTheNextFreeSlot() throws {
        let b = board()
        var home = try placedHome(Self.bluey, b).tiles
        let link = { (n: Int) in TileEntry(key: "page_p\(n)", link: "p\(n)", isAudible: false) }
        home = PagePlacer.insertLink(link(1), into: home, kind: .home)
        #expect(cells(PageSpec(key: "home", tiles: home))[Self.cell(1, 10)]?.link == "p1")
        // Five slots full, the next links take empty cells, nearest the link
        // columns, and the cluster keeps its words.
        for n in 2...6 { home = PagePlacer.insertLink(link(n), into: home, kind: .home) }
        var grid = cells(PageSpec(key: "home", tiles: home))
        let empty = PageTemplate.spareLinkCells.first { grid[$0] == nil || grid[$0]?.isSpacer == true }
        let target = try #require(empty)
        home = PagePlacer.insertLink(link(7), into: home, kind: .home)
        grid = cells(PageSpec(key: "home", tiles: home))
        #expect(grid[target]?.link == "p7")
        #expect(grid[Self.cell(1, 11)]?.key == "don't")
        #expect(grid[Self.cell(3, 11)]?.key == "not")
        // Out of empty cells: not's cell goes, then don't's; stop stays.
        var n = 100
        while PageTemplate.spareLinkCells.contains(where: { $0 > home.count || home[$0 - 1].isSpacer }) {
            n += 1
            home = PagePlacer.insertLink(link(n), into: home, kind: .home)
        }
        home = PagePlacer.insertLink(link(8), into: home, kind: .home)
        home = PagePlacer.insertLink(link(9), into: home, kind: .home)
        grid = cells(PageSpec(key: "home", tiles: home))
        #expect(grid[Self.cell(3, 11)]?.link == "p8")
        #expect(grid[Self.cell(1, 11)]?.link == "p9")
        #expect(grid[Self.cell(2, 11)]?.key == "stop")
        // A full page: the link still lands, at the end.
        home = PagePlacer.insertLink(link(10), into: home, kind: .home)
        #expect(home.last?.link == "p10")
    }

    @Test func onlyAPageOnTheSchemeIsTemplated() throws {
        let b = board()
        let home = try placedHome(Self.bluey, b)
        #expect(PageTemplate.kind(of: home, homePageKey: "home") == .home)
        #expect(PageTemplate.kind(of: try #require(b.home), homePageKey: b.system.homePageKey) == nil)
        #expect(PageTemplate.isTemplated([home], homePageKey: "home"))
    }

    @Test func aTemplatedScenesOtherPagesAreLeafPages() throws {
        let b = board()
        var scene = try TopicWordsService.scene(from: try TopicWordsService.parse(content: Self.bluey),
                                                systemHome: b.home, allTiles: b.tiles)
        let words = b.tiles.filter { $0.wordClass == "food" && !$0.isStructuralChrome }
        let few = words.prefix(12).map { GeneratedTile(key: $0.key, isAudible: true, link: "") }
        let many = words.prefix(PageTemplate.leafCapacity + 1)
            .map { GeneratedTile(key: $0.key, isAudible: true, link: "") }
        try #require(many.count > PageTemplate.leafCapacity)
        scene.pages += [GeneratedPage(key: "few", tiles: few), GeneratedPage(key: "many", tiles: many)]
        let placed = scene.placedPages(systemHome: b.home, lookup: b.lookup)
        #expect(PageTemplate.kind(of: placed[1], homePageKey: "home") == .leaf)
        #expect(PageTemplate.kind(of: placed[2], homePageKey: "home") == nil)
        #expect(placed[2].tiles.count == many.count)
        // A link added to the leaf page goes to column 12, top.
        let leaf = PagePlacer.insertLink(TileEntry(key: "page_x", link: "x", isAudible: false),
                                         into: placed[1].tiles, kind: .leaf)
        #expect(cells(PageSpec(key: "few", tiles: leaf))[Self.cell(1, 11)]?.link == "x")
    }

    @Test func anAddedPageLeavesOutTheSystemRow() throws {
        let b = board()
        let response = try TopicWordsService.parse(content: """
            {"refused": false, "name": "Playground", "description": "",
             "words": [{"word": "slide"}, {"word": "people"}, {"word": "swing"}]}
            """)
        let page = try TopicWordsService.page(from: response, key: "playground",
                                              systemHome: b.home, allTiles: b.tiles).primaryPage
        #expect(page.key == "playground")
        #expect(!page.tiles.contains { $0.key == "people" })
        #expect(page.tiles.contains { $0.key == "slide" })
    }

    @Test func theSceneContextIsTheHomePagesWords() throws {
        let b = board()
        let context = TestStore.container.mainContext
        let generated = try TopicWordsService.scene(
            from: try TopicWordsService.parse(content: Self.bluey),
            systemHome: b.home, allTiles: b.tiles)
        let built = try SceneBuilder.build(from: generated, tileLookup: b.lookup, context: context)
        let words = TopicWordsService.SceneContext(built).words
        #expect(words.contains("bluey"))
        #expect(words.contains("want"))
        #expect(!words.contains { $0.hasPrefix(TileToken.spacerPrefix) })
        #expect(!words.contains("people"))
    }

    // MARK: - Matching

    @Test func wordsMatchTheVocabulary() {
        let tiles = [TileModel(key: "short", value: "short", wordClass: "describe"),
                     TileModel(key: "tooth", value: "tooth", wordClass: "body"),
                     TileModel(key: "hot_", value: "hot", wordClass: "describe"),
                     TileModel(key: "telly", value: "TV", wordClass: "object"),
                     TileModel(key: "cup", value: "cup", wordClass: "object")]
        let words = ["shorts", "teeth", "hot", "TV", "cups", "cup"].map {
            TopicWordsService.Response.Word(word: $0, wordClass: "object")
        }
        let page = TopicWordMatcher.select(words, excluding: [], allTiles: tiles).page
        // shorts is not more than one "short"; the second cup is a duplicate.
        #expect(page.map(\.key) == ["shorts", "tooth", "hot_", "telly", "cup"])
        #expect(page[0].isProposedNew)
        #expect(!page[1].isProposedNew)
    }

    @Test func aRefusedTopicSaysWhy() async throws {
        let refused = try TopicWordsService.parse(content: """
            {"refused": true, "name": "Trip", "description": "Not for a young child.", "words": []}
            """)
        #expect(refused.refused)
        #expect(refused.words.isEmpty)
    }

    // MARK: - Building

    @Test func theBuiltSceneKeepsEveryCell() throws {
        let b = board()
        let context = TestStore.container.mainContext
        let generated = try TopicWordsService.scene(
            from: try TopicWordsService.parse(content: Self.bluey),
            systemHome: b.home, allTiles: b.tiles)
        let built = try SceneBuilder.build(from: generated, tileLookup: b.lookup, context: context)
        #expect(built.designedFor == PageTemplate.designedFor)
        let home = try #require(built.page(withKey: built.homePageKey))
        let preview = try #require(generated.placedPages(systemHome: b.home, lookup: b.lookup).first)
        #expect(home.tiles.count == preview.tiles.count)
        #expect(cells(home)[Self.cell(2, 4)]?.key == "want")
        // New words were materialized, so none was dropped.
        #expect(home.tiles.contains { $0.key == "bluey" })
    }

    @Test func aBlasterAI60PageIsLinkedNotCopied() throws {
        let b = board()
        let folder = try #require(SceneStructure.systemFolder(for: "animals", in: b.system))
        #expect(folder.link == TileToken.systemLink(to: "animals"))
        #expect(folder.linkColor == "noun")
        #expect(SceneStructure.systemFolder(for: b.system.homePageKey, in: b.system) == nil)
    }
}
}
