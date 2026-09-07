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

    /// Reporting stops at the bundled table. It must NOT fall through to the
    /// `wordClass` derivation — a coverage report that pads its counts with
    /// guesses is worth less than one that admits it does not know.
    @Test("Reporting answers nil for an unknown word rather than guessing")
    func reportingDoesNotGuess() {
        let invented = "zzz_not_a_real_word"
        #expect(PartOfSpeechIndex.partOfSpeech(for: invented) == nil)
        #expect(!PartOfSpeechIndex.keys(.noun).contains(invented))
    }

    // MARK: - The four-layer resolution

    private func tile(_ key: String, _ wordClass: String,
                      stored: PartOfSpeech? = nil) -> TileModel {
        let t = TileModel(key: key, value: key, wordClass: wordClass)
        t.storedPartOfSpeech = stored
        return t
    }

    /// Layer 1 over layer 2. A therapist correcting a *bundled* word is the
    /// whole reason the stored field exists — `more` as a verb rather than a
    /// determiner — so the file must not win.
    @Test("A stored part of speech outranks the bundled table")
    func storedBeatsBundled() {
        let bundled = tile("more", "core")
        #expect(bundled.resolvedPartOfSpeech == PartOfSpeechIndex.partOfSpeech(for: "more"))

        let corrected = tile("more", "core", stored: .verb)
        #expect(corrected.resolvedPartOfSpeech == .verb)
    }

    /// Layer 2 over layer 3. `eat` is a verb in the table; its `actions` class
    /// would derive the same answer, so use a word where they differ: `i` is a
    /// pronoun in the table but its `people` class derives to noun.
    @Test("The bundled table outranks the wordClass derivation")
    func bundledBeatsDerived() {
        #expect(VocabularyClasses.known("people")?.defaultPartOfSpeech == .noun)
        #expect(tile("i", "people").resolvedPartOfSpeech == .pronoun)
    }

    /// Layer 3. A caregiver-added word is in no table, and must still get a
    /// color — this is the layer that stops "grandma" rendering as chrome.
    @Test("A caregiver word derives from the class the caregiver picked")
    func unknownWordDerivesFromItsClass() {
        #expect(tile("zzz_grandma", "people").resolvedPartOfSpeech == .noun)
        #expect(tile("zzz_wiggle", "actions").resolvedPartOfSpeech == .verb)
        #expect(tile("zzz_squishy", "describe").resolvedPartOfSpeech == .adjective)
    }

    /// Layer 4, and the only place nil is correct.
    @Test("Structural chrome has no part of speech")
    func chromeResolvesToNil() {
        #expect(tile("home", "navigation").resolvedPartOfSpeech == nil)
        #expect(tile("page_farm", PageLink.wordClass).resolvedPartOfSpeech == nil)
    }

    /// The invariant that matters for the board: **every real word gets a
    /// color.** A word that resolves to nil renders as furniture, which is the
    /// failure this whole chain exists to prevent — and it would appear silently,
    /// on one tile, on somebody's board.
    @Test("No bundled word resolves to chrome")
    func everyRealWordResolves() {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TileModelCodable].self, from: data)
        else { Issue.record("vocabulary.json did not load"); return }

        let unresolved = decoded
            .map { tile($0.key, $0.wordClass) }
            .filter { !$0.isStructuralChrome && $0.resolvedPartOfSpeech == nil }
        #expect(unresolved.isEmpty,
                "no part of speech for: \(unresolved.map(\.key).sorted())")
    }

    // MARK: - Fitzgerald palette

    /// The colors a therapist teaches must actually differ from each other.
    @Test("The Fitzgerald buckets are distinct colors")
    func fitzgeraldBucketsAreDistinct() {
        let buckets: [PartOfSpeech] = [.pronoun, .verb, .adjective, .noun,
                                       .question, .negation, .social, .preposition]
        let colors = buckets.map { TileColorResolver.color(for: $0) }
        #expect(Set(colors.map(\.description)).count == buckets.count)
    }

    /// Fitzgerald groups these, and so do we — pink for social, neutral for
    /// function words.
    @Test("Grouped parts of speech share a color")
    func groupedPartsShareAColor() {
        #expect(TileColorResolver.color(for: .social)
                == TileColorResolver.color(for: .interjection))
        #expect(TileColorResolver.color(for: .determiner)
                == TileColorResolver.color(for: .conjunction))
        #expect(TileColorResolver.color(for: .preposition)
                == TileColorResolver.functionWord)
    }

    /// Fitzgerald owns blue for describing words, and this app owns blue for
    /// "goes somewhere". They collided the moment cards were filled: an
    /// adjective sat in a row of page links and could not be told apart.
    @Test("Navigation blue is not adjective blue")
    func navigationIsDistinctFromAdjective() {
        #expect(TileColorResolver.navigation != TileColorResolver.color(for: .adjective))
        #expect(TileColorResolver.navigation != TileColorResolver.chrome)
    }

    /// The labels are the SLP's own terms, not paraphrases of them. "Position"
    /// for preposition was both jargon-averse and wrong.
    @Test("Word types use standard grammatical terms")
    func labelsAreStandardTerms() {
        #expect(PartOfSpeech.preposition.label == "Preposition")
        #expect(PartOfSpeech.noun.label == "Noun")
        #expect(PartOfSpeech.determiner.label == "Determiner")
        #expect(PartOfSpeech.conjunction.label == "Conjunction")
        // Every type carries examples, since the term now does the naming and
        // the examples do the explaining.
        for pos in PartOfSpeech.allCases {
            #expect(!pos.examples.isEmpty, "\(pos.rawValue) has no examples")
        }
    }

    @Test("Chrome and a missing tile take the chrome color, not a word color")
    func chromeTakesChromeColor() {
        #expect(TileColorResolver.color(for: nil as PartOfSpeech?) == TileColorResolver.chrome)
        #expect(TileColorResolver.color(for: nil as TileModel?) == TileColorResolver.chrome)
        #expect(TileColorResolver.color(for: tile("home", "navigation"))
                == TileColorResolver.chrome)
    }

    // MARK: - Corrections reach the report, not just the board

    /// The gap this closes: a correction lives on `TileModel`, but
    /// `CoverageReport` looks words up by key. Without the projection the tile
    /// would take its new color while coverage still counted it under the old
    /// part of speech — a split nobody sees until they read the report.
    @Test("A stored correction reaches the key-based lookup")
    func correctionReachesReporting() {
        let key = "more"
        let original = PartOfSpeechIndex.partOfSpeech(for: key)
        #expect(original != .verb, "fixture assumes `more` is not a verb in the table")

        PartOfSpeechIndex.setStored(.verb, for: key)
        defer { PartOfSpeechIndex.setStored(nil, for: key) }

        #expect(PartOfSpeechIndex.partOfSpeech(for: key) == .verb)
        #expect(PartOfSpeechIndex.coverage(of: [key])[.verb] == 1)
        // And it moves lists rather than appearing in both.
        #expect(PartOfSpeechIndex.keys(.verb).contains(key))
        if let original {
            #expect(!PartOfSpeechIndex.keys(original).contains(key))
        }
    }

    /// Clearing back to Automatic is the only undo, so it has to actually undo.
    @Test("Clearing a correction restores the bundled answer")
    func clearingACorrectionRestoresTheTable() {
        let key = "more"
        let original = PartOfSpeechIndex.partOfSpeech(for: key)
        PartOfSpeechIndex.setStored(.verb, for: key)
        PartOfSpeechIndex.setStored(nil, for: key)
        #expect(PartOfSpeechIndex.partOfSpeech(for: key) == original)
    }

    /// "Automatic" has to say what it would fall back to, not echo the override
    /// back. Otherwise a therapist cannot see what they are changing, and
    /// clearing the correction becomes a guess.
    @Test("Automatic ignores the stored correction it is offering to replace")
    func derivedIgnoresTheStoredValue() {
        let corrected = tile("more", "core", stored: .verb)
        #expect(corrected.resolvedPartOfSpeech == .verb)
        #expect(corrected.derivedPartOfSpeech == PartOfSpeechIndex.bundledPartOfSpeech(for: "more"))
        #expect(corrected.derivedPartOfSpeech != .verb)
    }

    /// The projection must not leak into the derivation either: a correction
    /// recorded in the index is still a correction, not a bundled fact.
    @Test("Automatic ignores a correction recorded in the index")
    func derivedIgnoresTheProjection() {
        PartOfSpeechIndex.setStored(.verb, for: "more")
        defer { PartOfSpeechIndex.setStored(nil, for: "more") }
        #expect(tile("more", "core").derivedPartOfSpeech != .verb)
    }

    /// A chip in the tray and the tile on the board must not disagree, which
    /// they would if the chip re-derived from `wordClass` and missed a stored
    /// correction.
    @Test("A tray selection carries the tile's resolved part of speech")
    func selectionSnapshotsThePartOfSpeech() {
        let corrected = tile("more", "core", stored: .verb)
        #expect(TileSelection(from: corrected).partOfSpeech == .verb)
        #expect(TileColorResolver.color(for: TileSelection(from: corrected))
                == TileColorResolver.color(for: corrected))
    }
}
}
