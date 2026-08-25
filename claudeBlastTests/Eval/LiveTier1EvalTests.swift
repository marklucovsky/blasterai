// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LiveTier1EvalTests.swift
//  claudeBlastTests
//
//  End-to-end Tier-1 eval against the real subject model. OPT-IN ONLY: skipped
//  unless RUN_LIVE_EVAL=1 and a key are present, so normal test/CI runs make no
//  network calls. This proves the harness plumbing (real prompts → subject model
//  → Tier-1 scoring) before the Tier-2 judge lands in A2, and gives an early
//  read on whether the system is grossly broken (e.g. wordClass leakage).

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct LiveTier1EvalTests {

    private var enabled: Bool { EvalEnv.liveEnabled && EvalEnv.apiKey != nil }

    private func makeSubjectRunner() -> SubjectRunner {
        let cfg = EvalModelConfig.subject(apiKey: EvalEnv.apiKey ?? "", model: EvalEnv.subjectModel)
        return SubjectRunner(client: EvalChatClient(config: cfg))
    }

    @Test(.enabled(if: EvalEnv.liveEnabled && EvalEnv.apiKey != nil))
    func liveSentenceSanity() async throws {
        let runner = makeSubjectRunner()
        var failures: [String] = []

        for c in EvalCases.sentences {
            let text = try await runner.generate(tiles: c.tiles)
            let score = Tier1.scoreSentence(text, tiles: c.tiles, stage: runner.brownsStage)
            let line = "[sentence] \(c.id): \"\(text)\"  \(score.passed ? "OK" : "FAIL \(score.issues)")"
            print(line)
            EvalEnv.appendTranscript(line)
            if !score.passed { failures.append("\(c.id): \(score.issues.joined(separator: "; "))") }
        }

        #expect(failures.isEmpty, Comment(rawValue: "Tier-1 sentence failures:\n" + failures.joined(separator: "\n")))
    }

    @Test(.enabled(if: EvalEnv.liveEnabled && EvalEnv.apiKey != nil))
    func liveEscalationSanity() async throws {
        let runner = makeSubjectRunner()
        var failures: [String] = []
        // Every ladder, pass or fail, folded into the expectation message.
        // `print` from a test does not survive into the .xcresult bundle, so a
        // CLI run could see *that* a ladder regressed but never *what it said* —
        // which is the only thing that tells you whether the wording is any
        // good. Escalation quality is a judgement about sentences, so the
        // sentences have to reach the reader.
        var transcript: [String] = []

        for c in EvalCases.escalations {
            let ladder = try await runner.generateEscalationLadder(tiles: c.tiles, extraSteps: c.extraSteps)
            let score = Tier1.scoreEscalation(ladder, tiles: c.tiles, stage: runner.brownsStage)
            transcript.append("\(c.id) [\(runner.brownsStage.label)] intensities=\(score.intensities)")
            for (i, rung) in ladder.enumerated() {
                transcript.append("    [\(i)] \"\(rung)\"")
            }
            if !score.passed {
                transcript.append("    -> FAIL \(score.issues)")
                failures.append("\(c.id): \(score.issues.joined(separator: "; "))")
            }
        }
        print(transcript.joined(separator: "\n"))
        EvalEnv.appendTranscript("=== escalation ===\n" + transcript.joined(separator: "\n"))

        // Tier 1 is a floor: a regression or flat ramp here is a real signal that
        // escalation is broken — exactly the failure mode this milestone targets.
        #expect(failures.isEmpty, Comment(rawValue:
            "Tier-1 escalation failures:\n" + failures.joined(separator: "\n")
            + "\n\nLadders:\n" + transcript.joined(separator: "\n")))
    }
}
