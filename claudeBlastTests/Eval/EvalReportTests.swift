// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  EvalReportTests.swift
//  claudeBlastTests
//
//  Offline tests for the Tier-2 plumbing: judge-JSON decoding (incl. fenced /
//  prose-wrapped output) and the report rollup math. No network — these always
//  run in CI and guard the aggregation that the baseline comparison relies on.

import Testing
import Foundation
@testable import claudeBlast

struct EvalReportTests {

    private func judge() -> Judge {
        Judge(client: EvalChatClient(config: EvalModelConfig.judge(apiKey: "test")))
    }

    // MARK: - Judge JSON tolerance

    @Test func decodesPlainSentenceVerdict() throws {
        let raw = #"{"faithfulness":5,"firstPerson":4,"stageFit":5,"naturalness":4,"rationale":"good"}"#
        let v = try judge().decodeJSON(SentenceVerdict.self, from: raw)
        #expect(v.faithfulness == 5)
        #expect(v.mean == 4.5)
    }

    @Test func decodesFencedAndProseWrappedJSON() throws {
        let raw = """
        Here is my assessment:
        ```json
        {"calls":["escalates","flat","regresses"],"rationale":"mixed"}
        ```
        """
        let v = try judge().decodeJSON(EscalationVerdict.self, from: raw)
        #expect(v.calls.count == 3)
        #expect(v.escalatesCount == 1)
        #expect(v.regressesCount == 1)
        #expect(!v.allEscalate)
    }

    @Test func allEscalateLadder() throws {
        let raw = #"{"calls":["escalates","escalates"],"rationale":"rising"}"#
        let v = try judge().decodeJSON(EscalationVerdict.self, from: raw)
        #expect(v.allEscalate)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try judge().decodeJSON(SentenceVerdict.self, from: "not json at all")
        }
    }

    // MARK: - Report rollups

    private func sampleReport() -> EvalReport {
        EvalReport(
            subjectModel: "gpt-4o-mini",
            judgeModel: "gpt-4o",
            timestamp: "2026-06-20T00:00:00Z",
            sentences: [
                SentenceCaseResult(id: "a", output: "Mom, I'm hungry.", tier1Passed: true, tier1Issues: [],
                                   judge: SentenceVerdict(faithfulness: 5, firstPerson: 5, stageFit: 5, naturalness: 5, rationale: "")),
                SentenceCaseResult(id: "b", output: "hungry (feeling)", tier1Passed: false, tier1Issues: ["wordClass leaked"],
                                   judge: SentenceVerdict(faithfulness: 2, firstPerson: 2, stageFit: 3, naturalness: 1, rationale: "")),
            ],
            escalations: [
                EscalationCaseResult(id: "x", ladder: ["a", "b", "c"], intensities: [1, 3, 6], tier1Passed: true, tier1Issues: [],
                                     judge: EscalationVerdict(calls: [.escalates, .escalates], rationale: "")),
                EscalationCaseResult(id: "y", ladder: ["a", "b"], intensities: [4, 2], tier1Passed: false, tier1Issues: ["regression"],
                                     judge: EscalationVerdict(calls: [.regresses], rationale: "")),
            ]
        )
    }

    @Test func rollupsComputeCorrectly() {
        let r = sampleReport()
        #expect(r.sentenceTier1PassRate == 0.5)
        // sentence judge means: (20/4=5) and (8/4=2) → avg 3.5
        #expect(r.sentenceMeanScore == 3.5)
        // escalation calls: escalates,escalates,regresses → 2/3 escalate
        #expect(abs((r.escalationStepEscalateRate ?? 0) - (2.0 / 3.0)) < 0.0001)
        #expect(r.escalationRegressions == 1)
        #expect(r.escalationTier1PassRate == 0.5)
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let r = sampleReport()
        let data = try EvalReportWriter.json(r)
        let decoded = try JSONDecoder().decode(EvalReport.self, from: data)
        #expect(decoded.subjectModel == r.subjectModel)
        #expect(decoded.escalations.count == 2)
        #expect(decoded.escalationRegressions == 1)
    }

    @Test func summaryLineIsReadable() {
        let line = sampleReport().summaryLine
        #expect(line.contains("subject=gpt-4o-mini"))
        #expect(line.contains("judge=gpt-4o"))
    }
}
