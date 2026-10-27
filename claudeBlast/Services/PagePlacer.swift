// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PagePlacer.swift
//  claudeBlast
//
//  The page scheme (iPad 12 × 5), and laying a page's words into it.
//
//        c1    c2    c3    c4    c5    c6    c7    c8    c9    c10  │ c11   c12
//  r1    HOME  ─────────── blue system row ───────────  ·     │  ·     ⌨
//  r2    I     ·     ·     ·     go→   ·     ·     ·     ·     more │  L1    don't
//  r3    ·     ·     ·     ·     want  ·     ·     ·     ·     ·    │  L2    stop
//  r4    you   ·     ·     help  ·     ·     ·     ·     ·     ·    │  L3    not
//  r5    yes   done  no    ·     ·     ·     ·     ·     ·     ·    │  L4    L5
//
//  - Row 1 is Home and BlasterAI 60's folders, as `<system>:` links, so a
//    scene opens the core board's own pages (see `TileToken.systemPrefix`).
//    The keyboard is pinned to column 12, with a gap before it.
//  - A scene's home page keeps the core words where BlasterAI 60 has them —
//    a child who knows where "want" is finds it in the same place on every
//    board — and the don't / stop / not cluster in column 12. A frame word
//    that is a doorway there ("go" → Places, "I" → the I page) is one here too.
//  - The page's own links fill L1–L4, then L5; a sixth takes `not`, a seventh
//    `don't`. `stop` is never displaced.
//  - Words fill columns 1–10, top to bottom, in Fitzgerald bands left to
//    right: pronouns, people, actions, describing, social, things. A scene's
//    home has 31 free cells there and the budget is 25, so adding a page never
//    moves a word.
//  - A leaf page has the system row and no frame; its links take column 12,
//    then 11, and its bands start fresh columns with a gap when there is room.
//
//  The shape — grid, frame words, cluster, link slots, band order — is
//  `Resources/page_templates.json`. The frame's cells come from BlasterAI 60's
//  home at run time, so when the core board moves a word every new scene
//  follows it.
//  Prototype: `tools/eval/build_layouts.py`.
//

import Foundation

/// The page scheme as data: `Resources/page_templates.json`. Grid size, the
/// frame words, the cluster, link slots and band order live there so a layout
/// experiment is an edit to one file. Cells are written as on the diagram
/// above — `"r2c11"` is row 2, column 11 — and stored as cell numbers.
struct PageScheme: Decodable {
    struct Template: Decodable {
        /// Core words the page keeps where BlasterAI 60 has them.
        var frame: [String]
        /// Frame words that also open a BlasterAI 60 page, beyond the doorways
        /// BlasterAI 60's home already gives them. Empty since `go` became a
        /// doorway there; kept so a layout experiment can add one.
        var frameLinks: [String: String]
        /// Column 12's don't / stop / not, read from BlasterAI 60 like the frame.
        var cluster: [String]
        /// Cluster words a link may take, in order, once the page is full.
        var displaceable: [String]
        /// Inclusive, 1-based: the columns words fill.
        var wordColumns: [Int]
        /// Where the page's own links go, in order.
        var linkSlots: [String]
        /// Each band starts a fresh column, with a gap when there is room.
        var spreadBands: Bool
    }

    var version: Int
    var designedFor: String
    var cols: Int
    var rows: Int
    var keyboard: String
    var bands: [String]
    var templates: [String: Template]

