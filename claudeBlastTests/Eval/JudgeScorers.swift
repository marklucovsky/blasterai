// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  JudgeScorers.swift
//  claudeBlastTests
//
//  Tier 2: the LLM judge. Where Tier 1 is a deterministic floor, Tier 2 is the
//  semi-subjective quality read — the thing we actually want. A stronger model
//  (the "judge", decoupled from the "subject" under test) scores output against
//  a rubric and, for escalation, makes the pairwise "is rung k more insistent
//  than k-1, same want?" call that the volume-knob hypothesis lives or dies on.
//
//  The judge is asked for STRICT JSON so verdicts parse and aggregate. Scores
//  are compared run-over-run in aggregate (means / pass-rates) — never as exact
//  text — because the judge, like any model, is non-deterministic.

import Foundation
@testable import claudeBlast

// MARK: - Verdict models

/// 1–5 rubric scores for a single generated sentence.
struct SentenceVerdict: Codable {
    let faithfulness: Int   // says what the tiles mean, nothing invented
    let firstPerson: Int    // framed as the child's own voice/request
    let stageFit: Int         // vocabulary/grammar for the target Brown's Stage
    let naturalness: Int    // sounds like a real person, not word salad
    let rationale: String

    /// Simple mean for at-a-glance aggregation.
    var mean: Double {
        Double(faithfulness + firstPerson + stageFit + naturalness) / 4.0
    }
}

/// Per-step pairwise call across an escalation ladder.
enum EscalationStepCall: String, Codable {
    case escalates   // rung k more insistent than k-1, same underlying want
    case flat        // about the same intensity
    case regresses   // less insistent, or drifted off the want
}

struct EscalationVerdict: Codable {
    /// One call per adjacent pair: calls[i] compares rung i+1 to rung i.
    let calls: [EscalationStepCall]
    let rationale: String

    var escalatesCount: Int { calls.filter { $0 == .escalates }.count }
    var regressesCount: Int { calls.filter { $0 == .regresses }.count }
    /// The volume knob "works" for this ladder when every step escalates.
    var allEscalate: Bool { !calls.isEmpty && calls.allSatisfy { $0 == .escalates } }
}

// MARK: - Judge

struct Judge {
    let client: EvalChatClient
    var brownsStage: BrownsStage = .twoThree

    /// Score one generated sentence against the rubric.
    func scoreSentence(tiles: [TileSelection], output: String) async throws -> SentenceVerdict {
        let tileList = tiles.map { "\($0.value) (\($0.wordClass))" }.joined(separator: ", ")
        let system = """
        You are evaluating an AAC (assistive communication) app that turns a non-verbal child's \
        selected word tiles into a spoken sentence. Score the GENERATED sentence on a 1–5 scale \
        (5 best) for each dimension:
        - faithfulness: conveys exactly what the tiles mean, invents no new intent.
        - firstPerson: framed as the child's own voice/request (self-centered is correct here).
        - ststageFit: vocabulary and grammar suit a child \(brownsStage.promptDescriptor()).
        - naturalness: sounds like a real person, not concatenated words or echoed tile list.
        Respond with STRICT JSON only, no prose: \
        {"faithfulness":N,"firstPerson":N,"stageFit":N,"naturalness":N,"rationale":"one short sentence"}
        """
        let user = "Tiles: \(tileList)\nGenerated sentence: \"\(output)\""
        let raw = try await client.complete(
            [EvalChatMessage(role: "system", content: system),
             EvalChatMessage(role: "user", content: user)],
            maxTokens: 250)
        return try decodeJSON(SentenceVerdict.self, from: raw)
    }

    /// Make the pairwise insistence calls across an escalation ladder.
    func scoreEscalation(tiles: [TileSelection], ladder: [String]) async throws -> EscalationVerdict {
        let tileList = tiles.map(\.value).joined(separator: ", ")
        let rungs = ladder.enumerated()
            .map { "[\($0.offset)] \"\($0.element)\"" }
            .joined(separator: "\n")
        let pairCount = max(ladder.count - 1, 0)
        let system = """
        You are evaluating escalation in an AAC app. A non-verbal child repeats the SAME word \
        selection to insist harder — repetition is their volume knob. Below is a ladder of \
        sentences generated for the same tiles, in order (rung 0 = first/calmest). For each \
        adjacent pair (rung i+1 vs rung i), judge whether intensity/insistence INCREASES while \
        staying on the same underlying want:
        - "escalates": rung i+1 is more insistent than rung i, same want.
        - "flat": about the same intensity.
        - "regresses": less insistent, or drifts to a different want.
        There are \(pairCount) pairs. Respond with STRICT JSON only: \
        {"calls":["escalates"|"flat"|"regresses", ...],"rationale":"one short sentence"} \
        with exactly \(pairCount) entries in calls.
        """
        let user = "Tiles: \(tileList)\nLadder:\n\(rungs)"
        let raw = try await client.complete(
            [EvalChatMessage(role: "system", content: system),
             EvalChatMessage(role: "user", content: user)],
            maxTokens: 400)
        return try decodeJSON(EscalationVerdict.self, from: raw)
    }

    // MARK: - Helpers

    /// Decode JSON the judge returned, tolerating ```json fences / surrounding
    /// prose by slicing to the outermost braces (same trick as GeneratedScene).
    func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let jsonText: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            jsonText = String(raw[start...end])
        } else {
            jsonText = raw
        }
        guard let data = jsonText.data(using: .utf8) else {
            throw EvalHarnessError.decode("judge output not UTF-8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EvalHarnessError.decode("judge JSON: \(error.localizedDescription) — raw: \(raw.prefix(160))")
        }
    }
}
