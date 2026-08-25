// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  Tier1Scorers.swift
//  claudeBlastTests
//
//  Tier 1: cheap, deterministic sanity checks. NOT a quality model — just a
//  floor that catches gross failures (the prompt's "(wordclass)" annotation
//  leaking into output, empty/echo/degenerate text, an escalation ladder that
//  goes backwards). Qualitative judgment is Tier 2 (the LLM judge). Kept
//  intentionally small per the agreed scope.
//
//  Pure functions over strings + tiles, so they're unit-tested offline against
//  fixtures (Tier1ScorerTests) and reused on live output when RUN_LIVE_EVAL.

import Foundation
@testable import claudeBlast

// MARK: - Sentence sanity

struct SentenceSanity {
    var issues: [String] = []
    var passed: Bool { issues.isEmpty }
}

enum Tier1 {

    /// All known wordClass names, lowercased — used to detect prompt-hint echo.
    private static let wordClassNames: Set<String> =
        Set(VocabularyClasses.all.map { $0.name.lowercased() })

    /// Tiny safety net. Tier 1 only flags blatant leakage; nuanced safety is the
    /// system prompt's job and the judge's review.
    private static let unsafeFragments: [String] = ["make love", "kill you", "porn"]

    /// The headline check: did a "(food)"/"(actions)"/… annotation leak into the
    /// output? The user prompt sends tiles as `word (class)`; the model must not
    /// echo the parenthetical. Matches `( class )` for any known class name.
    static func containsWordClassEcho(_ text: String) -> Bool {
        let lower = text.lowercased()
        for name in wordClassNames where lower.contains("(\(name))") || lower.contains("( \(name) )") {
            return true
        }
        return false
    }

    /// Output is empty, whitespace, or punctuation-only.
    static func isEmptyOrDegenerate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return !trimmed.contains(where: { $0.isLetter })
    }

    /// Output is just the input tile values strung together with no real
    /// sentence added (a raw echo of the selection). Compares the letter-only,
    /// lowercased forms so punctuation/spacing don't mask an echo.
    static func looksLikeRawTileEcho(_ text: String, tiles: [TileSelection]) -> Bool {
        func lettersOnly(_ s: String) -> String {
            String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let out = lettersOnly(text)
        let joined = lettersOnly(tiles.map(\.value).joined())
        guard !joined.isEmpty else { return false }
        // Echo if the output is essentially just the concatenated tile words.
        return out == joined
    }

    /// Run all sentence checks, collecting issues. `tiles` is the input combo.
    ///
    /// `stage` gates the raw-echo rule only. At Brown's Stage I and II-III a
    /// near-verbatim output is the *correct* answer, not a failure: the child's
    /// mean utterance length is 1-3 words, so "dad, help" for the tiles
    /// `dad + help` is exactly what that child would say. `looksLikeRawTileEcho`
    /// strips punctuation before comparing, so it cannot tell "dad help" from
    /// "Dad, help!" — and at these stages it should not try.
    ///
    /// The rule still applies in full at Stage IV+, where an echo really does
    /// mean the model added nothing. Defaulting to `.fourPlus` keeps every
    /// existing caller as strict as it was.
    ///
    /// This was found by the live eval after Brown's Stages replaced the
    /// grade-level prompt: `dad_help` began failing precisely because the model
    /// started obeying the stage. The check was encoding "always expand", which
    /// was an artifact of the old "2nd-grade student" phrasing.
    static func scoreSentence(_ text: String, tiles: [TileSelection],
                              stage: BrownsStage = .fourPlus) -> SentenceSanity {
        var s = SentenceSanity()
        if isEmptyOrDegenerate(text) { s.issues.append("empty/degenerate output") }
        if containsWordClassEcho(text) { s.issues.append("wordClass annotation leaked into output") }
        if stage == .fourPlus, looksLikeRawTileEcho(text, tiles: tiles) {
            s.issues.append("output is a raw echo of the tiles")
        }
        let lower = text.lowercased()
        for bad in unsafeFragments where lower.contains(bad) {
            s.issues.append("unsafe fragment: \"\(bad)\"")
        }
        return s
    }

    // MARK: - Escalation sanity

    /// Urgency lexicon for the intensity proxy. Deliberately coarse — this is a
    /// signal that escalation is *moving*, not a measure of how good it is.
    private static let urgencyTerms: [String] =
        ["now", "really", "need", "right now", "starving", "must", "so ", "please", "want"]

    /// A rough "insistence" score for one sentence: exclamation marks, ALL-CAPS
    /// emphasis words, and urgency-lexicon hits. Higher = more insistent.
    static func intensity(_ text: String) -> Int {
        let exclam = text.filter { $0 == "!" }.count
        let words = text.split { $0 == " " || $0 == "\n" }.map(String.init)
        let capsWords = words.filter { w in
            let letters = w.filter { $0.isLetter }
            return letters.count >= 2 && letters == letters.uppercased()
        }.count
        let lower = text.lowercased()
        let urgency = urgencyTerms.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        return exclam * 2 + capsWords * 3 + urgency
    }

    struct EscalationSanity {
        var intensities: [Int]
        var issues: [String]
        var passed: Bool { issues.isEmpty }
    }

    /// Score an escalation ladder (step 0 = baseline, then repeats). Flags:
    /// - any per-tile sanity failure on a rung,
    /// - a strict regression (a rung less insistent than the one before),
    /// - a totally flat ladder (no escalation at all across the whole ramp).
    static func scoreEscalation(_ ladder: [String], tiles: [TileSelection],
                                stage: BrownsStage = .fourPlus) -> EscalationSanity {
        var issues: [String] = []
        let intensities = ladder.map(intensity)

        for (i, text) in ladder.enumerated() {
            let s = scoreSentence(text, tiles: tiles, stage: stage)
            if !s.passed { issues.append("step \(i): \(s.issues.joined(separator: ", "))") }
        }
        for i in 1..<max(ladder.count, 1) where i < intensities.count {
            if intensities[i] < intensities[i - 1] {
                issues.append("step \(i) less insistent than step \(i - 1) (\(intensities[i]) < \(intensities[i - 1]))")
            }
        }
        if ladder.count > 1, let first = intensities.first, let last = intensities.last, last <= first {
            issues.append("no escalation across the ramp (start \(first) → end \(last))")
        }
        return EscalationSanity(intensities: intensities, issues: issues)
    }
}
