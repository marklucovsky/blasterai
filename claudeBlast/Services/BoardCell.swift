// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardCell.swift
//  claudeBlast
//
//  The text of one board cell, for the spreadsheet editor and CSV boards.
//

import Foundation
import SwiftData

/// One cell of a board, written as text: `[word] [> page]`.
///
/// The left side is the word the cell says; the right side is the page it
/// opens.
///
/// | Cell                     | Meaning                                         |
/// |--------------------------|-------------------------------------------------|
/// | *(empty)*                | a gap                                           |
/// | `cat`                    | an existing word                                |
/// | `cat, animal[, Display]` | a new word of that class (`BulkWordParser`)     |
/// | `go > places`            | says *go*, then opens this scene's Places       |
/// | `> animals`              | a silent folder that opens Animals              |
/// | `go > sys:places`        | opens BlasterAI 60's Places                     |
/// | `[family] > people`      | a folder showing Family's picture, not People's cover |
///
/// A bare page name is always the scene's own: one not made yet becomes an
/// empty page, so a board can link forward to a page written later. BlasterAI
/// 60's pages are reached only with `sys:` — the same text means the same page
/// in the grid, a spreadsheet and an export.
///
/// ## Why a board is a spreadsheet
///
/// A page is a fixed grid whose positions a child learns, so a cell is an
/// address, not a slot in a list that reflows (see `PageCells`). With an
/// address per word, a page can be typed cell by cell, and a board can come
/// in from the spreadsheet a therapist already drew it in.
///
/// Parsing is pure: what a word or page *is* depends on the vocabulary and the
/// scene, which `resolve` takes as arguments.
enum BoardCell {

    /// The text after `>` that names BlasterAI 60's page rather than the
    /// scene's own.
    static let systemMarker = "sys:"

    /// The left side of a cell.
    enum Word: Equatable {
        /// A word already in the vocabulary, as typed.
        case existing(String)
        /// A new word: `key, class[, Display]`.
        case new(BulkWordParser.Word)
    }

    /// The right side of a cell, as typed.
    struct Link: Equatable {
        var page: String
        /// `sys:` was written.
        var isSystem: Bool
        /// `[word] > page`: a folder showing this word's picture rather than
        /// the page's cover.
        var picture: String? = nil
    }

    enum Parsed: Equatable {
        case spacer
        case cell(word: Word?, link: Link?)
        case invalid(String)
    }

