// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PartOfSpeech.swift
//  claudeBlast
//
//  The grammatical axis — a second, independent view of the vocabulary.
//

import Foundation
import SwiftData

/// What kind of word this is, grammatically.
///
/// **Deliberately not `wordClass`.** `wordClass` answers the *sentence
/// generator's* question — is `snack_bar` a place or a food — and it is injected
/// into the prompt and the cache key to settle exactly that
/// (`SentencePromptBuilder`). This answers a different question, for a different
/// reader: which pronouns does this board have, does it carry any question
/// words, show me the verbs.
///
/// Neither axis derives from the other. `actions` happens to line up with verbs;
/// nothing else does — pronouns are scattered across `core` and `people`, and
/// `describe` mixes adjectives with adverbs.
enum PartOfSpeech: String, CaseIterable, Codable, Identifiable, Sendable {
    case noun
    case verb
    case adjective
    case pronoun
    case preposition
    case determiner
    case question
    case negation
    case social
    case interjection
    case conjunction

    var id: String { rawValue }

    /// The standard grammatical term.
    ///
    /// **Deliberately not simplified.** These started as friendly paraphrases —
    /// "Things", "Position", "How many" — on the theory that the reader is a
    /// parent as often as a therapist. That was a mistake: this is the working
    /// vocabulary of the people who will use these screens hardest, and the
    /// paraphrases were not even accurate. "Position" for *preposition* is
    /// wrong (`with`, `for` and `to` are not positions), and an SLP asked to
    /// find prepositions should not have to guess which of our words means
    /// theirs. A parent who does not know the term learns it here, correctly,
    /// and can then read it on any other board or in any report.
    ///
    /// `examples` carries the explaining instead, where there is room for it.
    var label: String {
        switch self {
        case .noun: return "Noun"
        case .verb: return "Verb"
        case .adjective: return "Adjective"
        case .pronoun: return "Pronoun"
        case .preposition: return "Preposition"
        case .determiner: return "Determiner"
        case .question: return "Question word"
        case .negation: return "Negation"
        case .social: return "Social"
        case .interjection: return "Interjection"
        case .conjunction: return "Conjunction"
        }
    }

    /// A few of this board's own words, for a reader who wants the term
    /// grounded. Shown beside the label where the layout has room — the picker —
    /// and omitted where it does not.
    var examples: String {
        switch self {
        case .noun: return "mom, banana, toilet"
        case .verb: return "want, go, help"
        case .adjective: return "hungry, big, tired"
        case .pronoun: return "I, you, it"
        case .preposition: return "in, on, with"
        case .determiner: return "more, all, some"
        case .question: return "what, where, why"
        case .negation: return "no, not, stop"
        case .social: return "please, sorry, hi"
        case .interjection: return "yes, all done, uh-oh"
        case .conjunction: return "and, but, because"
        }
    }

    /// Order for a picker or a coverage report: the parts of speech a core board
    /// is judged on first, then the rest.
    static let display: [PartOfSpeech] = [
        .pronoun, .verb, .adjective, .question, .preposition,
        .determiner, .negation, .social, .interjection, .conjunction, .noun,
    ]
}

/// Part of speech for every bundled word.
///
/// ## Why this is a file, not a field
///
/// `TileModel.key` is a language-neutral concept id that never changes, so the
/// mapping can live beside the vocabulary rather than on the model. That keeps it
/// out of the synced CloudKit schema entirely — no new property, no
/// additive-only commitment, nothing that has to land before promotion.
///
/// The file stays a file even though `TileModel.partOfSpeechRaw` now exists:
/// the property is for the exceptions — a therapist's correction, a classifier's
/// answer for a word the bundle never heard of — and 496 bundled words do not
/// each need a copy of a fact we already know.
///
/// ## Extending it
///
/// A word a therapist adds is not in the file, and this answers `nil` for it
/// rather than guessing. That was the honest answer when the only consumer was a
/// coverage report about *core* words, which are ours.
///
/// Color changed what nil costs. A caregiver's "grandma" rendering
/// furniture-gray on a board where every other noun is orange is a visible
/// defect, not a missing table row — so `TileModel.resolvedPartOfSpeech` adds a
/// derivation below this one and never answers nil for a real word. This stays
/// strict, and the split is deliberate: guessing is right for a color and wrong
/// for a count.
enum PartOfSpeechIndex {

    /// Word key → part of speech, from `Resources/parts_of_speech.json`.
    private static let bundled: [String: PartOfSpeech] = {
        guard let url = Bundle.main.url(forResource: "parts_of_speech", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let grouped = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }

        var out: [String: PartOfSpeech] = [:]
        for (raw, keys) in grouped {
            guard let pos = PartOfSpeech(rawValue: raw) else { continue }
            for key in keys { out[key] = pos }
        }
        return out
    }()