    /// The bundled scheme. A file that does not decode is a build mistake, and
    /// `PageSchemeTests` catches it before it ships.
    static let bundled: PageScheme = {
        do {
            guard let url = Bundle.main.url(forResource: "page_templates", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try load(Data(contentsOf: url))
        } catch {
            fatalError("page_templates.json: \(error)")
        }
    }()

    /// Decode and check: every cell on the grid, every band and kind known.
    static func load(_ data: Data) throws -> PageScheme {
        let scheme = try JSONDecoder().decode(PageScheme.self, from: data)
        try scheme.validate()
        return scheme
    }

    struct Invalid: Error, CustomStringConvertible { var description: String }

    func validate() throws {
        _ = try cell(keyboard)
        if bands.sorted() != PagePlacer.Band.allCases.map(\.rawValue).sorted() {
            throw Invalid(description: "bands must list each of \(PagePlacer.Band.allCases.map(\.rawValue)) once")
        }
        for kind in PageTemplate.Kind.allCases {
            guard let t = templates[kind.rawValue] else { throw Invalid(description: "no \(kind.rawValue) template") }
            for slot in t.linkSlots { _ = try cell(slot) }
            guard t.wordColumns.count == 2, 1 <= t.wordColumns[0], t.wordColumns[0] <= t.wordColumns[1],
                  t.wordColumns[1] <= cols else {
                throw Invalid(description: "\(kind.rawValue): wordColumns must be [first, last] within 1…\(cols)")
            }
            for key in t.displaceable where !t.cluster.contains(key) {
                throw Invalid(description: "\(kind.rawValue): \(key) is displaceable but not in the cluster")
            }
        }
    }

    /// `"r2c11"` → its cell number (row-major from 0; Home is r1c1).
    func cell(_ name: String) throws -> Int {
        let parts = name.dropFirst().split(separator: "c")
        guard name.first == "r", parts.count == 2, let r = Int(parts[0]), let c = Int(parts[1]),
              (1...rows).contains(r), (1...cols).contains(c), r > 1 || c > 1 else {
            throw Invalid(description: "\(name) is not a cell on a \(rows) × \(cols) grid")
        }
        return (r - 1) * cols + (c - 1)
    }

    /// Every kind is checked by `validate`, so this never misses.
    func template(_ kind: PageTemplate.Kind) -> Template { templates[kind.rawValue]! }
}

enum PageTemplate {
    enum Kind: String, Codable, CaseIterable {
        /// A scene's home page: system row, core frame, cluster.
        case home
        /// Any other page: system row only.
        case leaf

        /// Core words the page already has, which the model is told to leave out.
        var frameKeys: [String] { PageTemplate.scheme.template(self).frame }
    }

    static let scheme = PageScheme.bundled

    static var cols: Int { scheme.cols }
    static var rows: Int { scheme.rows }
    /// The grid every templated page is laid out on.
    static var designedFor: String { scheme.designedFor }

    /// BlasterAI 60's level-1 words that are words on its home (eat, drink and
    /// play are folders there). `tools/eval/prompts.py` reads the same file.
    static var homeFrame: [String] { scheme.template(.home).frame }
    /// The keyboard's cell: the same place on every page.
    static var keyboardCell: Int { try! scheme.cell(scheme.keyboard) }

    static func cell(row: Int, col: Int) -> Int { row * cols + col }

    /// Where the page's own links go, in order, before any displacement.
    static func linkSlots(_ kind: Kind) -> [Int] {
        scheme.template(kind).linkSlots.map { try! scheme.cell($0) }
    }

    /// The columns words fill, 0-based.
    static func wordColumns(_ kind: Kind) -> ClosedRange<Int> {
        let c = scheme.template(kind).wordColumns
        return (c[0] - 1)...(c[1] - 1)
    }

    /// Cells words may take, in fill order: the word columns, top to bottom.
    static func wordCells(_ kind: Kind, excluding taken: Set<Int>) -> [Int] {
        wordColumns(kind).flatMap { col in (1..<rows).map { cell(row: $0, col: col) } }
            .filter { !taken.contains($0) }
    }

    /// Where a link goes once the link slots are full: any empty cell below
    /// row 1, rightmost column first so it sits near the link columns.
    static var spareLinkCells: [Int] {
        (0..<cols).reversed().flatMap { col in (1..<rows).map { cell(row: $0, col: col) } }
    }

    /// Most words a leaf page lays out: its word columns. A longer list (a big
    /// pack, every word of a class) stays a flat page the grid pages through.
    static var leafCapacity: Int { wordColumns(.leaf).count * (rows - 1) }

    /// The template `page` was laid out on, read from the page itself: a
    /// templated page opens with the system row, so cell 1 is a `<system>:`
    /// link. Nil for a flat page — BlasterAI 60's own, an older scene's, a
    /// pack page too long to place.
    static func kind(of page: PageSpec, homePageKey: String) -> Kind? {
        guard let first = page.tiles.first, TileToken.systemPageKey(first.link) != nil,
              !first.isAudible else { return nil }
        return page.key == homePageKey ? .home : .leaf
    }

    /// Whether `scene`'s pages are built on the scheme: its home page is.
    static func isTemplated(_ pages: [PageSpec], homePageKey: String) -> Bool {
        pages.first { $0.key == homePageKey }.flatMap { kind(of: $0, homePageKey: homePageKey) } == .home
    }
}

/// What a templated page takes from BlasterAI 60's home.
struct PageFrame {
    /// Row 1 after Home: the core board's silent folders, as `<system>:`
    /// links. Its audible links (eat, drink, play) are words that also open a
    /// page, and belong in the word area, not here.
    var systemRow: [TileEntry]
    /// Cell → row-1 entry: the folders from cell 1 on, the keyboard in the
    /// last column so it is in the same place on every page.
    var rowOne: [Int: TileEntry] {
        var cells: [Int: TileEntry] = [:]
        var next = 1
        for entry in systemRow {
            if TileToken.systemPageKey(entry.link) == "keyboard" {
                cells[PageTemplate.keyboardCell] = entry
            } else {
                cells[next] = entry
                next += 1
            }
        }
        return cells
    }
    /// Cell → core word, for the home template's frame and cluster.
    var fixed: [Int: TileEntry]

