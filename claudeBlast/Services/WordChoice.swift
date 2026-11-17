// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordChoice.swift
//  claudeBlast
//
//  What the shared word chooser offers, kept out of the view so it can be
//  tested: which words, which class chips, and in what order.
//

import Foundation

/// The words a chooser offers and how it narrows them.
///
/// Every "pick a word" surface used to have its own search, and each matched
/// differently: one by plain `contains` on the key, others by `WordFinder`,
/// some leaving out words hidden from the child and some not. `WordChooser`
/// asks here instead, so a search for "ice cream" finds the same words
/// wherever a caregiver types it.
enum WordChoice {
    struct Rules {
        /// Words left out: already listed, or the tile being given art.
        var excluding: Set<String> = []
        /// Folder tiles for pages (`page_link`). A picture or a Me page word
        /// is never one.
        var includesPageLinks = false
    }

    /// The words on offer, before search: never a word hidden from the child.
    static func candidates(_ tiles: [TileModel], rules: Rules) -> [TileModel] {
        tiles.filter { tile in
            !tile.isHiddenFromChild
                && !rules.excluding.contains(tile.key)
                && (rules.includesPageLinks
                    || (tile.wordClass != PageLink.wordClass
                        && PageLink.targetPage(forKey: tile.key) == nil))
        }
    }

    /// The class chips for these words, in the caregiver order of
    /// `word_classes.json`; a class the file does not know goes last, by name.
    static func classes(of tiles: [TileModel]) -> [String] {
        let present = Set(tiles.map(\.wordClass).filter { !$0.isEmpty })
        let known = VocabularyClasses.all.map(\.name).filter(present.contains)
        let unknown = present.subtracting(known).sorted()
        return known + unknown
    }

    /// What a class chip says.
    static func label(ofClass wordClass: String) -> String {
        if wordClass == PageLink.wordClass { return "Page Links" }
        return VocabularyClasses.known(wordClass)?.label ?? wordClass.capitalized
    }

    /// `tiles` narrowed to a class, then to a search: best match first while
    /// searching (`WordFinder.rank`), alphabetical otherwise.
    static func filter(_ tiles: [TileModel], query: String, wordClass: String?) -> [TileModel] {
        let inClass = wordClass.map { wc in tiles.filter { $0.wordClass == wc } } ?? tiles
        let q = WordFinder.normalize(query)
        guard !q.isEmpty else {
            return inClass.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        return inClass
            .compactMap { tile in WordFinder.rank(of: q, in: tile).map { (tile, $0) } }
            .sorted { ($0.1, $0.0.key.count, $0.0.key) < ($1.1, $1.0.key.count, $1.0.key) }
            .map(\.0)
    }
}
