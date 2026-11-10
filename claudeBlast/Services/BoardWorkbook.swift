// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardWorkbook.swift
//  claudeBlast
//
//  A scene as a spreadsheet: one tab per page, one sheet row per board row.
//

import Foundation
import SwiftData

/// A board drawn in a spreadsheet, and the scene it becomes.
///
/// - **A tab is a page.** Its name is the page's name; the first tab, or one
///   named `home`, is the home page.
/// - **A row is a board row,** as wide as the grid (10 on the iPad board), with
///   the inherited system row left out. Rows past a screen's last continue
///   onto the next screen, exactly as the page editor lays them out.
/// - **A cell is a `BoardCell`:** whatever can be typed in the grid can be
///   typed in the sheet, and means the same.
///
/// - **A `#covers` tab** names each page's cover, a row per page: the page,
///   then the word whose picture stands for it. Optional; export writes it.
///
/// Every tab's name is known before any cell is read, so `> people` on the
/// first tab finds a People tab written after it. A bare name no tab or page
/// has becomes an empty page — a link forward to a page not written yet.
enum BoardWorkbook {
    struct Problem: Equatable, Identifiable {
        /// What went wrong, where the preview can offer to fix it.
        enum Kind: Equatable {
            /// A word the vocabulary does not have: give it a class to make it.
            case missingWord(String)
            /// A name more than one word has: pick one.
            case ambiguous(String, [String])
            /// A new word whose class is not one of the app's: pick one.
            case unknownClass(String, String)
            /// Prose in a cell — several words that are no word: a note to
            /// the reader, left out rather than settled.
            case note
            case other
        }
        var page: String
        /// One-based, as the spreadsheet numbers them.
        var row: Int
        var column: String
        var text: String
        var message: String
        var kind: Kind = .other
        var id: String { "\(page)!\(column)\(row)" }
    }

    /// What importing one tab does.
    struct PagePlan: Equatable, Identifiable {
        enum Existing: Equatable {
            /// No page of that name: made.
            case none
            /// A page with nothing on it — a placeholder a link made: filled.
            case empty
            /// A page with words: replaced only if the caregiver says so.
            case filled(tiles: Int)
        }
        var key: String
        /// The tab's name, kept as the page's name when it is not the one its
        /// key would be given.
        var title: String
        var existing: Existing
        /// Cells with something to place, by board index.
        var cells: [(index: Int, text: String)]
        /// Where the tab's board starts (`detectOrigin`, or the caregiver's
        /// choice).
        var origin: Origin = .topLeft
        /// The tab it came from, as the sheet names it.
        var tabName: String = ""
        /// The cover the `#covers` tab names, by key; empty leaves it as is.
        var cover: String = ""
        /// Each placed cell as it would land, for the page preview: the
        /// placement, and the new word it makes, if any.
        var resolved: [(index: Int, entry: TileEntry, newWord: BulkWordParser.Word?)] = []

        /// The page as the preview draws it, from row 2 on (the system row is
        /// the board's): every cell where the sheet puts it, gaps kept.
        func board(cols: Int) -> PageSpec {
            let cells = PageCells(grid: (cols, 1), inheritsChrome: false)
            var tiles: [TileEntry] = []
            for item in resolved { tiles = cells.setting(item.entry, at: item.index, in: tiles) }
            return PageSpec(key: key, displayName: title, tiles: tiles, cover: cover)
        }

        /// The page as the standard page preview reads it: each placement,
        /// a new word carrying its name and class so it is reviewed as new.
        var generated: GeneratedPage {
            GeneratedPage(key: key, tiles: resolved.map { item in
                GeneratedTile(key: item.entry.key, isAudible: item.entry.isAudible, link: item.entry.link,
                              displayName: item.newWord?.displayName, wordClass: item.newWord?.wordClass)
            })
        }
        var placed: Int
        var id: String { key }