    init(systemHome: PageSpec?, kind: PageTemplate.Kind) {
        let tiles = systemHome?.tiles ?? []
        systemRow = tiles
            .filter { !$0.link.isEmpty && !$0.isAudible && !$0.isSpacer }
            .prefix(PageTemplate.cols - 1)
            .map { entry in
                var link = TileEntry(key: entry.key, link: TileToken.systemLink(to: entry.link),
                                     isAudible: false, linkColor: entry.linkColor,
                                     linkColorIsAuto: false)
                link.revealLevel = entry.revealLevel
                return link
            }
        fixed = [:]
        let template = PageTemplate.scheme.template(kind)
        let wanted = Set(template.frame + template.cluster)
        guard !wanted.isEmpty else { return }
        // List index i is cell i + 1: Home is cell 0 and not in the list.
        // Both keep BlasterAI 60's levels, so the chrome grows the way the
        // core board does; a scene that wants none turns levels off.
        //
        // A frame word that is a doorway on BlasterAI 60 (`go` → Places, `I` →
        // the I page) stays one here, opening the core board's page: a doorway
        // belongs to the word, so it works on every board the word is on. This
        // used to skip any frame word with a link, which was right while only
        // folders had them and would have dropped `go` and `I` from every new
        // scene once they became doorways.
        for (index, entry) in tiles.enumerated()
        where wanted.contains(entry.key) && (entry.link.isEmpty || entry.isAudible)
            && index + 1 > PageTemplate.cols - 1 {
            let opens = entry.link.isEmpty ? template.frameLinks[entry.key] : entry.link
            var word = opens.map {
                TileEntry(key: entry.key, link: TileToken.systemLink(to: $0), isAudible: true,
                          linkColor: entry.linkColor ?? "verb", linkColorIsAuto: false)
            } ?? TileEntry(key: entry.key, link: "", isAudible: true)
            word.revealLevel = entry.revealLevel
            fixed[index + 1] = word
        }
    }

    /// Keys the page already has, which its words must not repeat.
    var keys: Set<String> { Set(systemRow.map(\.key) + fixed.values.map(\.key)) }
}

enum PagePlacer {
    /// Fitzgerald bands; their left-to-right order is the scheme's `bands`.
    enum Band: String, CaseIterable {
        case pronoun, people, verb, adjective, social, noun

        var order: Int { PageTemplate.scheme.bands.firstIndex(of: rawValue) ?? 0 }
    }

    static func band(_ pos: PartOfSpeech, wordClass: String?) -> Band {
        switch pos {
        case .pronoun: return .pronoun
        case .verb: return .verb
        case .adjective, .preposition, .determiner, .conjunction: return .adjective
        case .social, .interjection, .question, .negation: return .social
        case .noun: return wordClass == "people" ? .people : .noun
        }
    }

    /// Lay `words` (rank order) and `links` into one page of the scheme.
    ///
    /// Returns the page's entries for cells 1…59 — Home is cell 0 and is drawn
    /// by the board — with `TileEntry.spacer()` in every empty cell before the
    /// last placed one, so each word sits in its cell.
    static func place(words: [GeneratedTile], links: [GeneratedTile],
                      kind: PageTemplate.Kind, frame: PageFrame,
                      lookup: [String: TileModel]) -> [TileEntry] {
        var grid: [Int: TileEntry] = frame.fixed
        grid.merge(frame.rowOne) { _, row in row }

        // Links take the template's slots first; any more wait for the words.
        var pendingLinks = links[...]
        for slot in PageTemplate.linkSlots(kind) {
            guard let link = pendingLinks.popFirst() else { break }
            grid[slot] = entry(link)
        }

        // Words, grouped into bands; a stable sort keeps the model's rank.
        let ordered = words.enumerated().sorted { a, b in
            let ba = band(of: a.element, lookup: lookup), bb = band(of: b.element, lookup: lookup)
            return ba != bb ? ba.order < bb.order : a.offset < b.offset
        }.map(\.element)
        let cells = PageTemplate.scheme.template(kind).spreadBands
            ? spread(ordered, kind: kind, taken: Set(grid.keys), lookup: lookup)
            : Array(PageTemplate.wordCells(kind, excluding: Set(grid.keys)).prefix(ordered.count))
        for (cell, word) in zip(cells, ordered) { grid[cell] = entry(word) }
        // Words past the word area take whatever cells are left in columns
        // 11–12 rather than vanish. The budget keeps this from happening.
        if ordered.count > cells.count {
            let rest = (1..<PageTemplate.rows * PageTemplate.cols).filter { grid[$0] == nil }
            for (cell, word) in zip(rest, ordered.dropFirst(cells.count)) { grid[cell] = entry(word) }
        }

        // Links past the slots: an empty cell, then (on a scene's home) not's
        // cell, then don't's. A core word goes only when the page is full.
        var spare = PageTemplate.spareLinkCells.filter { grid[$0] == nil }
        spare += PageTemplate.scheme.template(kind).displaceable.compactMap { key in
            frame.fixed.first { $0.value.key == key }?.key
        }
        for cell in spare {
            guard let link = pendingLinks.popFirst() else { break }
            grid[cell] = entry(link)
        }
        // A link is never lost: with no cell left it starts a second screen.
        let overflow = pendingLinks.map { entry($0) }

        guard let last = grid.keys.max() else { return overflow }
        return (1...last).map { grid[$0] ?? .spacer() } + overflow
    }

