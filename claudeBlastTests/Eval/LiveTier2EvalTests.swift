// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LiveTier2EvalTests.swift
//  claudeBlastTests
//
//  Full end-to-end quality run: subject generation → Tier-1 floor → Tier-2 judge,
//  rolled into an EvalReport and written to disk as the baseline. OPT-IN ONLY
//  (RUN_LIVE_EVAL=1 + key), since it makes many API calls against both the
//  subject and judge models.
//
//  This is the A3 substrate: capture a baseline, change the escalation prompt,
//  re-run, and compare escalate-rate / regressions. It does not hard-assert a
//  quality bar (that's a judgment call to set once we see real numbers) — it
//  asserts the run completed and prints the rollup. Subject and judge models are
//  independent (EVAL_SUBJECT_MODEL / EVAL_JUDGE_MODEL).

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct LiveTier2EvalTests {

    @Test(.enabled(if: EvalEnv.liveEnabled && EvalEnv.apiKey != nil), .timeLimit(.minutes(10)))
    func captureQualityBaseline() async throws {
        let key = EvalEnv.apiKey ?? ""
        let subject = SubjectRunner(client: EvalChatClient(config: .subject(apiKey: key, model: EvalEnv.subjectModel)))
        let judge = Judge(client: EvalChatClient(config: .judge(apiKey: key, model: EvalEnv.judgeModel)))

        // Sentences: generate → Tier-1 → judge.
        var sentenceResults: [SentenceCaseResult] = []
        for c in EvalCases.sentences {
            let output = try await subject.generate(tiles: c.tiles)
            // Score at the stage the subject actually generated at.
            //
            // Without this the capture graded Stage II-III output against the
            // `.fourPlus` default, and `dad_help` failed as "a raw echo of the
            // tiles" — which is exactly what the echo rule was re-scoped to stop
            // saying. `LiveTier1EvalTests` already passes the stage; this one
            // was missed, so the Tier-2 capture has been marking a correct
            // Stage II-III answer wrong ever since stages landed.
            let tier1 = Tier1.scoreSentence(output, tiles: c.tiles, stage: subject.brownsStage)
            let verdict = try? await judge.scoreSentence(tiles: c.tiles, output: output)
            sentenceResults.append(SentenceCaseResult(
                id: c.id, output: output,
                tier1Passed: tier1.passed, tier1Issues: tier1.issues, judge: verdict))
            print("[eval/sentence] \(c.id): \"\(output)\" tier1=\(tier1.passed ? "OK" : "\(tier1.issues)") judge=\(verdict.map { String(format: "%.2f", $0.mean) } ?? "n/a")")
        }

        // Escalation: ladder → Tier-1 → pairwise judge. This is the priority signal.
        var escalationResults: [EscalationCaseResult] = []
        for c in EvalCases.escalations {
            let ladder = try await subject.generateEscalationLadder(tiles: c.tiles, extraSteps: c.extraSteps)
            let tier1 = Tier1.scoreEscalation(ladder, tiles: c.tiles)
            let verdict = try? await judge.scoreEscalation(tiles: c.tiles, ladder: ladder)
            escalationResults.append(EscalationCaseResult(
                id: c.id, ladder: ladder, intensities: tier1.intensities,
                tier1Passed: tier1.passed, tier1Issues: tier1.issues, judge: verdict))
            let calls = verdict?.calls.map(\.rawValue).joined(separator: ",") ?? "n/a"
            print("[eval/escalation] \(c.id) intensities=\(tier1.intensities) calls=[\(calls)]")
            for (i, rung) in ladder.enumerated() { print("    [\(i)] \"\(rung)\"") }
        }

        let report = EvalReport(
            subjectModel: EvalEnv.subjectModel,
            judgeModel: EvalEnv.judgeModel,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sentences: sentenceResults,
            escalations: escalationResults)

        let url = try EvalReportWriter.write(report, stem: report.timestamp.replacingOccurrences(of: ":", with: "-"))
        print("\n[eval] ===== BASELINE =====")
        print("[eval] \(report.summaryLine)")
        print("[eval] report written: \(url.path)\n")

        // Attach the artifacts to the test result so they survive out of the
        // simulator sandbox (export via `xcrun xcresulttool` / Xcode report nav).
        // print() to simulator stdout doesn't reach the host; attachments do.
        Attachment.record(try EvalReportWriter.json(report), named: "baseline.json")
        Attachment.record(report.summaryLine, named: "summary.txt")

        // The run completed with output for every case; quality thresholds are
        // set in A3 once we've seen real numbers.
        #expect(report.sentences.count == EvalCases.sentences.count)
        #expect(report.escalations.count == EvalCases.escalations.count)
        // Every case produced non-empty output (proves it ran live, not skipped).
        #expect(report.sentences.allSatisfy { !$0.output.isEmpty })
    }
}