        static func == (a: PagePlan, b: PagePlan) -> Bool {
            a.key == b.key && a.title == b.title && a.existing == b.existing && a.placed == b.placed
                && a.cover == b.cover
                && a.cells.map(\.index) == b.cells.map(\.index) && a.cells.map(\.text) == b.cells.map(\.text)
        }
    }

    struct Preview: Equatable {
        var pages: [PagePlan]
        var homeKey: String?
        /// Words the import makes, in the order first written.
        var newWords: [BulkWordParser.Word]
        /// Pages a link names that no tab fills: made empty.
        var emptyPages: [String]
        var problems: [Problem]
        /// `Name:`, `Description:` and the like from the sheet's details rows.
        var details: [String: String] = [:]

        var hasWork: Bool { !pages.isEmpty }
    }

    /// What importing `tabs` into a scene with `scenePages` would do. Pure:
    /// nothing is created.
    ///
    /// - Parameters:
    ///   - cols: the board's columns; cells past them are reported, not placed.
    ///   - lookup: every word, by key.
    ///   - systemPages: BlasterAI 60's pages, for `sys:` links.
    ///   - origins: where a tab's board starts, by tab name, when the
    ///     caregiver moved it; any other tab's is detected.
    ///   - unnamedTab: the page a first tab nobody named (`Sheet1`) becomes:
    ///     Home for a new scene, the sheet's own name for pages added to one.
    static func preview(_ tabs: [SpreadsheetTab], cols: Int, scenePages: [PageSpec],
                        lookup: [String: TileModel], systemPages: [PageSpec],
                        origins: [String: Origin] = [:], unnamedTab: String = "home") -> Preview {
        var preview = Preview(pages: [], homeKey: nil, newWords: [], emptyPages: [], problems: [])
        var seen = Set<String>()
        let coverTab = tabs.first { $0.name.lowercased() == coversTab }
        let pageTabs = tabs.filter { $0.name.lowercased() != coversTab }
        preview.details = pageTabs.first.map(details(of:)) ?? [:]
        let reads: (String) -> Bool = { text in
            switch BoardCell.parse(text) {
            case .spacer, .invalid: return false
            case .cell(.existing(let word)?, _):
                return BoardCell.existingWord(word, lookup: lookup) != .missing
            case .cell: return true
            }
        }
        for (t, tab) in pageTabs.enumerated() {
            // Sheet1 is no page's name: the first one is Home.
            let unnamed = t == 0 && isDefaultTabName(tab.name)
            // The SystemRow tab is the scene's own row 1, not a page.
            let key = isRowTab(tab.name) ? BlasterScene.rowPageKey
                : BoardCell.pageKey(unnamed ? unnamedTab : tab.name)
            guard !key.isEmpty, seen.insert(key).inserted else {
                preview.problems.append(Problem(page: tab.name, row: 0, column: "", text: tab.name,
                                                message: key.isEmpty ? "A tab needs a name" : "Two tabs are both \u{201C}\(key)\u{201D}; the second was skipped"))
                continue
            }
            let existing: PagePlan.Existing
            if key == BlasterScene.rowPageKey {
                existing = .none
            } else if let page = scenePages.first(where: { $0.key == key }) {
                let words = page.tiles.filter { !$0.isSpacer }.count
                existing = words == 0 ? .empty : .filled(tiles: words)
            } else {
                existing = .none
            }
            let origin = origins[tab.name] ?? detectOrigin(tab, cols: cols, reads: reads)
            var cells: [(Int, String)] = []
            for (r, row) in tab.rows.enumerated() where r >= origin.row {
                for (c, raw) in row.enumerated() where c >= origin.col {
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, text.lowercased() != boardMarker else { continue }
                    let br = r - origin.row, bc = c - origin.col
                    guard bc < cols else {
                        preview.problems.append(Problem(page: key, row: r + 1, column: XLSX.column(c), text: text,
                                                        message: "Past the board's \(cols) columns"))
                        continue
                    }
                    cells.append((br * cols + bc, text))
                }
            }
            let shown = unnamed ? unnamedTab : tab.name
            let title = key == BlasterScene.rowPageKey || PageNaming.displayName(key) == shown
                || shown == key || key == "home" ? "" : shown
            var plan = PagePlan(key: key, title: title, existing: existing, cells: cells, placed: 0)
            plan.origin = origin
            plan.tabName = tab.name
            preview.pages.append(plan)
        }
        guard !preview.pages.isEmpty else { return preview }
        let boardPages = preview.pages.filter { $0.key != BlasterScene.rowPageKey }
        preview.homeKey = boardPages.first { $0.key == "home" }?.key ?? boardPages.first?.key

        // Every tab is a page before any cell is resolved.
        var pages = scenePages
        for plan in preview.pages where !pages.contains(where: { $0.key == plan.key }) {
            pages.append(PageSpec(key: plan.key, displayName: plan.title, tiles: []))
        }
        // Every new word is a word before any cell is resolved, so `pony` on
        // one tab finds the `pony, animal` written on a later one.
        var simulated = lookup
        // Every key the sheet writes with a class, known or not. A bare `pony`
        // waits for the `pony, animal` written elsewhere, and a bare word whose
        // only class is one to settle stays a word to settle with it.
        var classedKeys: Set<String> = []
        for plan in preview.pages {
            for (_, text) in plan.cells {
                if case .cell(.new(let word)?, _) = BoardCell.parse(text) {
                    classedKeys.insert(TileModel.normalizeKey(word.key))
                }
            }
        }
        for plan in preview.pages {
            for (_, text) in plan.cells {
                guard case .cell(.new(let word)?, _) = BoardCell.parse(text),
                      isKnownClass(word.wordClass) else { continue }
                let key = TileModel.normalizeKey(word.key)
                if let tile = simulated[key], tile.wordClass == word.wordClass { continue }
                if preview.newWords.contains(where: { TileModel.normalizeKey($0.key) == key && $0.wordClass == word.wordClass }) { continue }
                preview.newWords.append(word)
                if simulated[key] == nil {
                    simulated[key] = TileModel(key: key, value: word.displayName, wordClass: word.wordClass)
                }
            }
        }
        // A bare word the vocabulary still lacks is a new word with no class
        // yet, unless it is a note (three words or more, left out).
        for plan in preview.pages {
            for (_, text) in plan.cells {
                guard case .cell(.existing(let bare)?, _) = BoardCell.parse(text), !Self.isNote(bare),
                      case .missing = BoardCell.existingWord(bare, lookup: simulated) else { continue }
                let key = TileModel.normalizeKey(bare)
                guard !key.isEmpty, !classedKeys.contains(key) else { continue }
                let word = BulkWordParser.Word(key: bare, wordClass: VocabularyClasses.unspecified,
                                               displayName: bare)
                preview.newWords.append(word)
                simulated[key] = TileModel(key: key, value: bare, wordClass: word.wordClass)
            }
        }
        // Covers, before any folder is resolved, so `> people` shows People's.
        for (r, row) in (coverTab?.rows ?? []).enumerated() {
            guard row.count >= 2 else { continue }
            let pageName = row[0].trimmingCharacters(in: .whitespaces)
            let word = row[1].trimmingCharacters(in: .whitespaces)
            guard !pageName.isEmpty, !word.isEmpty else { continue }
            let pageKey = BoardCell.pageKey(pageName)
            guard let i = preview.pages.firstIndex(where: { $0.key == pageKey }) else {
                if !pages.contains(where: { $0.key == pageKey }) {
                    preview.problems.append(Problem(page: coversTab, row: r + 1, column: "A", text: pageName,
                                                    message: "No tab or page \u{201C}\(pageName)\u{201D}"))
                }
                continue
            }
            let key = TileModel.normalizeKey(word)
            let found: String?
            if simulated[key] != nil { found = key }
            else if case .found(let match) = BoardCell.existingWord(word, lookup: simulated) { found = match }
            else { found = nil }
            guard let found else {
                preview.problems.append(Problem(page: coversTab, row: r + 1, column: "B", text: word,
                                                message: "No word \u{201C}\(word)\u{201D} for \(pageName)'s cover"))
                continue
            }
            preview.pages[i].cover = found
            if let p = pages.firstIndex(where: { $0.key == pageKey }) { pages[p].cover = found }
        }

        var empty: [String] = []
        for i in preview.pages.indices {
            var placed = 0
            preview.pages[i].resolved = []
            for (index, text) in preview.pages[i].cells {
                // A bare word the planning above left unmade — a note, or a
                // word whose class is still to settle — is a problem, as it
                // was before words could go in unclassified; resolving it now
                // would make it a word.
                if case .cell(.existing(let bare)?, _) = BoardCell.parse(text),
                   case .missing = BoardCell.existingWord(bare, lookup: simulated) {
                    let cells = PageCells(grid: (cols, 1), inheritsChrome: false)
                    let origin = preview.pages[i].origin
                    let isNote = Self.isNote(bare)
                    preview.problems.append(Problem(page: preview.pages[i].key,
                                                    row: origin.row + cells.absoluteRow(index) + 1,
                                                    column: XLSX.column(origin.col + cells.column(index)), text: text,
                                                    message: isNote ? "A note, left out"
                                                        : "No word \u{201C}\(bare)\u{201D}. Add a class to make one",
                                                    kind: isNote ? .note : .missingWord(bare)))
                    continue
                }
                if case .cell(.new(let word)?, _) = BoardCell.parse(text), !isKnownClass(word.wordClass) {
                    let cells = PageCells(grid: (cols, 1), inheritsChrome: false)
                    preview.problems.append(Problem(
                        page: preview.pages[i].key, row: preview.pages[i].origin.row + cells.absoluteRow(index) + 1,
                        column: XLSX.column(preview.pages[i].origin.col + cells.column(index)), text: text,
                        message: "\u{201C}\(word.wordClass)\u{201D} isn't a word class",
                        kind: .unknownClass(word.key, word.wordClass)))
                    continue
                }
                switch BoardCell.resolve(BoardCell.parse(text), lookup: simulated,
                                         scenePages: pages, systemPages: systemPages) {
                case .error(let message):
                    let cells = PageCells(grid: (cols, 1), inheritsChrome: false)
                    var kind = Problem.Kind.other
                    if case .cell(.existing(let word)?, _) = BoardCell.parse(text) {
                        switch BoardCell.existingWord(word, lookup: simulated) {
                        case .missing:
                            kind = Self.isNote(word) ? .note : .missingWord(word)
                        case .ambiguous(let keys): kind = .ambiguous(word, keys)
                        case .found: break
                        }
                    }
                    // Named as the sheet names the cell, not by board position.
                    let origin = preview.pages[i].origin
                    preview.problems.append(Problem(page: preview.pages[i].key,
                                                    row: origin.row + cells.absoluteRow(index) + 1,
                                                    column: XLSX.column(origin.col + cells.column(index)), text: text,
                                                    message: kind == .note ? "A note, left out" : message, kind: kind))
                case .plan(let plan):
                    placed += 1
                    if !plan.entry.isSpacer {
                        // A word the import makes is new on every cell that names
                        // it, though resolving against the planned words found it.
                        let made = plan.newWord ?? (lookup[plan.entry.key] == nil
                            ? preview.newWords.first { TileModel.normalizeKey($0.key) == plan.entry.key } : nil)
                        preview.pages[i].resolved.append((index, plan.entry, made))
                    }
                    if let page = plan.newPage, !empty.contains(page) { empty.append(page) }
                }
            }
            preview.pages[i].placed = placed
        }
        preview.emptyPages = empty
        return preview
    }

