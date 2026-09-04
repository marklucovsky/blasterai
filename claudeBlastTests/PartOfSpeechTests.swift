// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PartOfSpeechTests.swift
//  claudeBlastTests
//
//  The grammatical axis, and the coverage question that produced it.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PartOfSpeechTests {

    private var vocabularyKeys: [String] {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tiles = try? JSONDecoder().decode([TileModelCodable].self, from: data)
        else { return [] }
        return tiles.map(\.key)
    }

    @Test("The index loads and covers nearly all of the vocabulary")
    func indexLoads() {
        let keys = vocabularyKeys
        #expect(keys.count > 400)

        let classified = keys.filter { PartOfSpeechIndex.partOfSpeech(for: $0) != nil }
        #expect(Double(classified.count) / Double(keys.count) > 0.95)
    }

    /// The gap Brandi's question found: nothing in the vocabulary asked a
    /// question. This is the test that would have caught it.
    @Test("The vocabulary carries the core question words")
    func questionWordsExist() {
        for word in ["what", "where", "who", "why", "when", "how", "which"] {
            #expect(PartOfSpeechIndex.partOfSpeech(for: word) == .question,
                    "\(word) is missing or misfiled")
        }
        #expect(PartOfSpeechIndex.keys(.question).count >= 7)
    }

    @Test("Pronouns are complete in both subject and object form")
    func pronounsAreComplete() {
        for word in ["i", "me", "you", "he", "him", "she", "her",
                     "we", "us", "they", "them", "it"] {
            #expect(PartOfSpeechIndex.partOfSpeech(for: word) == .pronoun,
                    "\(word) is missing or misfiled")
        }
    }

    /// The two axes are independent, and this is the case that shows it:
    /// pronouns are scattered across `wordClass` values because `wordClass`
    /// answers the sentence generator's question, not a grammatical one.
    @Test("Part of speech is not derivable from wordClass")
    func axesAreIndependent() throws {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let tiles = try JSONDecoder().decode([TileModelCodable].self, from: data)
        let byKey = Dictionary(tiles.map { ($0.key, $0.wordClass) }, uniquingKeysWith: { a, _ in a })

        let pronounClasses = Set(PartOfSpeechIndex.keys(.pronoun).compactMap { byKey[$0] })
        #expect(pronounClasses.count > 1,
                "pronouns sit in one wordClass — the axes would then be redundant")
    }

    @Test("Chrome is not vocabulary and carries no part of speech")
    func chromeIsExcluded() {
        for key in ["home", "next_page", "previous_page", "body_health"] {
            #expect(PartOfSpeechIndex.partOfSpeech(for: key) == nil,
                    "\(key) is navigation, not a word")
        }
    }

    /// The shape a coverage report is built from.
    @Test("Coverage counts a board's words by part of speech")
    func coverageCounts() {
        let board = ["i", "you", "want", "eat", "what", "where", "big", "not", "home"]
        let counts = PartOfSpeechIndex.coverage(of: board)

        #expect(counts[.pronoun] == 2)
        #expect(counts[.verb] == 2)
        #expect(counts[.question] == 2)
        #expect(counts[.negation] == 1)
        #expect(counts[.noun] == nil, "home is chrome, not a noun")
    }

    @Test("Coverage does not double-count a word placed twice")
    func coverageDeduplicates() {
        #expect(PartOfSpeechIndex.coverage(of: ["want", "want", "want"])[.verb] == 1)
    }

    /// The seam for therapist-introduced words: unknown answers nil rather than
    /// guessing, and an override is consulted first.
    @Test("An unknown word is unclassified until something says otherwise")
    func overridesExtendTheIndex() {
        let invented = "zzz_not_a_real_word"
        #expect(PartOfSpeechIndex.partOfSpeech(for: invented) == nil)

        PartOfSpeechIndex.overrides[invented] = .noun
        defer { PartOfSpeechIndex.overrides.removeValue(forKey: invented) }

        #expect(PartOfSpeechIndex.partOfSpeech(for: invented) == .noun)
        #expect(PartOfSpeechIndex.keys(.noun).contains(invented))
    }
}
}
