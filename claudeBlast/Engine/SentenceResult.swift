// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceResult.swift
//  claudeBlast
//

import Foundation

struct TileSelection: Sendable, Equatable, Hashable {
    let key: String
    let value: String
    let wordClass: String

    /// Part of speech captured when the tile was tapped, so a chip in the tray
    /// and the tile on the board cannot disagree about color.
    ///
    /// Snapshotted rather than re-derived at render time because the first layer
    /// of resolution — a therapist's stored correction — lives on `TileModel`,
    /// which a selection does not carry. Deriving from `wordClass` alone in the
    /// tray would quietly paint the chip a different color from the tile the
    /// child just pressed.
    let partOfSpeech: PartOfSpeech?

    init(key: String, value: String, wordClass: String, partOfSpeech: PartOfSpeech? = nil) {
        self.key = key
        self.value = value
        self.wordClass = wordClass
        // No tile in hand, so this can reach layers 2 and 3 but not a stored
        // correction. Callers that have a TileModel should use `init(from:)`.
        self.partOfSpeech = partOfSpeech
            ?? PartOfSpeechIndex.partOfSpeech(for: key)
            ?? VocabularyClasses.known(wordClass)?.defaultPartOfSpeech
    }

    init(from tile: TileModel) {
        self.key = tile.key
        self.value = tile.value
        self.wordClass = tile.wordClass
        self.partOfSpeech = tile.resolvedPartOfSpeech
    }

    // MARK: - Typed words

    /// Key prefix of a typed word that is not in the vocabulary. Angle
    /// brackets keep it clear of every tile key, which are lowercase words.
    static let typedPrefix = "<typed>:"
    /// The class a typed word carries: no picture, no part of speech.
    static let typedClass = "typed"

    /// A word typed on the keyboard that matches no tile: drawn as text.
    /// A typed sum, or a piece of one: drawn as keys, said once (see
    /// `SpokenSums`).
    var isMath: Bool { isTyped && MathHelper.isMathText(value) }

    static func typed(_ word: String) -> TileSelection {
        TileSelection(key: typedPrefix + word, value: word, wordClass: typedClass)
    }

    /// Typed, and not a word of the vocabulary — it has no picture.
    var isTyped: Bool { key.hasPrefix(Self.typedPrefix) }
}

struct TokenUsage: Sendable {
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let promptCachedTokens: Int
}

struct SentenceResult: Sendable {
    let text: String
    let usage: TokenUsage?

    init(text: String, usage: TokenUsage? = nil) {
        self.text = text
        self.usage = usage
    }
}

/// Lifecycle state for a TileGroup in the sentence tray timeline.
enum TileGroupState: Sendable, Equatable {
    /// Tiles being added; no sentence has been generated yet.
    case building
    /// Sentence has been generated. Tapping a new tile flushes this group to history.
    case locked
    /// Was locked; child has removed a tile and the previously-locked sentence is now stale.
    /// Generation will re-fire on debounce/Go.
    case unlockedEditable
}

/// An utterance in the sentence tray timeline: up to N tiles plus the generated sentence.
/// Of a line of typed sums, what Play has said. Each sum is said once — Play
/// says what came after the last one — so a child can type `1+1=2`, Play,
/// `2+2=4`, Play, and hear each once (Mark, 2026-11-20).
struct SpokenSums: Sendable, Equatable {
    /// How many words of the line have been said.
    var count = 0
    /// Where each said sum starts, so Play with nothing new, or a tap on a
    /// sum, says that sum again.
    var starts: [Int] = []

    mutating func said(from start: Int, to end: Int) {
        said(starts: [start], to: end)
    }

    /// Said, as one sum starting at each of `starts`.
    mutating func said(starts new: [Int], to end: Int) {
        guard let first = new.first, first < end else { return }
        starts.append(contentsOf: new)
        count = end
    }

    /// The line lost its word at `index`.
    mutating func remove(at index: Int) {
        if index < count { count -= 1 }
        starts = starts.map { $0 > index ? $0 - 1 : $0 }.filter { $0 < count }
        starts = starts.enumerated().filter { $0.offset == 0 || starts[$0.offset - 1] != $0.element }.map(\.element)
    }

    /// The line lost its first `n` words (the strip's oldest drop off).
    mutating func dropFirst(_ n: Int) {
        guard n > 0 else { return }
        count = max(0, count - n)
        // A sum that lost its first words now starts at 0.
        starts = starts.map { max(0, $0 - n) }.filter { $0 < count }
        if count > 0, starts.first != 0 { starts.insert(0, at: 0) }
        starts = starts.enumerated().filter { $0.offset == 0 || starts[$0.offset - 1] != $0.element }.map(\.element)
    }

    /// The sum the word at `index` is in: from its start to the next one's.
    func range(around index: Int) -> Range<Int> {
        let start = starts.last { $0 <= index } ?? index
        let end = starts.first { $0 > index } ?? (index < count ? count : index + 1)
        return start..<max(end, index + 1)
    }
}

struct TileGroup: Identifiable, Sendable, Equatable {
    let id: UUID
    var tiles: [TileSelection]
    /// Page each tile was pressed on — parallel to `tiles`, one entry each.
    ///
    /// Deliberately NOT a field on `TileSelection`. That type is `Hashable` and
    /// feeds `SentenceCacheManager.cacheKey`, so carrying the page there would
    /// make the same words picked from two pages into two different cache
    /// entries — halving the hit rate to record something the cache has no
    /// interest in.
    var pageKeys: [String]
    var sentence: String?
    var state: TileGroupState
    let createdAt: Date
    var repetitionCount: Int
    /// Something in it was typed on the keyboard. A typed line is said as
    /// typed: never sent to sentence generation, and not held to the
    /// words-per-message cap (Mark, 2026-11-17). Stays set once set, even if
    /// every typed word matched a tile, because the line is still the user's
    /// own words in their own order.
    var isTyped: Bool = false
    /// Of a typed line of sums, what Play has said (`SpokenSums`).
    var spokenSums = SpokenSums()

    init(
        id: UUID = UUID(),
        tiles: [TileSelection] = [],
        pageKeys: [String] = [],
        sentence: String? = nil,
        state: TileGroupState = .building,
        createdAt: Date = .now,
        repetitionCount: Int = 0
    ) {
        self.id = id
        self.tiles = tiles
        self.pageKeys = pageKeys
        self.sentence = sentence
        self.state = state
        self.createdAt = createdAt
        self.repetitionCount = repetitionCount
    }
}