    struct Result: Equatable {
        var pagesWritten: [String]
        var pagesSkipped: [String]
        var wordsCreated: Int
    }

    /// Carries out `preview` in `scene`. Each cell is committed as if typed in
    /// the grid; a cell with a problem is left empty.
    ///
    /// - Parameter replacing: pages with words that the caregiver chose to
    ///   overwrite. Any other filled page is left as it is.
    /// A fix the caregiver chose in the preview for a word the sheet names.
    enum Fix: Equatable {
        /// Make it a new word of this class.
        case newWord(wordClass: String)
        /// It means this word.
        case word(key: String)
    }

    /// A class a new word may have: one of the caregiver's.
    /// Three words or more in a cell is a note to the reader, not a word.
    static func isNote(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count >= 3
    }

    static func isKnownClass(_ name: String) -> Bool {
        VocabularyClasses.known(name)?.isCaregiverSelectable == true
    }

    /// The key a fix is filed under: the word as written, folded.
    static func fixKey(_ word: String) -> String { WordFinder.normalize(word) }

    /// `tabs` with every cell naming a fixed word rewritten as the fix says —
    /// `finished` becomes `finished, describe`, or the chosen word's key — so
    /// the sheet imports as if it had been written that way.
    static func applying(_ fixes: [String: Fix], to tabs: [SpreadsheetTab]) -> [SpreadsheetTab] {
        guard !fixes.isEmpty else { return tabs }
        return tabs.map { tab in
            guard tab.name.lowercased() != coversTab else { return tab }
            var tab = tab
            tab.rows = tab.rows.map { row in
                row.map { text in
                    let rest = text.firstIndex(of: ">").map { " " + text[$0...] } ?? ""
                    switch BoardCell.parse(text) {
                    case .cell(.existing(let word)?, _):
                        guard let fix = fixes[fixKey(word)] else { return text }
                        switch fix {
                        case .newWord(let cls): return "\(word), \(cls)" + rest
                        case .word(let key): return key + rest
                        }
                    case .cell(.new(let word)?, _):
                        // A new word whose class was corrected.
                        guard case .newWord(let cls)? = fixes[fixKey(word.key)] else { return text }
                        let shown = word.displayName == word.key ? "" : ", \(word.displayName)"
                        return "\(word.key), \(cls)\(shown)" + rest
                    default:
                        return text
                    }
                }
            }
            return tab
        }
    }

