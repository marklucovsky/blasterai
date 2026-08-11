// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordModerationTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

@Suite struct WordModerationTests {

    /// `reviewTiles` (the Add-Tiles path) stamps persistent review state. Uses only
    /// LOCAL-tier words (blocklist/flag-list) so the audit resolves offline — no
    /// network — keeping the test deterministic.
    @MainActor
    @Test func reviewTilesStampsLocalVerdicts() async throws {
        let context = TestStore.freshContainer().mainContext
        let blocked = TileModel(key: "porn", wordClass: "object")   // blocklist → blocked
        let flagged = TileModel(key: "penis", wordClass: "body")    // flag-list → flagged
        context.insert(blocked); context.insert(flagged)

        await WordModerationService.reviewTiles([blocked, flagged], apiKey: "test-key", context: context)

        #expect(blocked.isRetired == true)
        #expect(!blocked.retiredReason.isEmpty)
        #expect(blocked.needsReview == false)
        #expect(flagged.needsReview == true)
        #expect(flagged.isRetired == false)
    }

    // Offline (empty key) → only the local lists run; everything else is deferred
    // to the online tiers (moderations + rubric).
    @Test func offlineAuditBlocksAndFlagsLocalLists() async {
        let svc = WordModerationService(apiKey: "")
        let v = await svc.audit(["Porn", "penis", "beer", "apple"])
        #expect(v["Porn"]?.isBlocked == true)     // blocklist, case-insensitive
        #expect(v["penis"]?.isFlagged == true)    // sensitive → caregiver choice, not blocked
        #expect(v["beer"] == .allowed)            // needs the online rubric; offline stays allowed
        #expect(v["apple"] == .allowed)
    }

    @Test func parseRatingsMapsRubricJSON() {
        let content = """
        Sure! {"ratings": {"gun": "inappropriate", "knife": "questionable", "apple": "appropriate"}}
        """
        let r = WordModerationService.parseRatings(content, words: ["gun", "knife", "apple", "missing"])
        #expect(r["gun"] == .inappropriate)
        #expect(r["knife"] == .questionable)
        #expect(r["apple"] == .appropriate)
        #expect(r["missing"] == nil)              // absent → caller treats as appropriate
    }

    @Test func parseRatingsToleratesGarbage() {
        #expect(WordModerationService.parseRatings("no json here", words: ["x"]).isEmpty)
        #expect(WordModerationService.parseRatings(#"{"nope": 1}"#, words: ["x"]).isEmpty)
    }

    @Test func parseFlagsMapsFlaggedCategoriesByInputOrder() {
        let json = """
        {"results":[
          {"flagged":true,"categories":{"sexual":true,"violence":false,"hate":true}},
          {"flagged":false,"categories":{"sexual":false}},
          {"flagged":true,"categories":{"violence":true}}
        ]}
        """.data(using: .utf8)!
        let flags = WordModerationService.parseFlags(data: json, words: ["w0", "w1", "w2"])
        #expect(flags["w0"]?.sorted() == ["hate", "sexual"])
        #expect(flags["w1"] == nil)
        #expect(flags["w2"] == ["violence"])
    }
}