    /// Add `link` to a page already laid out on `kind`, the way `place` would
    /// have: the first free link slot, then any empty cell below row 1, then
    /// (on a scene's home) `not`'s cell, then `don't`'s. Only a full page sends
    /// it to the end, onto a second screen, so a link is never lost. `tiles` is
    /// cells 1…n, as `place` returns them.
    static func insertLink(_ link: TileEntry, into tiles: [TileEntry],
                           kind: PageTemplate.Kind) -> [TileEntry] {
        var cells = tiles
        let isFree = { (cell: Int) in cell > cells.count || cells[cell - 1].isSpacer }
        var target = PageTemplate.linkSlots(kind).first(where: isFree)
            ?? PageTemplate.spareLinkCells.first(where: isFree)
        if target == nil {
            target = PageTemplate.scheme.template(kind).displaceable.lazy.compactMap { key in
                cells.indices.first {
                    cells[$0].key == key && cells[$0].link.isEmpty
                        && ($0 + 1) % PageTemplate.cols == PageTemplate.cols - 1
                }.map { $0 + 1 }
            }.first
        }
        guard let cell = target else { return cells + [link] }
        if cell > cells.count {
            cells += Array(repeating: TileEntry.spacer(), count: cell - cells.count)
        }
        cells[cell - 1] = link
        return cells
    }

    /// A leaf page has no frame, so its bands can breathe: each band starts a
    /// new column, with an empty column between bands when the page has room.
    /// Falls back to plain column fill when even gap-free columns don't fit.
    static func spread(_ words: [GeneratedTile], kind: PageTemplate.Kind, taken: Set<Int>,
                       lookup: [String: TileModel]) -> [Int] {
        let columns = PageTemplate.wordColumns(kind)
        let groups = Band.allCases.sorted { $0.order < $1.order }.map { b in words.filter { band(of: $0, lookup: lookup) == b } }
            .filter { !$0.isEmpty }
        let free = { (col: Int) in
            (1..<PageTemplate.rows).map { PageTemplate.cell(row: $0, col: col) }.filter { !taken.contains($0) }
        }
        for gap in [1, 0] {
            var cells: [Int] = []
            var col = columns.lowerBound
            var fits = true
            for (n, group) in groups.enumerated() {
                var remaining = group.count
                while remaining > 0 {
                    guard col <= columns.upperBound else { fits = false; break }
                    let column = free(col)
                    let used = min(remaining, column.count)
                    cells += column.prefix(used)
                    remaining -= used
                    if remaining > 0 { col += 1 }
                }
                guard fits else { break }
                if n < groups.count - 1 { col += 1 + gap }
            }
            if fits { return cells }
        }
        return Array(PageTemplate.wordCells(kind, excluding: taken).prefix(words.count))
    }

    private static func band(of tile: GeneratedTile, lookup: [String: TileModel]) -> Band {
        let wordClass = lookup[tile.key]?.wordClass ?? tile.wordClass
        return band(TopicWordMatcher.partOfSpeech(of: tile, lookup: lookup), wordClass: wordClass)
    }

    private static func entry(_ tile: GeneratedTile) -> TileEntry {
        TileEntry(key: tile.key, link: tile.link, isAudible: tile.isAudible,
                  linkColor: tile.linkColor, linkColorIsAuto: tile.linkColor == nil)
    }
}