    /// Therapist corrections, projected from `TileModel.partOfSpeechRaw`.
    ///
    /// This lookup takes a key and not a tile — `CoverageReport` works on key
    /// sets — so a stored answer has to reach it some other way. Same shape as
    /// `TileImageResolver.aliasMap`: one fetch for the whole table, holding only
    /// the entries that differ from the bundle, which in practice is a handful.
    ///
    /// **Without this the report and the board disagree.** A word a therapist
    /// re-classified would take its new color on the tile and still be counted
    /// under its old part of speech in coverage — the sort of split that is
    /// invisible until someone reads the report carefully.
    private static var stored: [String: PartOfSpeech] = [:]

    /// Reload corrections. Call at launch and whenever a tile's part of speech
    /// changes, is imported, or arrives by sync.
    @MainActor
    static func refreshStored(from context: ModelContext) {
        guard let tiles = try? context.fetch(FetchDescriptor<TileModel>()) else { return }
        var next: [String: PartOfSpeech] = [:]
        for tile in tiles {
            if let pos = tile.storedPartOfSpeech { next[tile.key] = pos }
        }
        stored = next
    }

    /// Record one correction without a refetch — the picker's path.
    static func setStored(_ partOfSpeech: PartOfSpeech?, for key: String) {
        if let partOfSpeech {
            stored[key] = partOfSpeech
        } else {
            stored.removeValue(forKey: key)
        }
    }

    /// Part of speech for a word key, for **reporting**.
    ///
    /// Nil-able on purpose, and it does **not** consult the `wordClass`
    /// derivation. Coverage answers "does this board carry any question words",
    /// and a report that pads its counts with guesses is worth less than one
    /// that says it does not know — the finding that started this axis (zero
    /// question words on the board) only means anything if the counts are
    /// honest. For color, which must never answer nil for a real word, use
    /// `TileModel.resolvedPartOfSpeech`.
    static func partOfSpeech(for key: String) -> PartOfSpeech? {
        stored[key] ?? bundled[key]
    }

    /// The bundle's answer, ignoring any correction.
    ///
    /// Needed by "Automatic" in the word-type picker: a therapist has to be able
    /// to see what they are overriding, and what clearing the override would
    /// restore. Consulting `partOfSpeech(for:)` there would echo their own
    /// correction back at them.
    static func bundledPartOfSpeech(for key: String) -> PartOfSpeech? {
        bundled[key]
    }

    /// Every word of one part of speech, sorted — corrections included, so a
    /// re-classified word moves between lists rather than appearing in both.
    static func keys(_ pos: PartOfSpeech) -> [String] {
        bundled.merging(stored) { _, correction in correction }
            .filter { $0.value == pos }
            .keys.sorted()
    }

    /// How many words of each part of speech a set of tile keys contains.
    ///
    /// The shape a coverage report is built from: hand it a board's keys and it
    /// answers "does this child have any question words" — the question that
    /// found seven missing.
    static func coverage(of keys: some Sequence<String>) -> [PartOfSpeech: Int] {
        var counts: [PartOfSpeech: Int] = [:]
        var seen = Set<String>()
        for key in keys where seen.insert(key).inserted {
            guard let pos = partOfSpeech(for: key) else { continue }
            counts[pos, default: 0] += 1
        }
        return counts
    }
}

// MARK: - Resolution

extension TileModel {

    /// Part of speech for this tile, resolved through four layers:
    ///
    ///     1. partOfSpeechRaw         stored, synced — therapist / classifier truth
    ///     2. parts_of_speech.json    bundled table, 496 words
    ///     3. derived from wordClass  total for any real word
    ///     4. nil                     structural chrome only
    ///
    /// **Only chrome answers nil.** That is what separates this from
    /// `PartOfSpeechIndex.partOfSpeech(for:)`, and it is the whole reason the
    /// derivation exists: this feeds `TileColorResolver`, and a caregiver's
    /// "grandma" must not render furniture-gray on a board where every other
    /// noun is orange.
    ///
    /// **Layer 1 must outrank layer 2.** A therapist calling `more` a verb on
    /// their board is correcting a *bundled* word — exactly the kind most likely
    /// to be argued about — and if the file won, the correction would silently
    /// do nothing.
    ///
    /// Reporting deliberately stops after layer 2; see
    /// `PartOfSpeechIndex.partOfSpeech(for:)`.
    var resolvedPartOfSpeech: PartOfSpeech? {
        storedPartOfSpeech ?? derivedPartOfSpeech
    }

    /// What this tile would resolve to with **no** stored correction — layers 2
    /// and 3 only.
    ///
    /// This is what "Automatic" means in the picker, and it has to skip layer 1
    /// or the row lies: with a correction set, asking `resolvedPartOfSpeech`
    /// would make Automatic echo the override back, so a therapist could never
    /// see what they were overriding or what clearing it would restore.
    var derivedPartOfSpeech: PartOfSpeech? {
        if let bundled = PartOfSpeechIndex.bundledPartOfSpeech(for: key) { return bundled }
        return VocabularyClasses.known(wordClass)?.defaultPartOfSpeech
    }
}