    /// - Parameter dropping: new words, by key, the caregiver chose not to
    ///   make (the moderation review). Cells naming them are left empty.
    @MainActor
    /// The classes the preview's tiles carry, given to the words this import
    /// made. A bare word comes in Unspecified, and the caregiver may have
    /// picked a class on its tile; a classed word may have had its class
    /// changed there. Only words in `created` — made by this import — change:
    /// a tile can carry the key of a word that already existed (the sheet's
    /// `cat, animal` beside the vocabulary's `cat`), and that word is not the
    /// import's to recolour.
    static func applyPickedClasses(_ tiles: [GeneratedTile], created: Set<String>, context: ModelContext) {
        var picked: [String: String] = [:]
        for gt in tiles where gt.isProposedNew {
            let key = TileModel.normalizeKey(gt.key)
            guard created.contains(key), let wc = gt.wordClass else { continue }
            picked[key] = wc
        }
        guard !picked.isEmpty else { return }
        let keys = Array(picked.keys)
        let descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { keys.contains($0.key) })
        for tile in (try? context.fetch(descriptor)) ?? [] {
            if let wc = picked[tile.key], tile.wordClass != wc { tile.wordClass = wc }
        }
        try? context.save()
    }

    @discardableResult
    static func apply(_ preview: Preview, to scene: BlasterScene, cols: Int, replacing: Set<String>,
                      dropping: Set<String> = [],
                      systemPages: [PageSpec], context: ModelContext) -> Result {
        var result = Result(pagesWritten: [], pagesSkipped: [], wordsCreated: 0)
        var lookup = currentLookup(context)

        // Words first, so a cell can name a word another tab defines.
        var keys = Set(lookup.keys)
        let before = keys.count
        for word in preview.newWords where !dropping.contains(TileModel.normalizeKey(word.key)) {
            WordCreator.findOrCreate(word, existing: Array(lookup.values), keys: &keys, context: context)
        }
        result.wordsCreated = keys.count - before

        // Then every page the import writes, so links between them resolve.
        let writing = preview.pages.filter { plan in
            if case .filled = plan.existing { return replacing.contains(plan.key) }
            return true
        }
        result.pagesSkipped = preview.pages.map(\.key).filter { key in !writing.contains { $0.key == key } }
        var pages = scene.pages
        for plan in writing where plan.key != BlasterScene.rowPageKey
            && !pages.contains(where: { $0.key == plan.key }) {
            pages.append(PageSpec(key: plan.key, displayName: plan.title, tiles: []))
            PageLink.mint(pageKey: plan.key, displayName: plan.title.isEmpty ? PageNaming.displayName(plan.key) : plan.title,
                          context: context, existing: lookup)
        }
        for plan in writing where !plan.cover.isEmpty {
            if let i = pages.firstIndex(where: { $0.key == plan.key }) { pages[i].cover = plan.cover }
        }
        scene.pages = pages
        // A SystemRow tab makes the row the scene's own.
        if writing.contains(where: { $0.key == BlasterScene.rowPageKey }), scene.ownRow == nil {
            scene.ownRow = PageSpec(key: BlasterScene.rowPageKey, tiles: [])
        }
        try? context.save()
        lookup = currentLookup(context)

        let geometry = PageCells(grid: (cols, 1), inheritsChrome: false)
        for plan in writing {
            var tiles: [TileEntry] = []
            for (index, text) in plan.cells {
                if case .cell(.new(let word)?, _) = BoardCell.parse(text),
                   dropping.contains(TileModel.normalizeKey(word.key)) { continue }
                // A bare word the vocabulary lacks is made only if the preview
                // planned it (Unspecified, not dropped); otherwise it was a
                // problem, and a cell with a problem is left empty.
                if case .cell(.existing(let bare)?, _) = BoardCell.parse(text),
                   case .missing = BoardCell.existingWord(bare, lookup: lookup) {
                    let key = TileModel.normalizeKey(bare)
                    let planned = preview.newWords.contains {
                        TileModel.normalizeKey($0.key) == key && VocabularyClasses.isUnspecified($0.wordClass)
                    }
                    if !planned || dropping.contains(key) { continue }
                }
                guard case .plan(let cell) = BoardCell.resolve(
                    BoardCell.parse(text), lookup: lookup, scenePages: scene.pages,
                    systemPages: systemPages) else { continue }
                let entry = BoardCell.commit(cell, replacing: nil, in: scene, systemPages: systemPages,
                                             lookup: lookup, context: context)
                if cell.newWord != nil || cell.newPage != nil || cell.folderFor != nil {
                    lookup = currentLookup(context)
                }
                tiles = geometry.setting(entry, at: index, in: tiles)
            }
            scene.updatePage(plan.key) { page in
                page.tiles = tiles
                if !plan.title.isEmpty { page.displayName = plan.title }
            }
            result.pagesWritten.append(plan.key)
        }
        try? context.save()
        return result
    }

    @MainActor
    private static func currentLookup(_ context: ModelContext) -> [String: TileModel] {
        let tiles = (try? context.fetch(FetchDescriptor<TileModel>())) ?? []
        return Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Export

    /// `pages` as tabs, home first: each cell as the grid would show it, so
    /// the workbook imports back as the same board.
    ///
    /// Levels, conceal and per-page labels do not travel: a cell's text does
    /// not carry them.
    ///
    /// `row`: the scene's own row 1, written as a SystemRow tab after the pages.
    static func tabs(for pages: [PageSpec], homeKey: String, cols: Int,
                     systemPages: [PageSpec] = [], isSystemScene: Bool = false,
                     row: PageSpec? = nil) -> [SpreadsheetTab] {
        let ordered = pages.filter { $0.key == homeKey } + pages.filter { $0.key != homeKey }
        let geometry = PageCells(grid: (cols, 1), inheritsChrome: false)
        let cover = BoardCell.covers(scenePages: pages, systemPages: systemPages, isSystemScene: isSystemScene)
        let covers = ordered.map { [$0.key, PageCover.key(of: $0, in: pages, isSystemScene: isSystemScene)] }
        return (ordered + (row.map { [$0] } ?? [])).map { page in
            var rows: [[String]] = []
            for (index, entry) in page.tiles.enumerated() where !entry.isSpacer {
                let r = geometry.absoluteRow(index), c = geometry.column(index)
                while rows.count <= r { rows.append([]) }
                while rows[r].count <= c { rows[r].append("") }
                rows[r][c] = BoardCell.format(entry, cover: cover)
            }
            // A custom name is the tab's name when it still finds the page.
            if page.key == BlasterScene.rowPageKey { return SpreadsheetTab(name: rowTab, rows: rows) }
            let name = page.hasCustomName && BoardCell.pageKey(page.displayName) == page.key
                ? page.displayName : page.key
            return SpreadsheetTab(name: name, rows: rows)
        } + [SpreadsheetTab(name: coversTab, rows: covers)]
    }

    /// The tab that names each page's cover.
    static let coversTab = "#covers"

    /// The tab that is the scene's own navigation bar (row 1 on a 10×6
    /// board): one row, the grid's width.
    static let rowTab = "Navigation Bar"

    /// `Navigation Bar`, `NavBar`, `SystemRow` or `Row 1`, in any case.
    static func isRowTab(_ name: String) -> Bool {
        let squeezed = name.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
        return ["navigationbar", "navbar", "systemrow", "row1"].contains(squeezed)
    }
}

