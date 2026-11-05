// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardCellTests.swift
//  claudeBlastTests
//
//  The spreadsheet editor's cell grammar (`BoardCell`) and cell addressing
//  (`PageCells`).
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct BoardCellTests {

    // MARK: - Parse

    @Test func parsesEveryForm() {
        #expect(BoardCell.parse("") == .spacer)
        #expect(BoardCell.parse("   ") == .spacer)
        #expect(BoardCell.parse("cat") == .cell(word: .existing("cat"), link: nil))
        #expect(BoardCell.parse("go > places")
                == .cell(word: .existing("go"), link: .init(page: "places", isSystem: false)))
        #expect(BoardCell.parse("> animals")
                == .cell(word: nil, link: .init(page: "animals", isSystem: false)))
        #expect(BoardCell.parse("go > sys:Places")
                == .cell(word: .existing("go"), link: .init(page: "Places", isSystem: true)))
        #expect(BoardCell.parse("starfish, animal, Sea Star > tide pools")
                == .cell(word: .new(.init(key: "starfish", wordClass: "animal", displayName: "Sea Star")),
                         link: .init(page: "tide pools", isSystem: false)))
    }

    @Test func rejectsHalfWrittenCells() {
        if case .invalid = BoardCell.parse("go >") {} else { Issue.record("empty page accepted") }
        if case .invalid = BoardCell.parse("starfish,") {} else { Issue.record("classless word accepted") }
    }

    // MARK: - Resolve

    private func tile(_ key: String, _ cls: String = "object", display: String? = nil) -> TileModel {
        TileModel(key: key, value: display ?? key.replacingOccurrences(of: "_", with: " "), wordClass: cls)
    }

    private var scenePages: [PageSpec] {
        [PageSpec(key: "home", tiles: []), PageSpec(key: "places", tiles: [])]
    }
    private var systemPages: [PageSpec] {
        [PageSpec(key: "home", tiles: []),
         PageSpec(key: "actions", tiles: []),
         PageSpec(key: "places", tiles: [TileEntry(key: "folder_house", link: "places_house", isAudible: false)]),
         PageSpec(key: "places_house", tiles: []),
         PageSpec(key: "people", tiles: []),
         PageSpec(key: "questions", tiles: [])]
    }

    private func plan(_ text: String, _ lookup: [String: TileModel]) -> BoardCell.Plan? {
        if case .plan(let plan) = BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                                   scenePages: scenePages, systemPages: systemPages) {
            return plan
        }
        return nil
    }

    /// A bare name is the scene's page, made empty if need be, even where
    /// BlasterAI 60 has one; only `sys:` reaches BlasterAI 60.
    @Test func bareLinksAreTheScenesAndSysIsTheSystemBoards() {
        let lookup = ["go": tile("go", "actions")]
        #expect(plan("go > places", lookup)?.entry.link == "places")
        #expect(plan("go > sys:places", lookup)?.entry.link == TileToken.systemLink(to: "places"))
        #expect(plan("go > sys:Actions", lookup)?.entry.link == TileToken.systemLink(to: "actions"))
        let forward = plan("go > actions", lookup)
        #expect(forward?.entry.link == "actions")
        #expect(forward?.newPage == "actions")
        let fresh = plan("go > tide pools", lookup)
        #expect(fresh?.entry.link == "tide_pools")
        #expect(fresh?.newPage == "tide_pools")
        #expect(plan("go > sys:nowhere", lookup) == nil)
    }

    @Test func aDoorwaySpeaksAndAFolderIsSilent() {
        let lookup = ["go": tile("go", "actions")]
        #expect(plan("go > places", lookup)?.entry.isAudible == true)
        let folder = plan("> tide pools", lookup)
        #expect(folder?.entry.isAudible == false)
        #expect(folder?.entry.key == "page_tide_pools")
        #expect(folder?.folderFor == "tide_pools")
    }

    @Test func aFolderReusesTheFolderAlreadyUsedForThatPage() {
        let folder = plan("> sys:places_house", [:])
        #expect(folder?.entry.key == "folder_house")
        #expect(folder?.entry.link == TileToken.systemLink(to: "places_house"))
        #expect(folder?.folderFor == nil)
    }

    /// People and Questions are folders only on the inherited system row, so
    /// `> people` found no folder on any page and minted an artless one.
    @Test func aFolderIntoASystemRowPageUsesTheRowsFolder() {
        let people = plan("> sys:people", [:])
        #expect(people?.entry.key == "people")
        #expect(people?.entry.link == TileToken.systemLink(to: "people"))
        #expect(people?.folderFor == nil)
        #expect(plan("> sys:questions", [:])?.entry.key == "question")
        // A scene's own People page is not the core board's.
        let own = BoardCell.folderKey(for: .scene("people"),
                                      scenePages: [PageSpec(key: "people", tiles: [])],
                                      systemPages: systemPages)
        #expect(own == PageLink.key(forPage: "people"))
    }

    @Test func wordsMatchByKeyThenByLabel() {
        let lookup = ["all_done": tile("all_done"), "hot_": tile("hot_", display: "hot"),
                      "right_": tile("right_", display: "right"), "right_side": tile("right_side", display: "right")]
        #expect(plan("all done", lookup)?.entry.key == "all_done")
        #expect(plan("Hot", lookup)?.entry.key == "hot_")
        if case .error = BoardCell.resolve(BoardCell.parse("right"), lookup: lookup,
                                           scenePages: [], systemPages: []) {} else {
            Issue.record("ambiguous label resolved")
        }
        if case .error = BoardCell.resolve(BoardCell.parse("zebra"), lookup: lookup,
                                           scenePages: [], systemPages: []) {} else {
            Issue.record("unknown word resolved")
        }
    }

    @Test func aNewWordIsPlannedUnlessItAlreadyExists() {
        let lookup = ["cat": tile("cat", "animal")]
        #expect(plan("cat, animal", lookup)?.newWord == nil)
        #expect(plan("starfish, animal", lookup)?.newWord?.key == "starfish")
    }

    // MARK: - Format

    @Test func formatWritesWhatParseReads() {
        #expect(BoardCell.format(.spacer()) == "")
        #expect(BoardCell.format(TileEntry(key: "cat")) == "cat")
        #expect(BoardCell.format(TileEntry(key: "go", link: "places")) == "go > places")
        #expect(BoardCell.format(TileEntry(key: "page_x", link: "x", isAudible: false)) == "> x")
        // A link into BlasterAI 60 is always written with sys:.
        #expect(BoardCell.format(TileEntry(key: "go", link: TileToken.systemLink(to: "actions"))) == "go > sys:actions")
    }

    /// Every placement on BlasterAI 60 survives being written as a cell and
    /// read back — the promise CSV export and the grid editor both rest on.
    @Test func blasterAI60RoundTripsThroughCellText() throws {
        let ctx = TestStore.freshContext()
        let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)
        let lookup = Dictionary(result.tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let pages = result.scene.pages
        #expect(pages.count > 10)
        var mismatches: [String] = []
        for page in pages {
            for entry in page.tiles where !entry.isSpacer {
                let text = BoardCell.format(entry)
                switch BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                         scenePages: pages, systemPages: []) {
                case .error(let message):
                    mismatches.append("\(page.key): \(text) → \(message)")
                case .plan(let plan):
                    let back = plan.entry
                    if back.key != entry.key || back.link != entry.link || back.isAudible != entry.isAudible {
                        mismatches.append("\(page.key): \(text) → \(back.key) > \(back.link)")
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(20))")
    }

    // MARK: - Commit

    @Test func commitMakesTheWordPageAndFolder() throws {
        let ctx = TestStore.freshContext()
        let scene = BlasterScene(name: "Tide Pools", homePageKey: "home", isDefault: false, isActive: false)
        scene.pages = [PageSpec(key: "home", tiles: [])]
        ctx.insert(scene)
        let cat = tile("cat", "animal")
        ctx.insert(cat)
        let lookup = ["cat": cat]

        guard case .plan(let wordPlan) = BoardCell.resolve(
            BoardCell.parse("cat, food > snacks"), lookup: lookup, scenePages: scene.pages, systemPages: []) else {
            Issue.record("no plan"); return
        }
        let entry = BoardCell.commit(wordPlan, replacing: nil, in: scene, lookup: lookup, context: ctx)
        #expect(entry.key == "cat_food")             // homograph of the animal
        #expect(entry.link == "snacks")
        #expect(scene.pages.map(\.key) == ["home", "snacks"])

        guard case .plan(let folderPlan) = BoardCell.resolve(
            BoardCell.parse("> snacks"), lookup: lookup, scenePages: scene.pages, systemPages: []) else {
            Issue.record("no plan"); return
        }
        let folder = BoardCell.commit(folderPlan, replacing: nil, in: scene, lookup: lookup, context: ctx)
        let keys = Set(try ctx.fetch(FetchDescriptor<TileModel>()).map(\.key))
        #expect(keys.isSuperset(of: ["cat_food", "page_snacks", folder.key]))
    }

    /// A typed doorway takes its word's colour, including one into BlasterAI 60
    /// that the scene's colour refresh never revisits. Stored nil, it drew blue.
    @Test func aTypedLinkIsColoredWhenMade() {
        let ctx = TestStore.freshContext()
        let scene = BlasterScene(name: "S", homePageKey: "home", isDefault: false, isActive: false)
        scene.pages = [PageSpec(key: "home", tiles: [])]
        let lookup = ["go": tile("go", "actions")]
        let system = [PageSpec(key: "places", tiles: [TileEntry(key: "park")])]
        guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse("go > sys:places"), lookup: lookup,
                                                      scenePages: scene.pages, systemPages: system) else {
            Issue.record("no plan"); return
        }
        let entry = BoardCell.commit(plan, replacing: nil, in: scene, systemPages: system,
                                     lookup: lookup, context: ctx)
        #expect(entry.link == TileToken.systemLink(to: "places"))
        #expect(entry.linkColor != nil)
        #expect(entry.linkColor != TileColorSlot.wayfinding.rawValue)
    }

    @Test func retypingAWordKeepsItsLevelAndConceal() {
        let ctx = TestStore.freshContext()
        let scene = BlasterScene(name: "S", homePageKey: "home", isDefault: false, isActive: false)
        scene.pages = [PageSpec(key: "home", tiles: [])]
        let lookup = ["go": tile("go", "actions")]
        var old = TileEntry(key: "go", link: "home", revealLevel: 3)
        old.isConcealed = true
        guard case .plan(let same) = BoardCell.resolve(BoardCell.parse("go > home"), lookup: lookup,
                                                      scenePages: scene.pages, systemPages: []),
              case .plan(let unlinked) = BoardCell.resolve(BoardCell.parse("go"), lookup: lookup,
                                                          scenePages: scene.pages, systemPages: []) else {
            Issue.record("no plan"); return
        }
        #expect(BoardCell.commit(same, replacing: old, in: scene, lookup: lookup, context: ctx) == old)
        let moved = BoardCell.commit(unlinked, replacing: old, in: scene, lookup: lookup, context: ctx)
        #expect(moved.link.isEmpty)
        #expect(moved.revealLevel == 3)
        #expect(moved.isConcealed)
    }

    // MARK: - Cells

    @Test func cellsAddressTheGridBelowTheSystemRow() {
        let cells = PageCells(grid: (10, 6), inheritsChrome: true)
        #expect(cells.perScreen == 50)
        #expect(cells.index(of: .init(screen: 1, row: 2, col: 3)) == 73)
        #expect(cells.cell(at: 73) == .init(screen: 1, row: 2, col: 3))
        #expect(PageCells(grid: (10, 6), inheritsChrome: false).perScreen == 60)
    }

    @Test func settingPadsWithGapsAndTrimsTrailingOnes() {
        let cells = PageCells(grid: (10, 6), inheritsChrome: true)
        let placed = cells.setting(TileEntry(key: "cat"), at: 12, in: [])
        #expect(placed.count == 13)
        #expect(placed.prefix(12).allSatisfy { $0.isSpacer })
        #expect(cells.entry(at: 12, in: placed)?.key == "cat")
        #expect(cells.entry(at: 3, in: placed) == nil)
        #expect(cells.setting(nil, at: 12, in: placed).isEmpty)
        #expect(cells.screenCount([]) == 1)
        #expect(cells.screenCount(cells.setting(TileEntry(key: "cat"), at: 50, in: [])) == 2)
    }

    @Test func movingWrapsRowsAndScreens() {
        let cells = PageCells(grid: (10, 6), inheritsChrome: true)
        let last = PageCells.Cell(screen: 0, row: 4, col: 9)
        #expect(cells.moving(last, colBy: 1, screens: 2) == .init(screen: 1, row: 0, col: 0))
        #expect(cells.moving(last, rowBy: 1, screens: 1) == last)
        #expect(cells.moving(.init(screen: 0, row: 0, col: 0), colBy: -1, screens: 1)
                == .init(screen: 0, row: 0, col: 0))
    }

    // MARK: - Moving

    private func keys(_ tiles: [TileEntry], _ cells: PageCells, through last: Int) -> [String] {
        (0...last).map { cells.entry(at: $0, in: tiles)?.key ?? "." }
    }

    @Test func aCellMovesIntoAGapAndNothingElseShifts() throws {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        let tiles = [TileEntry(key: "a"), TileEntry(key: "b"), TileEntry(key: "c")]
        let moved = try cells.moving([0], anchor: 0, to: 5, in: tiles).get()
        #expect(keys(moved, cells, through: 5) == [".", "b", "c", ".", ".", "a"])
    }

    @Test func aCellDroppedOnAWordSwapsWithIt() throws {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        let tiles = [TileEntry(key: "a"), TileEntry(key: "b"), TileEntry(key: "c")]
        let swapped = try cells.moving([0], anchor: 0, to: 2, in: tiles).get()
        #expect(keys(swapped, cells, through: 2) == ["c", "b", "a"])
    }

    @Test func aBlockKeepsItsShapeAndIsRefusedOverWords() throws {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        // a b . .
        // c d . x
        var tiles = cells.setting(TileEntry(key: "x"), at: 7,
                                  in: [TileEntry(key: "a"), TileEntry(key: "b"), .spacer(), .spacer(),
                                       TileEntry(key: "c"), TileEntry(key: "d")])
        let block: Set<Int> = [0, 1, 4, 5]
        // One column right overlaps itself: fine.
        let shifted = try cells.moving(block, anchor: 0, to: 1, in: tiles).get()
        #expect(keys(shifted, cells, through: 7) == [".", "a", "b", ".", ".", "c", "d", "x"])
        // Two right would cover x.
        #expect(cells.moving(block, anchor: 0, to: 2, in: tiles) == .failure(.occupied([7])))
        // Off the right edge.
        #expect(cells.moving(block, anchor: 0, to: 3, in: tiles) == .failure(.offGrid))
        // Down a row, past the screen's end onto the next.
        tiles = try cells.moving(block, anchor: 0, to: 8, in: tiles).get()
        #expect(cells.entry(at: 8, in: tiles)?.key == "a")
        #expect(cells.entry(at: 13, in: tiles)?.key == "d")
        #expect(cells.entry(at: 7, in: tiles)?.key == "x")
    }

    @Test func insertingShiftsTheRunIntoItsGapAndStops() {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        // a b . c   d
        let tiles = cells.setting(TileEntry(key: "d"), at: 4,
                                  in: [TileEntry(key: "a"), TileEntry(key: "b"), .spacer(), TileEntry(key: "c")])
        let x = cells.inserting([TileEntry(key: "x")], before: 0, in: tiles)
        #expect(keys(x, cells, through: 4) == ["x", "a", "b", "c", "d"])
        // d moves in front of b: its own cell empties, b shifts into the gap.
        let moved = cells.inserting([TileEntry(key: "d")], before: 1, removing: [4], in: tiles)
        #expect(keys(moved, cells, through: 4) == ["a", "d", "b", "c", "."])
        // Two entries use two gaps.
        let two = cells.inserting([TileEntry(key: "x"), TileEntry(key: "y")], before: 0, in: tiles)
        #expect(keys(two, cells, through: 6) == ["x", "y", "a", "b", "c", "d", "."])
    }

    @Test func placingStepsOverFilledCells() {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        let tiles = [TileEntry(key: "a"), .spacer(), TileEntry(key: "b")]
        let placed = cells.placing([TileEntry(key: "x"), TileEntry(key: "y")], intoEmptyFrom: 0, in: tiles)
        #expect(keys(placed, cells, through: 3) == ["a", "x", "b", "y"])
    }

    @Test func pastingWritesARectangleAndDropsWhatFallsOffTheEdge() {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        let rows: [[TileEntry?]] = [[TileEntry(key: "a"), nil, TileEntry(key: "b")],
                                    [TileEntry(key: "c")]]
        let pasted = cells.pasting(rows, at: 2, in: [TileEntry(key: "q"), TileEntry(key: "r"), TileEntry(key: "s"),
                                                      TileEntry(key: "t")])
        #expect(pasted.dropped == 1)
        #expect(keys(pasted.tiles, cells, through: 6) == ["q", "r", "a", ".", ".", ".", "c"])
    }

    @Test func tsvRoundTrips() {
        let rows = [["go > places", "", "cat"], ["> animals"]]
        #expect(BoardCell.rows(fromTSV: BoardCell.tsv(rows) + "\n") == rows)
        #expect(BoardCell.rows(fromTSV: "cat") == [["cat"]])
    }

    @Test func spanIsTheRectangleBetweenTwoCells() {
        let cells = PageCells(grid: (4, 3), inheritsChrome: false)
        #expect(cells.span(from: 5, to: 2) == [1, 2, 5, 6])
    }

    // MARK: - Word well

    /// A BlasterAI 60 link is offered as `sys:`, so it lands on the core
    /// board's page even in a scene with a page of the same name, and its
    /// folder keeps the core board's picture.
    @Test func theWellOffersSystemLinksAsSystemLinks() {
        let system = [PageSpec(key: "places", tiles: [
            TileEntry(key: "go", link: "places_house"),
            TileEntry(key: "folder_house", link: "places_house", isAudible: false),
            TileEntry(key: "park")]), PageSpec(key: "places_house", tiles: [])]
        let lookup = ["go": tile("go", "actions"), "park": tile("park", "places"),
                      "folder_house": tile("folder_house", "page_link")]
        let items = WellItem.items(from: .systemPage("places"), lookup: lookup,
                                   scenePages: [PageSpec(key: "places_house", tiles: [])], systemPages: system)
        #expect(items.map(\.text) == ["go > sys:places_house", "> sys:places_house", "park"])
        #expect(items.map(\.kind) == [.doorways, .folders, .words])
        guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse(items[1].text), lookup: lookup,
                                                      scenePages: [PageSpec(key: "places_house", tiles: [])],
                                                      systemPages: system) else {
            Issue.record("no plan"); return
        }
        #expect(plan.entry.key == "folder_house")
        #expect(plan.entry.link == TileToken.systemLink(to: "places_house"))
    }

    /// A pack word the vocabulary does not have yet travels as a new word.
    @Test func theWellOffersUnmadePackWordsAsNewWords() throws {
        let pack = try #require(PackCatalog.all.first)
        let items = WellItem.items(from: .pack(pack.id), lookup: [:], scenePages: [], systemPages: [])
        #expect(items.count == pack.words.count)
        #expect(items.allSatisfy { $0.key == nil && $0.text.contains(",") })
        if case .cell(.new, nil) = BoardCell.parse(items[0].text) {} else { Issue.record("not a new word") }
    }

    /// A word the vocabulary lacks is offered classes; a class fills in.
    @Test func anUnknownWordIsOfferedAClass() {
        let lookup = ["cow": tile("cow", "animal")]
        let offered = CellSuggestion.suggestions(for: "pony", lookup: lookup, scenePages: [], systemPages: [])
        #expect(offered.contains(.wordClass("animal")))
        #expect(CellSuggestion.wordClass("animal").applied(to: "pony") == "pony, animal")
        #expect(CellSuggestion.wordClass("animal").applied(to: "pony, an > barn")
                == "pony, animal > barn")
        let typed = CellSuggestion.suggestions(for: "pony, an", lookup: lookup, scenePages: [], systemPages: [])
        #expect(typed.first == .wordClass("animal"))
        #expect(CellSuggestion.suggestions(for: "pony, animal", lookup: lookup,
                                           scenePages: [], systemPages: []).isEmpty)
        #expect(!CellSuggestion.suggestions(for: "cow", lookup: lookup, scenePages: [], systemPages: [])
            .contains { $0.isWordClass })
    }
}
}
