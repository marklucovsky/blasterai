// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordPredictor.swift
//  claudeBlast
//
//  The keyboard's prediction bar (PR F): the words a person might be typing,
//  from our vocabulary and from what they have typed before, ranked by what
//  has followed the last word and then by their own use. Only once a word is
//  started: with nothing typed the bar is empty (Mark, 2026-11-20). Nothing
//  here leaves the device. See `docs/keyboard-design.md`.
//

import Foundation

struct WordPredictor {

    struct Prediction: Equatable, Identifiable {
        /// As shown and typed.
        let word: String
        /// The vocabulary tile, when the word is one: drawn with its picture.
        let tileKey: String?
        let wordClass: String?
        var id: String { tileKey ?? "<typed>:" + word }
    }

    /// One word it can offer.
    struct Entry {
        let word: String
        let normalized: String
        let tileKey: String?
        let wordClass: String?
        var uses: Int
    }

    private(set) var entries: [Entry] = []
    /// How often each word (normalized) followed another.
    private(set) var next: [String: [String: Int]] = [:]

    init() {}

    /// From the vocabulary and the utterance log.
    ///
    /// - Parameters:
    ///   - tiles: every word tile; hidden words, folders and the Letters pack
    ///     are left out, as `TypedWords.match` leaves them out.
    ///   - history: each utterance's words in order — tile keys, or
    ///     `<typed>:word` for a word typed that we don't have.
    init(tiles: [TileModel], history: [[String]]) {
        var byKey: [String: Int] = [:]
        var byWord: [String: Int] = [:]
        for tile in tiles where !tile.isHiddenFromChild && !tile.isStructuralChrome && tile.wordClass != "letter" {
            let word = tile.displayName.isEmpty ? tile.value : tile.displayName
            let normalized = WordFinder.normalize(word)
            guard !normalized.isEmpty else { continue }
            // One entry a word: the core word over a pack's variant, as
            // `TypedWords.match` picks.
            if let i = byWord[normalized] {
                if tile.key.count < (entries[i].tileKey?.count ?? .max) {
                    entries[i] = Entry(word: word, normalized: normalized, tileKey: tile.key,
                                       wordClass: tile.wordClass, uses: 0)
                    byKey[tile.key] = i
                }
                byKey[tile.key] = i
                continue
            }
            byWord[normalized] = entries.count
            byKey[tile.key] = entries.count
            entries.append(Entry(word: word, normalized: normalized, tileKey: tile.key,
                                 wordClass: tile.wordClass, uses: 0))
        }
        for line in history {
            var previous: String?
            for key in line {
                let index: Int
                if key.hasPrefix(TileSelection.typedPrefix) {
                    let word = String(key.dropFirst(TileSelection.typedPrefix.count))
                    let normalized = WordFinder.normalize(word)
                    // A typed word we don't have: offered too, once said.
                    // Sums are not words, spaces and all (`5/3=1 2/3`).
                    guard !normalized.isEmpty,
                          !MathHelper.isMathText(word.filter { !$0.isWhitespace }) else { previous = nil; continue }
                    if let i = byWord[normalized] {
                        index = i
                    } else {
                        byWord[normalized] = entries.count
                        index = entries.count
                        entries.append(Entry(word: word, normalized: normalized, tileKey: nil,
                                             wordClass: nil, uses: 0))
                    }
                } else if let i = byKey[key] {
                    index = i
                } else {
                    previous = nil
                    continue
                }
                entries[index].uses += 1
                let normalized = entries[index].normalized
                if let previous { next[previous, default: [:]][normalized, default: 0] += 1 }
                previous = normalized
            }
        }
    }

    /// How the bar orders its words (Settings › Keyboard, an experiment).
    enum Order: String, CaseIterable {
        /// The same letters always show the same words in the same places,
        /// so a person learns how many letters it takes (Mark, 2026-11-20:
        /// a fixed position is what motor planning in AAC rests on).
        case alphabetical
        /// What followed the last word, then the person's own use.
        case mostUsed

        var title: String { self == .alphabetical ? "Alphabetical" : "Most Used" }

        static var current: Order {
            UserDefaults.standard.string(forKey: AppSettingsKey.keyboardPredictionOrder)
                .flatMap(Order.init) ?? .alphabetical
        }
    }

    /// What to offer for `prefix`, the word being typed, after `previous`,
    /// the last word in the line. Best first.
    func predict(prefix: String, after previous: String?, order: Order = .mostUsed,
                 limit: Int = 24) -> [Prediction] {
        let p = WordFinder.normalize(prefix)
        // Nothing until a word is started.
        guard !p.isEmpty else { return [] }
        let followers = previous.map(WordFinder.normalize).flatMap { next[$0] } ?? [:]
        let pool = entries.filter { $0.normalized.hasPrefix(p) }
        if order == .alphabetical {
            return pool.sorted { $0.normalized < $1.normalized }
                .prefix(limit)
                .map { Prediction(word: $0.word, tileKey: $0.tileKey, wordClass: $0.wordClass) }
        }
        return pool.sorted { a, b in
            let fa = followers[a.normalized] ?? 0, fb = followers[b.normalized] ?? 0
            if fa != fb { return fa > fb }
            if a.uses != b.uses { return a.uses > b.uses }
            // A word with its picture before one without.
            if (a.tileKey != nil) != (b.tileKey != nil) { return a.tileKey != nil }
            if a.normalized.count != b.normalized.count { return a.normalized.count < b.normalized.count }
            return a.normalized < b.normalized
        }
        .prefix(limit)
        .map { Prediction(word: $0.word, tileKey: $0.tileKey, wordClass: $0.wordClass) }
    }
}
