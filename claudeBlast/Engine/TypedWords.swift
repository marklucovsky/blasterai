// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TypedWords.swift
//  claudeBlast
//
//  A word typed on the keyboard, matched to the vocabulary: "cookie" typed
//  becomes the cookie tile's chip, picture and all, as Avaz does it.
//

import Foundation

enum TypedWords {

    /// The tile a typed word names, if any.
    ///
    /// Matches the word's label, spoken value or key, ignoring case and
    /// accents (`WordFinder.normalize`). Left out: words hidden from the
    /// child, folders and other board furniture, and the Letters pack — "a"
    /// typed is the word *a*, not the letter tile.
    ///
    /// When more than one tile matches, the one whose key *is* the word wins
    /// (`i` over a custom "I" tile), then the shortest key — the core word
    /// over a pack's variant.
    static func match(_ word: String, in tiles: [TileModel]) -> TileModel? {
        let q = WordFinder.normalize(word)
        guard !q.isEmpty else { return nil }
        let candidates = tiles.filter { tile in
            guard !tile.isHiddenFromChild, !tile.isStructuralChrome,
                  tile.wordClass != "letter" else { return false }
            return [tile.displayName, tile.value, tile.key.replacingOccurrences(of: "_", with: " ")]
                .contains { WordFinder.normalize($0) == q }
        }
        return candidates.min { a, b in
            let aExact = a.key == q, bExact = b.key == q
            if aExact != bExact { return aExact }
            if a.key.count != b.key.count { return a.key.count < b.key.count }
            return a.key < b.key
        }
    }
}