    /// Reads a cell. Says nothing about whether the word or page exists.
    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .spacer }

        let lhs: Substring
        var link: Link?
        if let arrow = trimmed.firstIndex(of: ">") {
            lhs = trimmed[..<arrow]
            var page = trimmed[trimmed.index(after: arrow)...].trimmingCharacters(in: .whitespaces)
            var isSystem = false
            if page.lowercased().hasPrefix(systemMarker) {
                isSystem = true
                page = String(page.dropFirst(systemMarker.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !page.isEmpty else { return .invalid("Name a page after >") }
            link = Link(page: page, isSystem: isSystem)
        } else {
            lhs = Substring(trimmed)
        }

        var wordText = lhs.trimmingCharacters(in: .whitespaces)
        if wordText.hasPrefix("["), wordText.hasSuffix("]") {
            let picture = wordText.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            guard link != nil else { return .invalid("[picture] is for a folder: [word] > page") }
            guard !picture.isEmpty else { return .invalid("Name a word's picture inside [ ]") }
            link?.picture = picture
            wordText = ""
        }
        guard !wordText.isEmpty else {
            return link == nil ? .spacer : .cell(word: nil, link: link)
        }
        if wordText.contains(",") {
            guard let word = BulkWordParser.parse(wordText).words.first else {
                return .invalid("A new word needs a class: word, class")
            }
            return .cell(word: .new(word), link: link)
        }
        return .cell(word: .existing(wordText), link: link)
    }

    // MARK: - Resolution

    /// What committing a cell does: the placement, and anything that has to
    /// exist first.
    struct Plan: Equatable {
        var entry: TileEntry
        /// A word to create before placing `entry`. Its final key comes from
        /// `WordCreator`, which may add a homograph suffix.
        var newWord: BulkWordParser.Word?
        /// A page of the scene to create, by key.
        var newPage: String?
        /// A page-link tile to mint for a silent folder, by page key.
        var folderFor: String?
    }

    enum Resolution: Equatable {
        case plan(Plan)
        case error(String)
    }

    /// Where a page name lands: the scene's own page, BlasterAI 60's, or a new
    /// page of the scene.
    enum Target: Equatable {
        case scene(String)
        case system(String)
        case newPage(String)

        /// The link a `TileEntry` stores.
        var link: String {
            switch self {
            case .scene(let key), .newPage(let key): key
            case .system(let key): TileToken.systemLink(to: key)
            }
        }
    }

    /// The scene's page, else a new page of the scene; with `sys:`, BlasterAI
    /// 60's page or nothing. Matched by key or by title.
    static func target(_ link: Link, scenePages: [PageSpec],
                       systemPages: [PageSpec]) -> Target? {
        if link.page == TileToken.home { return .scene(TileToken.home) }
        let key = pageKey(link.page)
        guard !key.isEmpty else { return nil }
        if link.isSystem {
            return match(link.page, key: key, in: systemPages).map { .system($0.key) }
        }
        if let page = match(link.page, key: key, in: scenePages) { return .scene(page.key) }
        return .newPage(key)
    }

    /// Turns a parsed cell into a placement.
    ///
    /// - Parameters:
    ///   - lookup: every word, by key.
    ///   - scenePages: the scene being edited.
    ///   - systemPages: BlasterAI 60's pages; empty when editing it.
    static func resolve(_ parsed: Parsed, lookup: [String: TileModel],
                        scenePages: [PageSpec], systemPages: [PageSpec]) -> Resolution {
        switch parsed {
        case .spacer:
            return .plan(Plan(entry: .spacer()))
        case .invalid(let reason):
            return .error(reason)
        case .cell(let word, let link):
            var target: Target?
            if let link {
                guard let found = Self.target(link, scenePages: scenePages, systemPages: systemPages) else {
                    return .error("BlasterAI 60 has no page \u{201C}\(link.page)\u{201D}")
                }
                target = found
            }
            var plan = Plan(entry: TileEntry(key: "", link: target?.link ?? ""))
            if case .newPage(let key) = target { plan.newPage = key }

            switch word {
            case nil:
                guard let target else { return .plan(Plan(entry: .spacer())) }
                plan.entry.isAudible = false
                if let picture = link?.picture {
                    // Any tile's picture, folders and covers included, by key
                    // first and then by name.
                    let key = TileModel.normalizeKey(picture)
                    if lookup[key] != nil {
                        plan.entry.key = key
                    } else if case .found(let found) = existingWord(picture, lookup: lookup) {
                        plan.entry.key = found
                    } else {
                        return .error("No word \u{201C}\(picture)\u{201D} for the folder's picture")
                    }
                } else {
                    let pageKey = target.link == TileToken.home ? "home" : key(of: target)
                    plan.entry.key = folderKey(for: target, scenePages: scenePages, systemPages: systemPages)
                        ?? PageLink.key(forPage: pageKey)
                    // A page whose cover is still its own page-link tile, not
                    // yet made: make it.
                    if plan.entry.key == PageLink.key(forPage: pageKey), lookup[plan.entry.key] == nil {
                        plan.folderFor = pageKey
                    }
                }
            case .existing(let text):
                switch existingWord(text, lookup: lookup) {
                case .found(let key): plan.entry.key = key
                case .missing:
                    return .error("No word \u{201C}\(text)\u{201D}. Add a class to make one: \(text), class")
                case .ambiguous(let keys):
                    return .error("\u{201C}\(text)\u{201D} could be \(keys.joined(separator: ", "))")
                }
            case .new(let new):
                let key = TileModel.normalizeKey(new.key)
                if let tile = lookup[key], tile.wordClass == new.wordClass {
                    plan.entry.key = key
                } else {
                    plan.newWord = new
                    plan.entry.key = key
                }
            }
            return .plan(plan)
        }
    }

    private static func key(of target: Target) -> String {
        switch target {
        case .scene(let key), .system(let key), .newPage(let key): key
        }
    }

    enum WordMatch: Equatable {
        case found(String)
        case missing
        case ambiguous([String])
    }

    /// A typed word: its key exactly, else the one word whose label says it.
    static func existingWord(_ text: String, lookup: [String: TileModel]) -> WordMatch {
        let key = TileModel.normalizeKey(text)
        if lookup[key] != nil { return .found(key) }
        let wanted = WordFinder.normalize(text)
        let keys = lookup.values
            .filter { WordFinder.normalize($0.displayName) == wanted || WordFinder.normalize($0.value) == wanted }
            .map(\.key)
            .filter { PageLink.targetPage(forKey: $0) == nil }
            .sorted()
        switch keys.count {
        case 0: return .missing
        case 1: return .found(keys[0])
        default: return .ambiguous(keys)
        }
    }

    /// The silent folder already used for a page, so a typed `> places_house`
    /// gets the House folder's own picture rather than a new page-link tile.
    /// Looked for on the system row first — People and Questions are folders
    /// only there, inherited and never stored on a page — then on the pages
    /// the link belongs to.
    ///
    /// - Parameter systemRow: the row's folders as (word, page). A `.scene`
    ///   target uses it only when editing BlasterAI 60 itself (`systemPages`
    ///   empty): another scene's own `people` page is not the core board's.
    static func folderKey(for target: Target, scenePages: [PageSpec],
                          systemPages: [PageSpec],
                          systemRow: [(key: String, page: String)] = BoardCell.systemRowFolders) -> String? {
        let pages: [PageSpec]
        let link: String
        switch target {
        case .newPage: return nil
        case .scene(let key): pages = scenePages; link = key
        case .system(let key): pages = systemPages; link = key
        }
        let isCoreBoardPage: Bool = switch target {
        case .system: true
        case .scene: systemPages.isEmpty
        case .newPage: false
        }
        // The page's cover — chosen, else its default (`PageCover`).
        if let page = pages.first(where: { $0.key == link }) {
            return PageCover.key(of: page, in: pages, isSystemScene: isCoreBoardPage, systemRow: systemRow)
        }
        if isCoreBoardPage, let folder = systemRow.first(where: { $0.page == link }) {
            return folder.key
        }
        // A folder on a scene page that opens a system page BlasterAI 60's
        // pages were not passed for.
        if case .system = target {
            for page in scenePages {
                if let entry = page.tiles.first(where: { !$0.isAudible && $0.link == target.link }) {
                    return entry.key
                }
            }
        }
        return nil
    }

    /// The system row's folders, from `page_templates.json`.
    static var systemRowFolders: [(key: String, page: String)] {
        PageTemplate.scheme.systemRow.map { ($0.key, $0.page) }
    }

    /// A page name as a page key: `Fun Places` → `fun_places`.
    static func pageKey(_ name: String) -> String {
        TileModel.normalizeKey(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func match(_ name: String, key: String, in pages: [PageSpec]) -> PageSpec? {
        if let page = pages.first(where: { $0.key == key }) { return page }
        let wanted = WordFinder.normalize(name)
        return pages.first { WordFinder.normalize($0.title) == wanted }
    }

    // MARK: - Formatting

    /// The text of a placed cell, which `parse` reads back as the same
    /// placement.
    ///
    /// A silent folder writes only its page: its key is the folder's picture,
    /// which `folderKey` finds again.
    static func format(_ entry: TileEntry, cover: (TileEntry) -> String? = { _ in nil }) -> String {
        if entry.isSpacer { return "" }
        var word = entry.isAudible || entry.link.isEmpty ? entry.key : ""
        guard !entry.link.isEmpty else { return word }
        // A folder showing something other than its page's cover says so.
        if word.isEmpty, entry.link != TileToken.home, let cover = cover(entry), cover != entry.key {
            word = "[\(entry.key)]"
        }
        let page: String
        if entry.link == TileToken.home {
            page = TileToken.home
        } else if let system = TileToken.systemPageKey(entry.link) {
            page = systemMarker + system
        } else {
            page = entry.link
        }
        return word.isEmpty ? "> \(page)" : "\(word) > \(page)"
    }
}

extension BoardCell {
    /// The cover of the page a link opens, for `format`: a scene page's from
    /// `scenePages`, a BlasterAI 60 page's from `systemPages`.
    static func covers(scenePages: [PageSpec], systemPages: [PageSpec],
                       isSystemScene: Bool = false) -> (TileEntry) -> String? {
        { entry in
            if let system = TileToken.systemPageKey(entry.link) {
                guard let page = systemPages.first(where: { $0.key == system }) else { return nil }
                return PageCover.key(of: page, in: systemPages, isSystemScene: true)
            }
            guard let page = scenePages.first(where: { $0.key == entry.link }) else { return nil }
            return PageCover.key(of: page, in: scenePages, isSystemScene: isSystemScene || systemPages.isEmpty)
        }
    }

    /// Carries out `plan` in `scene`: creates the word, the page and the
    /// folder tile it needs, and returns the placement for the cell.
    ///
    /// `replacing` is what the cell held. Typing the same word and link back
    /// keeps it whole — its level, conceal and colour are the caregiver's, and
    /// the text of a cell does not carry them. The same word with a new link
    /// keeps all but the colour, which re-resolves.
    ///
    /// A link's colour is resolved here, as every link's is when it is made
    /// (`SceneLinkColors`): stored nil, it draws as wayfinding blue, and the
    /// scene's refresh never revisits a link into BlasterAI 60.
    @MainActor
    static func commit(_ plan: Plan, replacing old: TileEntry?, in scene: BlasterScene,
                       systemPages: [PageSpec] = [],
                       lookup: [String: TileModel], context: ModelContext) -> TileEntry {
        var entry = plan.entry
        if let word = plan.newWord {
            var keys = Set(lookup.keys)
            if let tile = WordCreator.findOrCreate(word, existing: Array(lookup.values),
                                                   keys: &keys, context: context) {
                entry.key = tile.key
            }
        }
        if let key = plan.newPage, !scene.pages.contains(where: { $0.key == key }) {
            var pages = scene.pages
            pages.append(PageSpec(key: key, tiles: []))
            scene.pages = pages
            PageLink.mint(pageKey: key, displayName: PageNaming.displayName(key),
                          context: context, existing: lookup)
        }
        if let key = plan.folderFor {
            PageLink.mint(pageKey: key, displayName: PageNaming.displayName(key),
                          context: context, existing: lookup)
        }
        try? context.save()

        if let old, !old.isSpacer, old.key == entry.key,
           old.link == entry.link, old.isAudible == entry.isAudible {
            return old
        }
        if !entry.link.isEmpty, entry.link != TileToken.home {
            let system = TileToken.systemPageKey(entry.link)
            entry.linkColor = SceneLinkColors.slot(
                forLinkTo: system ?? entry.link,
                spokenAs: entry.key,
                isAudible: entry.isAudible,
                in: system == nil ? scene.pages : systemPages,
                vocabulary: Array(lookup.keys) + (plan.newWord == nil ? [] : [entry.key]),
                partOfSpeech: { PartOfSpeechIndex.partOfSpeech(for: $0) }).rawValue
        }
        guard let old, !old.isSpacer, old.key == entry.key else { return entry }
        entry.isConcealed = old.isConcealed
        entry.revealLevel = old.revealLevel
        entry.label = old.label
        return entry
    }
}

/// A page's tiles as cells of its board grid.
///
/// A page is stored as a list, laid out row by row and screen by screen:
/// `TileGridEditor` and the child's board both chunk it into screens of
/// `perScreen` cells. So the cell at screen s, row r, column c is entry
/// `s * perScreen + r * cols + c`, and a gap is a spacer that holds its place.
struct PageCells: Equatable {
    let cols: Int
    /// Rows of words on a screen: the grid's rows, less the inherited system
    /// row.
    let rows: Int

    init(grid: (cols: Int, rows: Int), inheritsChrome: Bool) {
        cols = max(1, grid.cols)
        rows = max(1, grid.rows - (inheritsChrome ? 1 : 0))
    }

    var perScreen: Int { cols * rows }

    struct Cell: Hashable {
        var screen: Int
        var row: Int
        var col: Int
    }

    func index(of cell: Cell) -> Int {
        cell.screen * perScreen + cell.row * cols + cell.col
    }

    func cell(at index: Int) -> Cell {
        let within = index % perScreen
        return Cell(screen: index / perScreen, row: within / cols, col: within % cols)
    }

    /// Screens the page fills; at least one, so an empty page has cells.
    func screenCount(_ tiles: [TileEntry]) -> Int {
        max(1, (tiles.count + perScreen - 1) / perScreen)
    }

    /// The placement in a cell; nil for a gap or a cell past the end.
    func entry(at index: Int, in tiles: [TileEntry]) -> TileEntry? {
        guard index >= 0, index < tiles.count, !tiles[index].isSpacer else { return nil }
        return tiles[index]
    }

    /// `tiles` with `entry` in the cell at `index`; nil empties it.
    ///
    /// A cell past the end pads with gaps to reach it. Trailing gaps are
    /// dropped, so emptying the last word does not leave a page of air.
    func setting(_ entry: TileEntry?, at index: Int, in tiles: [TileEntry]) -> [TileEntry] {
        guard index >= 0 else { return tiles }
        var result = tiles
        while result.count <= index { result.append(.spacer()) }
        result[index] = entry ?? .spacer()
        while let last = result.last, last.isSpacer { result.removeLast() }
        return result
    }

    /// The cell `by` steps from `cell`, kept on the grid: across a row's end
    /// to the next row, down past a screen's last row onto the next screen.
    /// A move off the first cell or past `screens` screens stays put.
    func moving(_ cell: Cell, rowBy dRow: Int = 0, colBy dCol: Int = 0, screens: Int) -> Cell {
        var row = cell.screen * rows + cell.row + dRow
        var col = cell.col + dCol
        if col >= cols { col = 0; row += 1 }
        if col < 0 { col = cols - 1; row -= 1 }
        guard row >= 0, row < screens * rows else { return cell }
        return Cell(screen: row / rows, row: row % rows, col: col)
    }

    // MARK: - Moving cells

    /// A cell's row counted down through every screen. Screens stack, so the
    /// index is simply `absoluteRow * cols + col`: a block can be dragged across
    /// a screen break and keep its shape.
    func absoluteRow(_ index: Int) -> Int { index / cols }
    func column(_ index: Int) -> Int { index % cols }

    enum MoveError: Error, Equatable {
        /// Part of the block would land off the grid's sides or above its top.
        case offGrid
        /// These cells are filled and are not part of what is moving.
        case occupied([Int])
    }

    /// `tiles` with the cells at `sources` moved so that `anchor` lands on
    /// `target`, every other source keeping its offset from the anchor.
    ///
    /// **Nothing else moves.** A source leaves a gap behind it. One cell
    /// dropped on a filled cell swaps with it; a block may land only where
    /// every cell it covers is empty or part of the block itself, and
    /// otherwise the move is refused with the cells in the way — overwriting
    /// a word a child has learned the place of is never a side effect of a
    /// drag.
    func moving(_ sources: Set<Int>, anchor: Int, to target: Int,
                in tiles: [TileEntry]) -> Result<[TileEntry], MoveError> {
        let dRow = absoluteRow(target) - absoluteRow(anchor)
        let dCol = column(target) - column(anchor)
        guard dRow != 0 || dCol != 0 else { return .success(tiles) }

        var destination: [Int: Int] = [:]          // source → destination
        for source in sources {
            let row = absoluteRow(source) + dRow, col = column(source) + dCol
            guard row >= 0, col >= 0, col < cols else { return .failure(.offGrid) }
            destination[source] = row * cols + col
        }

        if sources.count == 1, let source = sources.first, let dest = destination[source],
           let other = entry(at: dest, in: tiles) {
            // A swap: each takes the other's cell.
            var result = setting(other, at: source, in: tiles)
            result = setting(entry(at: source, in: tiles), at: dest, in: result)
            return .success(result)
        }

        let blocked = destination.values
            .filter { !sources.contains($0) && entry(at: $0, in: tiles) != nil }
            .sorted()
        guard blocked.isEmpty else { return .failure(.occupied(blocked)) }

        let moving = sources.map { ($0, entry(at: $0, in: tiles)) }
        var result = tiles
        for (source, _) in moving { result = setting(nil, at: source, in: result) }
        for (source, entry) in moving where entry != nil {
            result = setting(entry, at: destination[source]!, in: result)
        }
        return .success(result)
    }

    /// `tiles` with `entries` put in front of the cell at `target`, the cells
    /// from there shifting along in reading order until a gap takes them.
    ///
    /// **The reflow eats one gap and stops.** A board's gaps are what hold its
    /// clusters apart — Avaz's 4 · gap · 4 — so a word inserted into a cluster
    /// pushes that cluster's words along into the gap after it and leaves the
    /// next cluster where it was. Only a run with no gap before the end of the
    /// page pushes its last word onto the end. Several entries shift by as many
    /// cells and use up as many gaps.
    ///
    /// `sources`, when the entries come from this page, are emptied first, so
    /// a word moved forward within its own run leaves the gap it needs.
    func inserting(_ entries: [TileEntry], before target: Int, removing sources: Set<Int> = [],
                   in tiles: [TileEntry]) -> [TileEntry] {
        var result = sources.reduce(tiles) { setting(nil, at: $1, in: $0) }
        var carry = entries
        var index = max(0, target)
        while !carry.isEmpty {
            let displaced = entry(at: index, in: result)
            result = setting(carry.removeFirst(), at: index, in: result)
            if let displaced { carry.append(displaced) }
            index += 1
        }
        return result
    }

    /// `tiles` with `entries` placed into empty cells, the first at or after
    /// `start`, in reading order. Filled cells are stepped over, never moved.
    func placing(_ entries: [TileEntry], intoEmptyFrom start: Int,
                 in tiles: [TileEntry]) -> [TileEntry] {
        var result = tiles
        var index = max(0, start)
        for entry in entries {
            while self.entry(at: index, in: result) != nil { index += 1 }
            result = setting(entry, at: index, in: result)
            index += 1
        }
        return result
    }

    /// `tiles` with a rectangle of cells written over the grid from `target`,
    /// row by row, as a spreadsheet pastes: nil empties a cell. Columns past
    /// the grid's edge are dropped and counted.
    func pasting(_ rows: [[TileEntry?]], at target: Int,
                 in tiles: [TileEntry]) -> (tiles: [TileEntry], dropped: Int) {
        var result = tiles
        var dropped = 0
        let top = absoluteRow(target), left = column(target)
        for (r, row) in rows.enumerated() {
            for (c, entry) in row.enumerated() {
                guard left + c < cols else { dropped += 1; continue }
                result = setting(entry, at: (top + r) * cols + left + c, in: result)
            }
        }
        return (result, dropped)
    }

    /// The rectangle `selection` spans, as rows of indices top to bottom.
    func rectangle(_ selection: Set<Int>) -> [[Int]] {
        guard let first = selection.first else { return [] }
        var top = absoluteRow(first), bottom = top, left = column(first), right = left
        for index in selection {
            top = min(top, absoluteRow(index)); bottom = max(bottom, absoluteRow(index))
            left = min(left, column(index)); right = max(right, column(index))
        }
        return (top...bottom).map { row in (left...right).map { row * cols + $0 } }
    }

    /// Every cell in the rectangle between two cells.
    func span(from a: Int, to b: Int) -> Set<Int> {
        Set(rectangle([a, b]).joined())
    }
}

extension BoardCell {
    /// Cells as tab-separated text: a row per line, as Numbers, Excel and
    /// Sheets copy and paste them.
    static func tsv(_ rows: [[String]]) -> String {
        rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// Tab-separated text as rows of cell text. A trailing newline (which
    /// spreadsheets add) is not a row.
    static func rows(fromTSV text: String) -> [[String]] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        while lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines.map { $0.components(separatedBy: "\t") }
    }
}
