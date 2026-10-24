// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TopicWordMatcher.swift
//  claudeBlast
//
//  From the model's ranked words to a page's tiles. The model writes words,
//  not keys — matching them to the vocabulary is code's job (2026-10-20: left
//  to the model, gpt-4o-mini marked Elsa, Mario and Christmas as existing, and
//  they were dropped). Port of `tools/eval/scorers.score_topic_words`,
//  `resolve_key` and `balance`; the eval scores what this does.
//

import Foundation

enum TopicWordMatcher {
    /// The page's words in rank order, and the ones past the budget.
    struct Selection {
        var page: [GeneratedTile]
        var overflow: [GeneratedTile]
    }

    /// A page that talks rather than labels (2026-10-20, topic-t7: the
    /// feelings and describing words ranked last, so hot, scared and excited
    /// lost their cells to wolf, eagle and fence).
    static let pageFloor: [(PartOfSpeech, Int)] = [(.verb, 5), (.adjective, 3)]

    /// Verbs that go with almost any topic, for a page whose words are nearly
    /// all things (2026-10-24, the fire station: read and listen were its only
    /// verbs). They fill the verb floor when the model's own verbs run out.
    static let fallbackVerbs = ["look", "see", "like", "play", "feel"]

    static let irregularPlurals = ["teeth": "tooth", "feet": "foot", "mice": "mouse",
                                   "geese": "goose", "children": "child"]

    /// Match each word to the vocabulary, drop `excluded` (the frame, the
    /// system row) and duplicates, then cut at `budget` with the floor.
    static func select(_ words: [TopicWordsService.Response.Word],
                       excluding excluded: Set<String>,
                       allTiles: [TileModel],
                       budget: Int = TopicWordsService.budget) -> Selection {
        let lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let labels = labelIndex(allTiles)
        let tiles = words.compactMap { word -> GeneratedTile? in
            let label = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = TileModel.normalizeKey(label)
            guard !raw.isEmpty else { return nil }
            if let key = match(raw, lookup: lookup, labels: labels) {
                return GeneratedTile(key: key, isAudible: true, link: "")
            }
            return GeneratedTile(key: raw, isAudible: true, link: "",
                                 displayName: label, wordClass: word.wordClass ?? "object")
        }
        return select(tiles, excluding: excluded, lookup: lookup, budget: budget)
    }

    /// Dedupe, drop `excluded`, cut and balance tiles that are already
    /// resolved — the refine path, whose tiles arrive as keys.
    static func select(_ tiles: [GeneratedTile], excluding excluded: Set<String>,
                       lookup: [String: TileModel],
                       budget: Int = TopicWordsService.budget) -> Selection {
        var seen = excluded
        let ranked = tiles.filter { seen.insert($0.key).inserted }
        let fallback = fallbackVerbs.filter { lookup[$0] != nil && !seen.contains($0) }
            .map { GeneratedTile(key: $0, isAudible: true, link: "") }
        return balance(ranked, budget: budget, fallback: fallback) { partOfSpeech(of: $0, lookup: lookup) }
    }

    /// Cut at the budget, then pull verbs and describing words up from the
    /// overflow until the page has `pageFloor` of each, each displacing the
    /// lowest-ranked noun on the page. When the overflow has none left,
    /// `fallback` words of that kind fill the rest.
    static func balance(_ ranked: [GeneratedTile], budget: Int,
                        fallback: [GeneratedTile] = [],
                        pos: (GeneratedTile) -> PartOfSpeech) -> Selection {
        var page = Array(ranked.prefix(budget))
        var overflow = Array(ranked.dropFirst(budget))
        var spare = fallback
        for (wanted, floor) in pageFloor {
            while page.count(where: { pos($0) == wanted }) < floor {
                let promoted: GeneratedTile
                if let up = overflow.firstIndex(where: { pos($0) == wanted }) {
                    promoted = overflow.remove(at: up)
                } else if let up = spare.firstIndex(where: { pos($0) == wanted }) {
                    promoted = spare.remove(at: up)
                } else { break }
                if page.count >= budget {
                    guard let down = page.lastIndex(where: { pos($0) == .noun }) else { break }
                    overflow.append(page.remove(at: down))
                }
                page.append(promoted)
            }
        }
        let rank = Dictionary(ranked.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
        overflow.sort { (rank[$0.key] ?? 0) < (rank[$1.key] ?? 0) }
        return Selection(page: page, overflow: overflow)
    }

    /// The part of speech that decides a word's band and the floor: the
    /// tile's own for an existing word, its class's for a new one. A new word
    /// filed under "social" is a name (Christmas, Hanukkah) — social is for
    /// greetings and manners, and those are already in the vocabulary.
    static func partOfSpeech(of tile: GeneratedTile, lookup: [String: TileModel]) -> PartOfSpeech {
        if let existing = lookup[tile.key] {
            return existing.resolvedPartOfSpeech ?? .noun
        }
        let pos = VocabularyClasses.known(tile.wordClass ?? "")?.defaultPartOfSpeech ?? .noun
        return pos == .social ? .noun : pos
    }

    // MARK: - Matching

    /// A word's vocabulary key: the key itself, a tile's label ("TV" → `tv`
    /// may be keyed otherwise), a plural of a noun, or the bare form of a
    /// sense-marked key ("hot" → `hot_`). Nil means a new word.
    static func match(_ key: String, lookup: [String: TileModel],
                      labels: [String: String]) -> String? {
        if lookup[key] != nil { return key }
        if let labelled = labels[key] { return labelled }
        return resolveKey(key, lookup: lookup)
    }

    /// Only a noun has a plural: "shorts" is not more than one "short" (a
    /// describing word), so it stays a new word rather than the wrong tile.
    static func resolveKey(_ key: String, lookup: [String: TileModel]) -> String? {
        let plurals = [irregularPlurals[key],
                       key.hasSuffix("s") ? String(key.dropLast()) : nil,
                       key.hasSuffix("es") ? String(key.dropLast(2)) : nil]
        for case let candidate? in plurals {
            if let tile = lookup[candidate], (tile.resolvedPartOfSpeech ?? .noun) == .noun {
                return candidate
            }
        }
        for candidate in [key + "_", key + "__"] where lookup[candidate] != nil {
            return candidate
        }
        return nil
    }

    /// Normalized label → key, for tiles whose label differs from their key.
    private static func labelIndex(_ tiles: [TileModel]) -> [String: String] {
        var index: [String: String] = [:]
        for tile in tiles.sorted(by: { $0.key < $1.key })
        where !tile.isStructuralChrome && !tile.isRetired {
            for label in [tile.displayName, tile.value] {
                let normalized = TileModel.normalizeKey(label)
                if !normalized.isEmpty, normalized != tile.key, index[normalized] == nil {
                    index[normalized] = tile.key
                }
            }
        }
        return index
    }
}
