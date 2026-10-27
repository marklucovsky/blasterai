// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordFinder.swift
//  claudeBlast
//
//  Find Word, from the Caregiver Menu: type a word, get the places it is on
//  the active board, and go to one. `WordPlaces` answers the same question for
//  Manage Vocabulary across every scene; this answers it for the board in hand,
//  with the page keys to walk and the reason a word cannot be reached.
//

import Foundation

enum WordFinder {

    /// One place a matching word appears on the board.
    struct Finding: Identifiable, Hashable {
        /// Whether, and how, a place can be gone to. The ones that cannot are
        /// listed rather than left out: "why can't I find X" is the question
        /// the search exists to answer.
        enum Status: Hashable {
            case available
            /// Above the board's current level; shown from this level.
            case aboveLevel(Int)
            /// Concealed by a caregiver on this page.
            case concealed
            /// Visible, but on a page no folder leads to at the current level —
            /// `colors` at level 3, while Groups shows from level 4. Still gone
            /// to: the word is on the child's board, only the way in is not.
            /// The page opens on its own, so Home is the way back.
            case unreachable
        }

        let key: String
        let label: String
        let pageKey: String
        let pageTitle: String
        /// The pages to open from home, in order, to reach the page — home
        /// itself excluded, so empty for a word on home. Just the page itself
        /// when no folder leads there.
        let path: [String]
        /// `path` as page titles.
        let route: [String]
        let status: Status
        /// The query is the word, not just part of it.
        let isExact: Bool

        var id: String { "\(key)|\(pageKey)" }
        /// The word is on the board at this level, so there is somewhere to go.
        var isAvailable: Bool { status == .available || status == .unreachable }

        /// "Home", "Groups › Animals", or the page's own title when no folder
        /// leads there.
        var place: String {
            if status == .unreachable { return pageTitle }
            return route.isEmpty ? "Home" : route.joined(separator: " › ")
        }

        /// Why it cannot be gone to, or what is odd about going there; nil
        /// when there is nothing to say.
        var reason: String? {
            switch status {
            case .available: nil
            case .aboveLevel(let level): "Shows from level \(level)"
            case .concealed: "Concealed on this page"
            case .unreachable: "No folder leads here · Home goes back"
            }
        }
    }

    /// The most results a search returns. A one-letter query on a full board
    /// matches hundreds of words, and nobody reads past the first screen.
    static let limit = 60

    /// Every place a word matching `query` appears in `scene`.
    ///
    /// Matches a word's label, its spoken value, or its key, ignoring case and
    /// accents: the whole word first, then a word that starts with the query
    /// ("eat" finds "eat" before "eating"; "done" finds "all done"), then one
    /// that merely contains it. Within each, places that can be gone to come
    /// first — those a folder leads to ahead of those none does — then by
    /// word, then by the shortest route.
    ///
    /// - Parameter lookup: the tiles by key. Words hidden from the child
    ///   (retired, needs review) are left out entirely — the board reflows
    ///   around them, so they have no place on it.
    static func find(_ query: String, in scene: BlasterScene,
                     lookup: [String: TileModel]) -> [Finding] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }

        let level = scene.effectiveRevealLevel
        // Routes at the current level: a folder above it is not a way in.
        let paths = WordPlaces.pathsFromHome(pages: scene.visiblePages, homeKey: scene.homePageKey,
                                             row: BoardChrome.rowPages(of: scene))
        let titles = Dictionary(scene.pages.map { ($0.key, $0.title) },
                                uniquingKeysWith: { first, _ in first })

        var ranked: [(rank: Int, finding: Finding)] = []
        var index: [String: Int] = [:]
        for page in scene.pages {
            for entry in page.tiles where !entry.isSpacer {
                guard let tile = lookup[entry.key], !tile.isHiddenFromChild,
                      let rank = rank(of: q, in: tile) else { continue }
                let status: Finding.Status
                if entry.isConcealed {
                    status = .concealed
                } else if entry.isAboveLevel(level) {
                    status = .aboveLevel(entry.revealLevel)
                } else if paths[page.key] == nil {
                    status = .unreachable
                } else {
                    status = .available
                }
                let path = paths[page.key] ?? [page.key]
                let finding = Finding(key: entry.key,
                                      label: tile.displayName.isEmpty ? tile.value : tile.displayName,
                                      pageKey: page.key,
                                      pageTitle: page.title,
                                      path: path,
                                      route: paths[page.key].map { $0.compactMap { titles[$0] } } ?? [],
                                      status: status,
                                      isExact: rank == 0)
                // A word twice on one page is one place — the better of the two.
                if let i = index[finding.id] {
                    if !ranked[i].finding.isAvailable && finding.isAvailable {
                        ranked[i] = (rank, finding)
                    }
                } else {
                    index[finding.id] = ranked.count
                    ranked.append((rank, finding))
                }
            }
        }

        return ranked
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                if a.finding.isAvailable != b.finding.isAvailable { return a.finding.isAvailable }
                // A place with a folder route before one without.
                let aRouted = a.finding.status == .available, bRouted = b.finding.status == .available
                if aRouted != bRouted { return aRouted }
                let byLabel = a.finding.label.localizedCaseInsensitiveCompare(b.finding.label)
                if byLabel != .orderedSame { return byLabel == .orderedAscending }
                return a.finding.path.count < b.finding.path.count
            }
            .prefix(limit)
            .map(\.finding)
    }

    /// The one place Return should go to, if there is one: the only place that
    /// can be gone to, or else the only one that is the whole word. Nil when
    /// the caregiver has to choose.
    static func onlyMatch(in findings: [Finding]) -> Finding? {
        let available = findings.filter(\.isAvailable)
        if available.count == 1 { return available[0] }
        let exact = available.filter(\.isExact)
        return exact.count == 1 ? exact[0] : nil
    }

    // MARK: - Matching

    /// 0 whole word, 1 a word starting with the query, 2 containing it; nil
    /// for no match.
    private static func rank(of query: String, in tile: TileModel) -> Int? {
        let terms = Set([tile.displayName, tile.value, tile.key.replacingOccurrences(of: "_", with: " ")]
            .map(normalize)
            .filter { !$0.isEmpty })
        if terms.contains(query) { return 0 }
        let startsWord = terms.contains { term in
            term.hasPrefix(query)
                || term.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .contains { $0.hasPrefix(query) }
        }
        if startsWord { return 1 }
        if terms.contains(where: { $0.contains(query) }) { return 2 }
        return nil
    }

    nonisolated static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
