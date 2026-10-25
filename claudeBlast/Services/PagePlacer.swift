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
//    board — and the don't / stop / not cluster in column 12. "go" also
//    opens BlasterAI 60's Places, as eat opens Food (`frameLinks`).
//  - The page's own links fill L1–L4, then L5; a sixth takes `not`, a seventh
//    `don't`. `stop` is never displaced.
//  - Words fill columns 1–10, top to bottom, in Fitzgerald bands left to
//    right: pronouns, people, actions, describing, social, things. A scene's
//    home has 31 free cells there and the budget is 25, so adding a page never
//    moves a word.
//  - A leaf page has the system row and no frame; its links take column 12,
//    then 11, and its bands start fresh columns with a gap when there is room.
//
//  The cells come from BlasterAI 60's home at run time, not from a table here,
//  so when the core board moves a word every new scene follows it.
//  Prototype: `tools/eval/build_layouts.py`.
//

import Foundation

enum PageTemplate {
    enum Kind: String, Codable {
        /// A scene's home page: system row, core frame, cluster.
        case home
        /// Any other page: system row only.
        case leaf

        /// Core words the page already has, which the model is told to leave out.
        var frameKeys: [String] { self == .home ? PageTemplate.homeFrame : [] }
    }

    static let cols = 12
    static let rows = 5
    /// The grid every templated page is laid out on.
    static let designedFor = "ipad-12x5"

    /// BlasterAI 60's level-1 words that are words on its home (eat, drink and
    /// play are folders there). Mirrors `tools/eval/prompts.FRAMES["home"]`.
    static let homeFrame = ["i", "you", "want", "more", "go", "stop", "help", "yes", "no", "all_done"]
    /// Column 12, rows 2–4, in the order links displace them. `stop` is not
    /// here because it is never displaced: it is part of the frame.
    static let displaceable = ["not", "don't"]
    static let cluster = ["don't", "stop", "not"]
    /// Frame words that also open a BlasterAI 60 page, the way eat opens
    /// Food: "go" says go and shows the places to go.
    static let frameLinks = ["go": "places"]

    static func cell(row: Int, col: Int) -> Int { row * cols + col }

    /// Where the page's own links go, in order, before any displacement.
    static func linkSlots(_ kind: Kind) -> [Int] {
        switch kind {
        case .home:
            return (1..<rows).map { cell(row: $0, col: 10) } + [cell(row: 4, col: 11)]
        case .leaf:
            return (1..<rows).map { cell(row: $0, col: 11) } + (1..<rows).map { cell(row: $0, col: 10) }
        }
    }

    /// Cells words may take, in fill order: columns 1–10, top to bottom.
    static func wordCells(excluding taken: Set<Int>) -> [Int] {
        (0..<10).flatMap { col in (1..<rows).map { cell(row: $0, col: col) } }
            .filter { !taken.contains($0) }
    }

    /// Where a link goes once the link slots are full: any empty cell below
    /// row 1, rightmost column first so it sits near the link columns.
    static let spareLinkCells: [Int] = (0..<cols).reversed().flatMap { col in
        (1..<rows).map { cell(row: $0, col: col) }
    }

    /// Most words a leaf page lays out: columns 1–10. A longer list (a big
    /// pack, every word of a class) stays a flat page the grid pages through.
    static let leafCapacity = 10 * (rows - 1)

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
                cells[PageTemplate.cols - 1] = entry
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
                link.revealLevel = 0
                return link
            }
        fixed = [:]
        guard kind == .home else { return }
        let wanted = Set(PageTemplate.homeFrame + PageTemplate.cluster)
        // List index i is cell i + 1: Home is cell 0 and not in the list.
        for (index, entry) in tiles.enumerated()
        where wanted.contains(entry.key) && entry.link.isEmpty && index + 1 > PageTemplate.cols - 1 {
            fixed[index + 1] = PageTemplate.frameLinks[entry.key].map {
                TileEntry(key: entry.key, link: TileToken.systemLink(to: $0), isAudible: true,
                          linkColor: "verb", linkColorIsAuto: false)
            } ?? TileEntry(key: entry.key, link: "", isAudible: true)
        }
    }

    /// Keys the page already has, which its words must not repeat.
    var keys: Set<String> { Set(systemRow.map(\.key) + fixed.values.map(\.key)) }
}

enum PagePlacer {
    /// Fitzgerald bands, left to right.
    enum Band: Int, CaseIterable { case pronoun, people, verb, adjective, social, noun }

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
            return ba != bb ? ba.rawValue < bb.rawValue : a.offset < b.offset
        }.map(\.element)
        let cells = kind == .leaf
            ? spread(ordered, taken: Set(grid.keys), lookup: lookup)
            : Array(PageTemplate.wordCells(excluding: Set(grid.keys)).prefix(ordered.count))
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
        if kind == .home {
            spare += PageTemplate.displaceable.compactMap { key in
                frame.fixed.first { $0.value.key == key }?.key
            }
        }
        for cell in spare {
            guard let link = pendingLinks.popFirst() else { break }
            grid[cell] = entry(link)
        }
        // A link is never lost: with no cell left it starts a second screen.
        let overflow = pendingLinks.map(entry)

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
        if target == nil, kind == .home {
            target = PageTemplate.displaceable.lazy.compactMap { key in
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
    static func spread(_ words: [GeneratedTile], taken: Set<Int>,
                       lookup: [String: TileModel]) -> [Int] {
        let groups = Band.allCases.map { b in words.filter { band(of: $0, lookup: lookup) == b } }
            .filter { !$0.isEmpty }
        let free = { (col: Int) in
            (1..<PageTemplate.rows).map { PageTemplate.cell(row: $0, col: col) }.filter { !taken.contains($0) }
        }
        for gap in [1, 0] {
            var cells: [Int] = []
            var col = 0
            var fits = true
            for (n, group) in groups.enumerated() {
                var remaining = group.count
                while remaining > 0 {
                    guard col < 10 else { fits = false; break }
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
        return Array(PageTemplate.wordCells(excluding: taken).prefix(words.count))
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
