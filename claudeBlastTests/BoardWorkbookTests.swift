// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardWorkbookTests.swift
//  claudeBlastTests
//
//  Spreadsheet reading and writing (`Spreadsheet`, `XLSX`), Google Sheets
//  links, and boards imported from and exported to workbooks (`BoardWorkbook`).
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct BoardWorkbookTests {

    // MARK: - CSV

    @Test func csvReadsQuotedCommasQuotesAndNewlines() {
        let text = "cat,\"cat, animal\",\"say \"\"hi\"\"\"\r\n\"two\nlines\",,go > places,,\n\n"
        #expect(Spreadsheet.rows(fromDelimited: text) ==
                [["cat", "cat, animal", "say \"hi\""], ["two\nlines", "", "go > places"]])
    }

    @Test func csvKeepsEmptyRowsBetweenRows() {
        #expect(Spreadsheet.rows(fromDelimited: "a\n\nb") == [["a"], [], ["b"]])
    }

    @Test func csvWritesWhatItReads() {
        let rows = [["cat, animal", "", "go > sys:places"], [], ["\"quoted\""]]
        #expect(Spreadsheet.rows(fromDelimited: Spreadsheet.csv(rows)) == rows)
    }

    @Test func aFileIsReadByItsExtension() throws {
        let tsv = try Spreadsheet.tabs(from: Data("a\tb, c\n".utf8), fileExtension: "tsv", name: "p")
        #expect(tsv == [SpreadsheetTab(name: "p", rows: [["a", "b, c"]])])
        let csv = try Spreadsheet.tabs(from: Data("\u{FEFF}a,b\n".utf8), fileExtension: "csv", name: "p")
        #expect(csv == [SpreadsheetTab(name: "p", rows: [["a", "b"]])])
    }

    // MARK: - XLSX

    @Test func columnLetters() {
        #expect(XLSX.column(0) == "A")
        #expect(XLSX.column(25) == "Z")
        #expect(XLSX.column(26) == "AA")
        #expect(XLSX.columnIndex(ofReference: "AB12") == 27)
        #expect(XLSX.columnIndex(ofReference: "J3") == 9)
    }

    @Test func aWrittenWorkbookReadsBack() throws {
        let tabs = [
            SpreadsheetTab(name: "home", rows: [["cat", "", "go > people"], [], ["", "a < b & \"c\""]]),
            SpreadsheetTab(name: "Tide Pools", rows: [["starfish, animal, Star Fish"]]),
            SpreadsheetTab(name: "empty", rows: []),
        ]
        #expect(try XLSX.read(XLSX.write(tabs)) == tabs)
    }

    @Test func tabNamesAreMadeLegalAndUnique() {
        let tabs = [SpreadsheetTab(name: "a/b", rows: []), SpreadsheetTab(name: "AB", rows: [])]
        #expect(XLSX.sheetName("a/b", index: 0, in: tabs) == "ab")
        #expect(XLSX.sheetName("AB", index: 1, in: [SpreadsheetTab(name: "ab", rows: []), tabs[1]]) == "AB 2")
        #expect(XLSX.sheetName("", index: 2, in: tabs) == "Sheet3")
    }

    /// The workbook Google Sheets serves for a shared link: shared strings,
    /// deflated entries, a gap in a row.
    @Test func aGoogleSheetsWorkbookReads() throws {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: "google-sheets-two-tabs", withExtension: "xlsx"),
            "fixture missing from the test bundle")
        let tabs = try XLSX.read(Data(contentsOf: url))
        #expect(tabs.map(\.name) == ["home", "people"])
        #expect(tabs[0].rows.count == 5)
        #expect(tabs[0].rows[0] == ["yes", "more", "good", "i don't know", "different", "bad", "finished", "no"])
        #expect(tabs[0].rows[1] == ["hello", "bye", "here", "", "", "bathroom", "hurt", "help"])
        #expect(tabs[1].rows[0].first == "brother")
    }

    @Test func notAWorkbookIsSaidSo() {
        #expect(throws: Spreadsheet.ReadError.notAWorkbook) {
            try XLSX.read(Data("PK not really a zip".utf8))
        }
    }

    // MARK: - Google links

    @Test func googleLinksBecomeTheirExport() {
        #expect(GoogleSheetLink.exportURL(for: "https://docs.google.com/spreadsheets/d/1uXe-5Ko_H8m/edit?usp=sharing")?
            .absoluteString == "https://docs.google.com/spreadsheets/d/1uXe-5Ko_H8m/export?format=xlsx")
        #expect(GoogleSheetLink.exportURL(for: " https://docs.google.com/spreadsheets/d/abc/edit#gid=12 ")?
            .absoluteString == "https://docs.google.com/spreadsheets/d/abc/export?format=xlsx")
        #expect(GoogleSheetLink.exportURL(for: "https://docs.google.com/spreadsheets/d/e/2PACX-1v/pubhtml")?
            .absoluteString == "https://docs.google.com/spreadsheets/d/e/2PACX-1v/pub?output=xlsx")
        #expect(GoogleSheetLink.exportURL(for: "https://docs.google.com/document/d/abc/edit") == nil)
        #expect(GoogleSheetLink.exportURL(for: "https://example.com/spreadsheets/d/abc") == nil)
    }

    @Test func googlesFileNameIsTheSheetsName() {
        #expect(GoogleSheetLink.filename(from: "attachment; filename=\"testscene.xlsx\"; filename*=UTF-8''test%20scene.xlsx")
                == "test scene")
        #expect(GoogleSheetLink.filename(from: "attachment; filename=\"Board.xlsx\"") == "Board")
        #expect(GoogleSheetLink.filename(from: nil) == nil)
    }

    // MARK: - Preview

    private func tile(_ key: String, _ cls: String = "object") -> TileModel {
        TileModel(key: key, value: key.replacingOccurrences(of: "_", with: " "), wordClass: cls)
    }

    private var lookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: ["go", "cat", "mom", "dad"].map { ($0, tile($0)) })
    }

    private let system = [PageSpec(key: "people", tiles: []), PageSpec(key: "places", tiles: [])]

    /// Home links to People before the People tab is read; a bare name is the
    /// scene's page even though BlasterAI 60 has one too.
    @Test func aLinkFindsATabWrittenAfterIt() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["> people", "go > places", "> sys:people"]]),
                    SpreadsheetTab(name: "People", rows: [["mom", "dad"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(preview.problems.isEmpty)
        #expect(preview.pages.map(\.key) == ["home", "people"])
        #expect(preview.homeKey == "home")
        #expect(preview.emptyPages == ["places"])
        #expect(preview.pages.map(\.placed) == [3, 2])
    }

    @Test func aWordDefinedOnALaterTabIsFound() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["pony"]]),
                    SpreadsheetTab(name: "farm", rows: [["pony, animal"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(preview.problems.isEmpty)
        #expect(preview.newWords.map(\.key) == ["pony"])
    }

    @Test func problemsSayWhereTheyAre() {
        let tabs = [SpreadsheetTab(name: "home", rows: [[], ["", "zebra, action"], ["cat"] + Array(repeating: "", count: 9) + ["cat"]]),
                    SpreadsheetTab(name: "HOME", rows: [["cat"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(preview.problems.map(\.id) == ["home!K3", "HOME!0", "home!B2"])
        #expect(preview.pages.count == 1)
        #expect(preview.homeKey == "home")
    }

    @Test func theFirstTabIsHomeUnlessOneIsNamedHome() {
        let first = BoardWorkbook.preview([SpreadsheetTab(name: "Start", rows: [["cat"]])], cols: 10,
                                          scenePages: [], lookup: lookup, systemPages: [])
        #expect(first.homeKey == "start")
        #expect(first.pages[0].title == "")
        let named = BoardWorkbook.preview([SpreadsheetTab(name: "Tide Pools", rows: [["cat"]]),
                                           SpreadsheetTab(name: "home", rows: [["cat"]])],
                                          cols: 10, scenePages: [], lookup: lookup, systemPages: [])
        #expect(named.homeKey == "home")
        #expect(named.pages[0].key == "tide_pools")
    }

    @Test func existingPagesAreFilledOrAskedAbout() {
        let pages = [PageSpec(key: "home", tiles: [TileEntry(key: "cat")]), PageSpec(key: "people", tiles: [.spacer()])]
        let tabs = [SpreadsheetTab(name: "home", rows: [["go"]]), SpreadsheetTab(name: "people", rows: [["mom"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: pages, lookup: lookup, systemPages: [])
        #expect(preview.pages.map(\.existing) == [.filled(tiles: 1), .empty])
    }

    // MARK: - Apply

    private func freshScene(_ ctx: ModelContext, pages: [PageSpec] = []) -> BlasterScene {
        for key in ["go", "cat", "mom", "dad"] { ctx.insert(tile(key)) }
        let scene = BlasterScene(name: "Imported")
        scene.pages = pages
        ctx.insert(scene)
        try? ctx.save()
        return scene
    }

    @Test func importingPlacesEveryCellWhereTheSheetHasIt() throws {
        let ctx = TestStore.freshContext()
        let scene = freshScene(ctx)
        let tabs = [SpreadsheetTab(name: "home", rows: [["> farm", "", "cat"], ["", "", "", "pony"]]),
                    SpreadsheetTab(name: "farm", rows: [["pony, animal", "go > home"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: scene.pages,
                                            lookup: currentLookup(ctx), systemPages: [])
        let result = BoardWorkbook.apply(preview, to: scene, cols: 10, replacing: [], systemPages: [], context: ctx)
        #expect(result.wordsCreated == 1)
        #expect(result.pagesWritten == ["home", "farm"])
        let home = try #require(scene.page(withKey: "home"))
        #expect(home.tiles.count == 14)
        #expect(home.tiles[0].link == "farm")
        #expect(home.tiles[0].isAudible == false)
        #expect(home.tiles[1].isSpacer)
        #expect(home.tiles[2].key == "cat")
        #expect(home.tiles[13].key == "pony")
        let farm = try #require(scene.page(withKey: "farm"))
        #expect(farm.tiles.map(\.key) == ["pony", "go"])
        let ponies = try ctx.fetch(FetchDescriptor<TileModel>()).filter { $0.key.hasPrefix("pony") }
        #expect(ponies.count == 1)
    }

    @Test func aFilledPageIsKeptUnlessReplacedAndAPlaceholderIsFilled() throws {
        let ctx = TestStore.freshContext()
        let scene = freshScene(ctx, pages: [PageSpec(key: "home", tiles: [TileEntry(key: "cat")]),
                                            PageSpec(key: "people", tiles: [])])
        let tabs = [SpreadsheetTab(name: "home", rows: [["go"]]), SpreadsheetTab(name: "people", rows: [["mom"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: scene.pages,
                                            lookup: currentLookup(ctx), systemPages: [])
        let kept = BoardWorkbook.apply(preview, to: scene, cols: 10, replacing: [], systemPages: [], context: ctx)
        #expect(kept.pagesSkipped == ["home"])
        #expect(scene.page(withKey: "home")?.tiles.map(\.key) == ["cat"])
        #expect(scene.page(withKey: "people")?.tiles.map(\.key) == ["mom"])
        BoardWorkbook.apply(preview, to: scene, cols: 10, replacing: ["home"], systemPages: [], context: ctx)
        #expect(scene.page(withKey: "home")?.tiles.map(\.key) == ["go"])
    }

    /// Writing the same homograph twice reuses the first, rather than making
    /// `right_describe_2`.
    @Test func aHomographWrittenTwiceIsOneWord() {
        let ctx = TestStore.freshContext()
        ctx.insert(tile("right", "places"))
        let word = BulkWordParser.Word(key: "right", wordClass: "describe", displayName: "right")
        var keys: Set<String> = ["right"]
        let first = WordCreator.findOrCreate(word, existing: currentLookup(ctx).values.map { $0 }, keys: &keys, context: ctx)
        try? ctx.save()
        let second = WordCreator.findOrCreate(word, existing: currentLookup(ctx).values.map { $0 }, keys: &keys, context: ctx)
        #expect(first?.key == "right_describe")
        #expect(second?.key == "right_describe")
    }

    /// A word written without a class that already exists is that word,
    /// whatever its class: no `cat_unspecified` beside `cat`.
    @Test func aWordWithoutAClassReusesTheWordThatExists() {
        let ctx = TestStore.freshContext()
        ctx.insert(tile("cat", "animal"))
        try? ctx.save()
        var keys: Set<String> = ["cat"]
        let bare = BulkWordParser.Word(key: "cat", wordClass: VocabularyClasses.unspecified, displayName: "cat")
        let found = WordCreator.findOrCreate(bare, existing: currentLookup(ctx).values.map { $0 }, keys: &keys, context: ctx)
        #expect(found?.key == "cat")
        #expect(found?.wordClass == "animal")
        let new = BulkWordParser.Word(key: "zorb", wordClass: VocabularyClasses.unspecified, displayName: "zorb")
        let made = WordCreator.findOrCreate(new, existing: currentLookup(ctx).values.map { $0 }, keys: &keys, context: ctx)
        #expect(made?.key == "zorb")
        #expect(made?.wordClass == VocabularyClasses.unspecified)
    }

    // MARK: - Fixes in the preview

    /// A word the vocabulary lacks, written without a class, comes in as one
    /// new Unspecified word in every cell that names it, its link kept; it is
    /// not a problem to settle before the import.
    @Test func aMissingWordComesInUnspecified() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["finished", "finished > done"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(preview.problems.isEmpty)
        #expect(preview.newWords == [BulkWordParser.Word(key: "finished", wordClass: VocabularyClasses.unspecified,
                                                         displayName: "finished")])
        #expect(preview.pages[0].placed == 2)
    }

    /// Giving a word a class in the sheet makes it a new word of that class.
    @Test func aMissingWordIsFixedByGivingItAClass() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["finished", "finished > done"]])]
        let fixed = BoardWorkbook.applying(["finished": .newWord(wordClass: "describe")], to: tabs)
        #expect(fixed[0].rows[0] == ["finished, describe", "finished, describe > done"])
        let after = BoardWorkbook.preview(fixed, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(after.problems.isEmpty)
        #expect(after.newWords.map(\.key) == ["finished"])
    }

    /// `finished, action` names a class the app does not have (`actions`):
    /// settled in the preview, not made with a class nothing knows.
    @Test func anUnknownClassIsSettledNotMade() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["finished, action > done", "finished"]])]
        let before = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(before.newWords.isEmpty)
        #expect(before.problems.map(\.kind) == [.unknownClass("finished", "action"), .missingWord("finished")])
        let fixed = BoardWorkbook.applying(["finished": .newWord(wordClass: "actions")], to: tabs)
        #expect(fixed[0].rows[0] == ["finished, actions > done", "finished, actions"])
        let after = BoardWorkbook.preview(fixed, cols: 10, scenePages: [], lookup: lookup, systemPages: system)
        #expect(after.problems.isEmpty)
        #expect(after.newWords.map(\.wordClass) == ["actions"])
    }

    @Test func anAmbiguousWordIsFixedByPickingOne() {
        var words = lookup
        words["right_"] = TileModel(key: "right_", value: "right", wordClass: "describe")
        words["right_side"] = TileModel(key: "right_side", value: "right", wordClass: "places")
        let tabs = [SpreadsheetTab(name: "home", rows: [["right"]])]
        let before = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: words, systemPages: [])
        #expect(before.problems.first?.kind == .ambiguous("right", ["right_", "right_side"]))
        let fixed = BoardWorkbook.applying(["right": .word(key: "right_side")], to: tabs)
        #expect(BoardWorkbook.preview(fixed, cols: 10, scenePages: [], lookup: words, systemPages: []).problems.isEmpty)
    }

    /// A new word the review removed is not made, and its cells stay empty.
    @Test func aDroppedNewWordIsNotMade() throws {
        let ctx = TestStore.freshContext()
        let scene = freshScene(ctx)
        let tabs = [SpreadsheetTab(name: "home", rows: [["pony, animal", "cat", "pony"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: scene.pages,
                                            lookup: currentLookup(ctx), systemPages: [])
        BoardWorkbook.apply(preview, to: scene, cols: 10, replacing: [], dropping: ["pony"],
                            systemPages: [], context: ctx)
        #expect(currentLookup(ctx)["pony"] == nil)
        #expect(scene.page(withKey: "home")?.tiles.map { $0.isSpacer ? "" : $0.key } == ["", "cat"])
    }

    /// The class on a new word's preview tile is the class it is made with:
    /// picked for a bare word, or changed from the sheet's. A word left alone
    /// stays as it came, and a word that already existed is never recoloured.
    @Test func aClassPickedInThePreviewIsKept() throws {
        let ctx = TestStore.freshContext()
        let scene = freshScene(ctx)
        let tabs = [SpreadsheetTab(name: "home", rows: [["zebu", "quokka", "pony, animal"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: scene.pages,
                                            lookup: currentLookup(ctx), systemPages: [])
        let before = Set(currentLookup(ctx).keys)
        BoardWorkbook.apply(preview, to: scene, cols: 10, replacing: [], systemPages: [], context: ctx)
        let created = Set(currentLookup(ctx).keys).subtracting(before)
        #expect(created.isSuperset(of: ["zebu", "quokka", "pony"]))
        let catClass = currentLookup(ctx)["cat"]?.wordClass
        let accepted = [
            GeneratedTile(key: "zebu", isAudible: true, link: "", displayName: "zebu", wordClass: "animal"),
            GeneratedTile(key: "quokka", isAudible: true, link: "", displayName: "quokka",
                          wordClass: VocabularyClasses.unspecified),
            GeneratedTile(key: "pony", isAudible: true, link: "", displayName: "pony", wordClass: "toy"),
            GeneratedTile(key: "cat", isAudible: true, link: "", displayName: "cat", wordClass: "food"),
        ]
        BoardWorkbook.applyPickedClasses(accepted, created: created, context: ctx)
        let words = currentLookup(ctx)
        #expect(words["zebu"]?.wordClass == "animal")
        #expect(words["quokka"]?.wordClass == VocabularyClasses.unspecified)
        #expect(words["pony"]?.wordClass == "toy")
        #expect(words["cat"]?.wordClass == catClass)
    }

    // MARK: - Routing and the page preview

    @Test func anImportGoesWhereItsBytesBelong() throws {
        #expect(try ImportSource.kind(of: Data(), fileExtension: "blasterscene") == .blaster("blasterscene"))
        #expect(try ImportSource.kind(of: Data(), fileExtension: "XLSX") == .spreadsheet("xlsx"))
        #expect(try ImportSource.kind(of: Data([0x50, 0x4B, 3, 4]), fileExtension: "") == .spreadsheet("xlsx"))
        #expect(try ImportSource.kind(of: Data("\u{FEFF} {\"@type\": \"\(BlasterSceneFormat.mediaType)\"}".utf8),
                                      fileExtension: "") == .blaster("blasterscene"))
        #expect(try ImportSource.kind(of: Data("{\"@type\": \"\(BlasterPackFormat.mediaType)\"}".utf8),
                                      fileExtension: "json") == .blaster("blasterpack"))
        #expect(try ImportSource.kind(of: Data("cat,dog\n".utf8), fileExtension: "") == .spreadsheet("csv"))
    }

    /// The preview draws each tab where the sheet puts it, gaps kept, and
    /// marks the words the import makes as new.
    @Test func eachTabPreviewsCellForCell() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["cat", "", "pony, animal"], ["", "go > farm"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: [])
        let page = preview.pages[0]
        let board = page.board(cols: 10)
        #expect(board.tiles.map { $0.isSpacer ? "" : $0.key } == ["cat", "", "pony", "", "", "", "", "", "", "", "", "go"])
        #expect(board.tiles[11].link == "farm")
        let generated = page.generated
        #expect(generated.tiles.map(\.key) == ["cat", "pony", "go"])
        #expect(generated.tiles.map(\.isProposedNew) == [false, true, false])
    }

    // MARK: - Finding the board

    private func origin(_ rows: [[String]], _ words: [String: TileModel]? = nil) -> BoardWorkbook.Origin {
        let preview = BoardWorkbook.preview([SpreadsheetTab(name: "home", rows: rows)], cols: 10,
                                            scenePages: [], lookup: words ?? lookup, systemPages: [])
        return preview.pages.first?.origin ?? .topLeft
    }

    /// Mark's sheet: details rows, two blank rows, the board at A5, on a tab
    /// nobody named.
    @Test func aSheetWithDetailsStartsBelowThem() throws {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: "google-sheets-structure-issues", withExtension: "xlsx"))
        let tabs = try XLSX.read(Data(contentsOf: url))
        let words = Dictionary(uniqueKeysWithValues: ["ball", "bubbles", "art"].map { ($0, tile($0)) })
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: words, systemPages: [])
        let page = try #require(preview.pages.first)
        #expect(page.key == "home")
        #expect(page.title == "")
        #expect(page.origin.cell == "A5")
        #expect(page.origin.skipped == [.details(2)])
        #expect(preview.details["description"] == "test scene based on play_activities")
        #expect(preview.details["owner"] == "Mark")
        #expect(page.cells.first?.index == 0)
        #expect(page.cells.first?.text == "ball")
    }

    /// Added to a scene, an unnamed tab is named after its sheet, not Home —
    /// it must not offer to replace the scene's own Home page.
    @Test func anUnnamedTabAddedToASceneIsNamedForItsSheet() {
        let tabs = [SpreadsheetTab(name: "Sheet1", rows: [["cat"]])]
        let home = [PageSpec(key: "home", tiles: [TileEntry(key: "dog")])]
        let added = BoardWorkbook.preview(tabs, cols: 10, scenePages: home, lookup: lookup, systemPages: [],
                                          unnamedTab: "Structure Issues")
        #expect(added.pages.map(\.key) == ["structure_issues"])
        #expect(PageNaming.displayName(added.pages[0].key) == "Structure Issues")
        #expect(added.pages[0].existing == .none)
    }

    @Test func aTitleAndLabelsAreLeftOut() {
        let rows = [["Brandi's board v2"], [],
                    ["", "A", "B", "C"],
                    ["1", "cat", "mom", "dad"],
                    ["2", "go", "", "cat"]]
        let found = origin(rows)
        #expect(found.cell == "B4")
        #expect(found.skipped == [.columnLetters, .title(1), .rowNumbers])
        #expect(found.summary == "Starts at B4 · skipped the column labels, a title row, the row labels")
    }

    /// A numbers page starts 1…10 too: followed by more numbers, it is the board.
    @Test func aNumbersPageIsNotLabels() {
        let rows = [(1...10).map(String.init), (11...20).map(String.init)]
        #expect(origin(rows) == .topLeft)
    }

    /// An empty first row with nothing above it is the board's own.
    @Test func aBoardsOwnEmptyFirstRowIsKept() {
        #expect(origin([[], ["cat", "dog"]]) == .topLeft)
    }

    @Test func aBoardMarkerSaysWhere() {
        let rows = [["Owner: me", "anything"], ["notes here"], ["", "#board"], ["", "cat"]]
        let found = origin(rows)
        #expect(found.cell == "B4")
        #expect(found.skipped == [.marker])
    }

    /// A grid typed from column B on is moved left only when it would
    /// otherwise run past the board's ten columns.
    @Test func aGridTypedFurtherRightIsFound() {
        let wide = [[""] + Array(repeating: "cat", count: 10)]
        #expect(origin(wide).cell == "B1")
        let narrow = [["", "cat", "dog"]]
        #expect(origin(narrow) == .topLeft)
    }

    /// A chosen start wins, and problems keep the sheet's own addresses.
    @Test func aChosenStartWinsAndAddressesStayTheSheets() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["Title"], ["cat", "zebra goes here"]])]
        let moved = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: [],
                                          origins: ["home": BoardWorkbook.Origin(row: 1, col: 1)])
        #expect(moved.pages[0].origin.cell == "B2")
        #expect(moved.problems.map(\.id) == ["home!B2"])
    }

    @Test func aSentenceIsANoteNotAWord() {
        let tabs = [SpreadsheetTab(name: "home", rows: [["cat", "remember to add more animals"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: lookup, systemPages: [])
        #expect(preview.problems.map(\.kind) == [.note])
    }

    // MARK: - Class list

    /// `Resources/word_classes.json` is where the app's classes come from, and
    /// the list spreadsheet authors read. It loads, and holds every class the
    /// app depends on by name.
    @Test func theClassListLoadsFromItsFile() {
        let names = VocabularyClasses.all.map(\.name)
        #expect(names.count == Set(names).count)
        for name in ["people", "animal", "describe", "object", "letter", "number",
                     "core", "navigation", "question", PageLink.wordClass] {
            #expect(VocabularyClasses.known(name) != nil, "\(name)")
        }
        #expect(VocabularyClasses.known(PageLink.wordClass)?.isCaregiverSelectable == false)
        #expect(VocabularyClasses.known("number")?.defaultPartOfSpeech == .determiner)
        #expect(VocabularyClasses.known("letter")?.defaultPartOfSpeech == nil)
        #expect(VocabularyClasses.load(Data("nope".utf8)).isEmpty)
    }

    // MARK: - Export

    /// BlasterAI 60, exported to a workbook and imported into an empty scene,
    /// is the same board: every placement, in every cell, every folder's
    /// picture, and every page's cover — which the `#covers` tab carries, so
    /// `> people_family` in a new scene shows `folder_family` again.
    @Test func blasterAI60RoundTripsThroughAWorkbook() throws {
        let ctx = TestStore.freshContext()
        let loaded = BootstrapLoader.loadDefaultVocabulary(context: ctx)
        let original = loaded.scene
        let cols = (original.designedLayout?.grid.cols) ?? 10
        let tabs = BoardWorkbook.tabs(for: original.pages, homeKey: original.homePageKey, cols: cols,
                                      isSystemScene: true)
        #expect(tabs.last?.name == BoardWorkbook.coversTab)
        #expect(tabs.first.map { BoardCell.pageKey($0.name) } == original.homePageKey)
        let read = try XLSX.read(XLSX.write(tabs))
        #expect(read == tabs)

        let copy = BlasterScene(name: "Copy")
        ctx.insert(copy)
        let preview = BoardWorkbook.preview(read, cols: cols, scenePages: [], lookup: currentLookup(ctx), systemPages: [])
        #expect(preview.problems.isEmpty, "\(preview.problems.prefix(10))")
        #expect(preview.newWords.isEmpty)
        BoardWorkbook.apply(preview, to: copy, cols: cols, replacing: [], systemPages: [], context: ctx)

        func placements(_ tiles: [TileEntry]) -> [String] {
            var out = tiles.map { $0.isSpacer ? "" : "\($0.key)|\($0.link)|\($0.isAudible)" }
            while out.last == "" { out.removeLast() }
            return out
        }
        var mismatches: [String] = []
        for page in original.pages {
            let back = copy.page(withKey: page.key)?.tiles ?? []
            let a = placements(page.tiles), b = placements(back)
            if a != b {
                let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                mismatches.append("\(page.key)@\(i): \(i < a.count ? a[i] : "-") ≠ \(i < b.count ? b[i] : "-")")
            }
        }
        #expect(copy.pages.count == original.pages.count)
        #expect(mismatches.isEmpty, "\(mismatches)")
        let covers = original.pages.filter { copy.page(withKey: $0.key)?.cover != $0.cover }.map(\.key)
        #expect(covers.isEmpty, "\(covers)")
    }

    private func currentLookup(_ ctx: ModelContext) -> [String: TileModel] {
        let tiles = (try? ctx.fetch(FetchDescriptor<TileModel>())) ?? []
        return Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
}

private final class BundleToken {}
