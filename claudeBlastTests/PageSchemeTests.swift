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

    /// A page as built: cell → entry. Row 1 is the inherited system row, so
    /// the page's first tile is r2c1.
    private func cells(_ page: PageSpec) -> [Int: TileEntry] {
        Dictionary(uniqueKeysWithValues: page.tiles.enumerated().map { ($0.offset + PageTemplate.cols, $0.element) })
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
            (1, 0, "i"), (1, 4, "go"), (2, 8, "more"), (2, 4, "want"), (3, 0, "you"),
            (3, 3, "help"), (5, 0, "yes"), (5, 1, "all_done"), (5, 2, "no"),
            (1, 9, "don't"), (2, 9, "stop"), (3, 9, "not"),
        ]
        for (row, col, key) in expected {
            #expect(grid[Self.cell(row, col)]?.key == key, "r\(row + 1) c\(col + 1) should be \(key)")
        }
        // "go" speaks and opens BlasterAI 60's Places.
        let go = try #require(grid[Self.cell(1, 4)])
        #expect(go.isAudible && go.link == TileToken.systemLink(to: "places"))
        #expect(grid[Self.cell(2, 4)]?.link.isEmpty == true)
    }

    /// A doorway belongs to the word, so a scene's frame carries BlasterAI 60's:
    /// "I" opens the I page and "go" opens Places on every new board. The frame
    /// used to skip any word with a link, which would have dropped both.
    @Test func theFrameCarriesBlasterAI60sDoorways() throws {
        let b = board()
        let grid = cells(try placedHome(Self.bluey, b))
        let i = try #require(grid[Self.cell(1, 0)])
        #expect(i.key == "i" && i.isAudible && i.link == TileToken.systemLink(to: "i_page"))
        #expect(i.linkColor == "pronoun")
        let go = try #require(grid[Self.cell(1, 4)])
        #expect(go.linkColor == "verb")
    }

    // MARK: - BlasterAI 60's hierarchy (tools/board_spec/blasterai60.json)

    /// Row 1 is drawn, not stored: no BlasterAI 60 page carries the system
    /// row, and every page fits the screen under it.
    @Test func noCorePageStoresTheSystemRow() throws {
        let b = board()
        #expect(b.system.designedFor == PageTemplate.designedFor)
        #expect(BoardChrome.inherits(b.system))
        let row = Set(BoardChrome.pageKeys)
        var checked = 0
        for page in b.system.pages {
            let first = page.tiles.first
            #expect(!(first.map { row.contains($0.link) && !$0.isAudible } ?? false),
                    "\(page.key) still opens with the system row")
            #expect(page.tiles.count <= PageTemplate.cols * (PageTemplate.rows - 1),
                    "\(page.key) overflows one screen")
            checked += 1
        }
        #expect(checked > 30, "only \(checked) pages checked")
    }

    /// A doorway is a word that also opens a page; on the page it opens it is
    /// just the word.
    @Test func noDoorwayOpensItsOwnPage() {
        let b = board()
        var doorways = 0
        for page in b.system.pages {
            for tile in page.tiles where tile.isAudible && !tile.link.isEmpty {
                #expect(tile.link != page.key, "\(page.key)/\(tile.key) opens its own page")
                doorways += 1
            }
        }
        #expect(doorways > 20, "only \(doorways) doorways")
    }

    /// Folders extend the path one level down; they are not a topic toolbar.
    /// Describe › How much once repeated Size, Where, Opinions… in its own
    /// columns 11–12, and following them made deep, confusing chains (Mark,
    /// session 14). A folder page links only to pages below it — and keeps its
    /// own tile, in the cell Describe shows it in, for the board to mark "you
    /// are here" (`WayMark`).
    @Test func aFolderPageDoesNotRepeatItsSiblings() {
        let b = board()
        let pages = Dictionary(b.system.pages.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let describe = pages["describe"]?.tiles ?? []
        let folders = describe.filter { $0.link.hasPrefix("describe_") }.map(\.link)
        #expect(folders.count >= 6, "Describe's folders: \(folders)")
        for folder in folders {
            let tiles = pages[folder]?.tiles ?? []
            let siblings = tiles.filter { folders.contains($0.link) && $0.link != folder }.map(\.key)
            #expect(siblings.isEmpty, "\(folder) links to its siblings \(siblings)")
            #expect(tiles.firstIndex { $0.link == folder } == describe.firstIndex { $0.link == folder },
                    "\(folder) does not keep its own tile in Describe's cell")
        }
    }

    /// The marks follow the hierarchy: on How much, Describe is on the way and
    /// How much is here.
    @Test func theWayHereEndsAtThePageShowing() {
        let b = board()
        let row = BoardChrome.rowPages(of: b.system)
        let keys = WordPlaces.trailKeys(to: "describe_how_much", pages: b.system.pages,
                                        homeKey: b.system.homePageKey, row: row)
        #expect(keys == ["describe", "describe_how_much"])
        #expect(WordPlaces.trailKeys(to: b.system.homePageKey, pages: b.system.pages,
                                     homeKey: b.system.homePageKey, row: row).isEmpty)
    }

    /// A templated page stores none of row 1: the board draws the core
    /// board's folders over it, the same ten on every page of every scene.
    @Test func theSystemRowIsInheritedNotStored() throws {
        let b = board()
        let page = try placedHome(Self.bluey, b)
        #expect(!page.tiles.contains { TileToken.systemPageKey($0.link) != nil && !$0.isAudible })
        let row = BoardChrome.row(inSystemScene: false)
        #expect(row.count == PageTemplate.cols)
        #expect(row.allSatisfy { TileToken.systemPageKey($0.link) != nil && !$0.isAudible })
        // In the spec's order (`tools/board_spec/blasterai60.json`, `systemRow`).
        #expect(row.map(\.key) == PageTemplate.scheme.systemRow.map(\.key))
        #expect(row.contains { $0.link == TileToken.systemLink(to: "small_words") })
        // The keyboard is on the rail now, not in the row.
        #expect(!row.contains { $0.key == "keyboard" })
        // Eat, drink and play speak as well as open a page: words, not row 1.
        #expect(!row.contains { $0.key == "eat" })
        #expect(row.allSatisfy { !$0.linkColorIsAuto && $0.linkColor != nil })
        // On BlasterAI 60 itself the folders open its own pages.
        #expect(BoardChrome.row(inSystemScene: true).first?.link == "people")
    }

    /// Words fill columns 1–8; 9 and 10 are the links and the cluster. The
    /// frame's `more` is the one word there, where BlasterAI 60 has it.
    @Test func theWordsStayInColumnsOneToEight() throws {
        let b = board()
        let page = try placedHome(Self.bluey, b)
        let grid = cells(page)
        let frame = Set(PageTemplate.homeFrame + PageTemplate.scheme.template(.home).cluster)
        for row in 1..<PageTemplate.rows {
            for col in 8..<PageTemplate.cols {
                let entry = grid[Self.cell(row, col)]
                #expect(entry.map { $0.isSpacer || !$0.link.isEmpty || frame.contains($0.key) } ?? true,
                        "r\(row + 1) c\(col + 1) holds a word")
            }
        }
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
        let slots = [Self.cell(1, 8), Self.cell(3, 8), Self.cell(4, 8), Self.cell(5, 8), Self.cell(4, 9)]
        for (n, slot) in slots.enumerated() {
            #expect(grid[slot]?.link == "p\(n + 1)", "link \(n + 1) goes to cell \(slot)")
        }
        // Past the slots, links take empty cells; the cluster keeps its words.
        let rest = home.tiles.filter { ["p6", "p7"].contains($0.link) }
        #expect(rest.count == 2)
        #expect(home.tiles.count <= PageTemplate.cols * (PageTemplate.rows - 1))
        #expect(grid[Self.cell(1, 9)]?.key == "don't")
        #expect(grid[Self.cell(2, 9)]?.key == "stop")
        #expect(grid[Self.cell(3, 9)]?.key == "not")
    }

    @Test func aFewLinksLeaveTheClusterAlone() throws {
        let b = board()
        let links = [GeneratedTile(key: "page_p1", isAudible: false, link: "p1")]
        let grid = cells(try placedHome(Self.bluey, links: links, b))
        #expect(grid[Self.cell(1, 8)]?.link == "p1")
        #expect(grid[Self.cell(1, 9)]?.key == "don't")
        #expect(grid[Self.cell(3, 9)]?.key == "not")
    }

    // MARK: - The scheme file

    /// Experiments edit `page_templates.json`; these stay put whatever it says.
    /// A child finds want, go and stop by where they are, on every board.
    @Test func theAnchorsArePinned() throws {
        let home = PageTemplate.scheme.template(.home)
        for anchor in ["i", "you", "want", "go", "more", "help", "yes", "no", "all_done", "stop"] {
            #expect(home.frame.contains(anchor), "\(anchor) is in the home frame")
        }
        #expect(home.cluster.contains("stop"))
        #expect(!home.displaceable.contains("stop"), "stop is never displaced")
        #expect(PageTemplate.designedFor == "ipad-10x6")
        #expect(PageTemplate.cols == 10 && PageTemplate.rows == 6)
    }

    @Test func aBadSchemeIsRejected() throws {
        let url = try #require(Bundle.main.url(forResource: "page_templates", withExtension: "json"))
        let good = try String(contentsOf: url, encoding: .utf8)
        #expect(throws: Never.self) { try PageScheme.load(Data(good.utf8)) }
        for (bad, replacement) in [("\"r6c9\"]", "\"r7c9\"]"),                 // off the grid
                                   ("\"r2c9\"", "\"r1c9\""),                  // row 1 is inherited
                                   ("\"noun\"]", "\"nouns\"]"),                // unknown band
                                   ("\"wordColumns\": [1, 8]", "\"wordColumns\": [1, 13]"),
                                   ("\"displaceable\": [\"not\"", "\"displaceable\": [\"maybe\""),
                                   ("\"home\": {", "\"house\": {")] {          // no home template
            let text = good.replacingOccurrences(of: bad, with: replacement)
            try #require(text != good, "\(bad) is in the file")
            #expect(throws: PageScheme.Invalid.self, "\(replacement)") { try PageScheme.load(Data(text.utf8)) }
        }
    }

    // MARK: - The leaf template

    @Test func aLeafPageHasNoFrame() throws {
        let b = board()
        let response = try TopicWordsService.parse(content: Self.playground)
        let frame = PageFrame(systemHome: b.home, kind: .leaf)
        let selection = TopicWordMatcher.select(response.words, excluding: frame.keys, allTiles: b.tiles)
        let tiles = PagePlacer.place(words: selection.page, links: [], kind: .leaf,
                                     frame: frame, lookup: b.lookup)
        let grid = cells(PageSpec(key: "playground", tiles: tiles))
        #expect(!tiles.contains { TileToken.systemPageKey($0.link) != nil })
        #expect(!tiles.contains { $0.key == "i" })
        // Bands start columns: the first word is at the top of column 1.
        #expect(grid[Self.cell(1, 0)]?.isSpacer == false)
        for row in 1..<PageTemplate.rows {
            for col in 8..<PageTemplate.cols {
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
        #expect(cells(PageSpec(key: "home", tiles: home))[Self.cell(1, 8)]?.link == "p1")
        // Five slots full, the next links take empty cells, nearest the link
        // columns, and the cluster keeps its words.
        for n in 2...6 { home = PagePlacer.insertLink(link(n), into: home, kind: .home) }
        var grid = cells(PageSpec(key: "home", tiles: home))
        let empty = PageTemplate.spareLinkCells.first { grid[$0] == nil || grid[$0]?.isSpacer == true }
        let target = try #require(empty)
        home = PagePlacer.insertLink(link(7), into: home, kind: .home)
        grid = cells(PageSpec(key: "home", tiles: home))
        #expect(grid[target]?.link == "p7")
        #expect(grid[Self.cell(1, 9)]?.key == "don't")
        #expect(grid[Self.cell(3, 9)]?.key == "not")
        // Out of empty cells: not's cell goes, then don't's; stop stays.
        var n = 100
        let index = PageTemplate.contentIndex(ofCell:)
        while PageTemplate.spareLinkCells.contains(where: { index($0) >= home.count || home[index($0)].isSpacer }) {
            n += 1
            home = PagePlacer.insertLink(link(n), into: home, kind: .home)
        }
        home = PagePlacer.insertLink(link(8), into: home, kind: .home)
        home = PagePlacer.insertLink(link(9), into: home, kind: .home)
        grid = cells(PageSpec(key: "home", tiles: home))
        #expect(grid[Self.cell(3, 9)]?.link == "p8")
        #expect(grid[Self.cell(1, 9)]?.link == "p9")
        #expect(grid[Self.cell(2, 9)]?.key == "stop")
        // A full page: the link still lands, at the end.
        home = PagePlacer.insertLink(link(10), into: home, kind: .home)
        #expect(home.last?.link == "p10")
    }

    /// A scene is on the scheme when it declares a grid this build knows:
    /// those inherit the system row. A 12 × 5 scene from before, or an
    /// undeclared flat pack, draws its pages as they are.
    @Test func onlyASceneOnACurrentGridInheritsTheRow() throws {
        let b = board()
        let context = TestStore.container.mainContext
        let generated = try TopicWordsService.scene(
            from: try TopicWordsService.parse(content: Self.bluey),
            systemHome: b.home, allTiles: b.tiles)
        let built = try SceneBuilder.build(from: generated, tileLookup: b.lookup, context: context)
        #expect(BoardChrome.inherits(built))
        #expect(!BoardChrome.inherits(designedFor: "ipad-12x5"))
        #expect(!BoardChrome.inherits(designedFor: ""))
        #expect(BoardChrome.inherits(designedFor: "phone-4x6"))
    }

    /// A bundled starter takes the path a fresh generation does: its words
    /// around the frame on the home template, and the scene declares the grid,
    /// so it inherits the system row.
    @Test func aStarterSceneLandsOnTheTemplate() throws {
        let b = board()
        let context = TestStore.container.mainContext
        let starters = StarterSceneCatalog.all
        try #require(!starters.isEmpty)
        for starter in starters {
            let loaded = try #require(starter.loadPreview(), "\(starter.id)")
            let placed = ScenePreviewView.reselected(loaded.scene, template: .home,
                                                     systemHome: b.home, lookup: b.lookup)
            let scene = try #require(starter.importBundle(context: context), "\(starter.id)")
            let tiles = try context.fetch(FetchDescriptor<TileModel>())
            SceneBuilder.lay(placed, onto: scene,
                             lookup: Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }),
                             context: context)
            #expect(BoardChrome.inherits(scene), "\(starter.id)")
            let home = try #require(scene.page(withKey: scene.homePageKey))
            let topic = Set(loaded.scene.pages.flatMap(\.tiles).map(\.key))
            #expect(home.tiles.contains { topic.contains($0.key) }, "\(starter.id) lost its words")
            #expect(home.tiles.count <= PageTemplate.cols * (PageTemplate.rows - 1), "\(starter.id)")
        }
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
        // Too many for the leaf template: a flat list the grid pages through.
        #expect(placed[2].tiles.count == many.count)
        #expect(!placed[2].tiles.contains { $0.isSpacer })
        // A link added to the leaf page goes to column 10, top.
        let leaf = PagePlacer.insertLink(TileEntry(key: "page_x", link: "x", isAudible: false),
                                         into: placed[1].tiles, kind: .leaf)
        #expect(cells(PageSpec(key: "few", tiles: leaf))[Self.cell(1, 9)]?.link == "x")
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

    @Test func theChromeKeepsBlasterAI60sLevels() throws {
        let b = board()
        try #require(b.system.revealLevelCount > 0, "BlasterAI 60 has levels")
        let systemLevels = Dictionary((b.home?.tiles ?? []).map { ($0.key, $0.revealLevel) },
                                      uniquingKeysWith: { a, _ in a })
        try #require(systemLevels.values.contains { $0 > 1 }, "some core words reveal later")
        let context = TestStore.container.mainContext
        let generated = try TopicWordsService.scene(
            from: try TopicWordsService.parse(content: Self.bluey),
            systemHome: b.home, allTiles: b.tiles)
        let built = try SceneBuilder.build(from: generated, tileLookup: b.lookup, context: context)
        #expect(built.revealLevelCount == b.system.revealLevelCount)
        #expect(built.revealLevel == b.system.revealLevel)
        let home = try #require(built.page(withKey: built.homePageKey))
        let chrome = home.tiles.filter {
            TileToken.systemPageKey($0.link) != nil || PageTemplate.homeFrame.contains($0.key)
        }
        try #require(!chrome.isEmpty)
        for entry in chrome {
            #expect(entry.revealLevel == systemLevels[entry.key], "\(entry.key) keeps its level")
        }
        // The scene's own words show at every level.
        #expect(home.tiles.first { $0.key == "bluey" }?.revealLevel == 0)
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