/// A Google Sheets link as the workbook Google serves for it.
///
/// A sheet shared "Anyone with the link" downloads as .xlsx with no sign-in;
/// a private one answers with a sign-in page, which is how it is told apart.
enum GoogleSheetLink {
    static func exportURL(for link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), host == "docs.google.com" else { return nil }
        let parts = url.pathComponents
        guard let s = parts.firstIndex(of: "spreadsheets"), parts.count > s + 2, parts[s + 1] == "d" else { return nil }
        if parts[s + 2] == "e", parts.count > s + 3 {
            // File › Share › Publish to web.
            return URL(string: "https://docs.google.com/spreadsheets/d/e/\(parts[s + 3])/pub?output=xlsx")
        }
        let id = parts[s + 2]
        guard id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return URL(string: "https://docs.google.com/spreadsheets/d/\(id)/export?format=xlsx")
    }

    enum FetchError: LocalizedError {
        case notALink
        case notShared
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notALink: "That isn't a Google Sheets link."
            case .notShared: "Google asked for a sign-in. In Sheets, choose Share › General access › Anyone with the link, then try again — or download the sheet as .xlsx and import the file."
            case .failed(let why): "The sheet couldn't be downloaded: \(why)"
            }
        }
    }

    /// The workbook's bytes and the name Google gives it.
    static func fetch(_ link: String, session: URLSession = .shared) async throws -> (data: Data, name: String) {
        guard let url = exportURL(for: link) else { throw FetchError.notALink }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw FetchError.failed(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        guard data.starts(with: [0x50, 0x4B]) else {
            if let code = http?.statusCode, code >= 400, code != 401, code != 403 {
                throw FetchError.failed("Google answered \(code)")
            }
            throw FetchError.notShared
        }
        return (data, filename(from: http?.value(forHTTPHeaderField: "Content-Disposition")) ?? "Sheet")
    }

    /// `test scene` from `attachment; filename="testscene.xlsx"; filename*=UTF-8''test%20scene.xlsx`.
    static func filename(from disposition: String?) -> String? {
        guard let disposition else { return nil }
        var plain: String?, encoded: String?
        for part in disposition.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.lowercased().hasPrefix("filename*=") {
                let value = part.dropFirst("filename*=".count)
                encoded = value.components(separatedBy: "''").last?.removingPercentEncoding
            } else if part.lowercased().hasPrefix("filename=") {
                plain = String(part.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        guard let name = encoded ?? plain, !name.isEmpty else { return nil }
        return (name as NSString).deletingPathExtension
    }
}
