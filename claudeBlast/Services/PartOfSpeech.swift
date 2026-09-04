// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PartOfSpeech.swift
//  claudeBlast
//
//  The grammatical axis — a second, independent view of the vocabulary.
//

import Foundation

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

    /// Caregiver-facing label. Plain words, not grammar-class jargon: the reader
    /// is a parent as often as a therapist.
    var label: String {
        switch self {
        case .noun: return "Things"
        case .verb: return "Actions"
        case .adjective: return "Describing"
        case .pronoun: return "Pronouns"
        case .preposition: return "Position"
        case .determiner: return "How many"
        case .question: return "Questions"
        case .negation: return "Saying no"
        case .social: return "Social"
        case .interjection: return "Whole phrases"
        case .conjunction: return "Joining"
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
/// ## Extending it
///
/// A word a therapist adds is not in the file, and `partOfSpeech(for:)` answers
/// `nil` for it rather than guessing. That is the honest answer today and the
/// seam for later: `overrides` is where a dynamic source plugs in — a classifier
/// run at word-add time, or a caregiver's own choice — without any caller
/// changing. Coverage reporting is about *core* words, which are ours, so the
/// static table already answers the question it was built for.
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

    /// Runtime additions, for words the bundle does not know. Empty until a
    /// dynamic source exists; the lookup already consults it.
    static var overrides: [String: PartOfSpeech] = [:]

    static func partOfSpeech(for key: String) -> PartOfSpeech? {
        overrides[key] ?? bundled[key]
    }

    /// Every bundled word of one part of speech, sorted.
    static func keys(_ pos: PartOfSpeech) -> [String] {
        let all = bundled.merging(overrides) { _, new in new }
        return all.filter { $0.value == pos }.keys.sorted()
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
