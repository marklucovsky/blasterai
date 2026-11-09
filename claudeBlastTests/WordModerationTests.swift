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

    /// The rubric's class rides along with its rating. Only a class a
    /// caregiver could choose is kept: an invented one ("clothes") or the
    /// no-meaning `unspecified` is dropped, so the word keeps its ?.
    @Test func parseClassesKeepsOnlyAssignableClasses() {
        let content = """
        {"ratings": {"pony": "appropriate"}, "classes": {"pony": "Animal", "sock": "clothes",         "zorb": "unspecified", "hello": "social"}}
        """
        let c = WordModerationService.parseClasses(content, words: ["pony", "sock", "zorb", "hello", "missing"])
        #expect(c == ["pony": "animal", "hello": "social"])
        #expect(WordModerationService.parseClasses(#"{"ratings": {}}"#, words: ["pony"]).isEmpty)
    }

    /// The rubric is told which classes it may give, and never `unspecified`.
    @Test func theRubricOffersTheAssignableClasses() throws {
        let body = WordModerationService.rubricRequestBody(words: ["pony"])
        let messages = try #require(body["messages"] as? [[String: String]])
        let system = try #require(messages.first?["content"])
        #expect(system.contains(VocabularyClasses.assignableList))
        #expect(!system.contains("unspecified"))
        #expect(!system.contains("{{"))
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

// MARK: - When a tier could not run
//
// The hole these cover: an exhausted key made tier 3 throw, `try?` swallowed it,
// every word kept tier 1's `.allowed` default, and the Add-Tiles path stamped it
// approved — recording "checked and fine" for a word nothing had checked. Tier 3
// is the only tier that catches weapons, drugs, alcohol, gambling and adult
// themes, so what sailed through was exactly what it exists to stop.

@Suite struct ModerationUnavailableTests {

    private func http(_ status: Int, _ body: String) -> Error {
        OpenAIError.httpError(statusCode: status, body: body)
    }

    /// The reason is caregiver-facing, so "out of credit" must not surface as
    /// "the service could not be reached" — one is a bill, the other is a tunnel,
    /// and they send someone looking in different places.
    @Test func exhaustionReadsAsCredit() {
        let body = #"{"error":{"type":"insufficient_quota","code":"project_spend_limit_exceeded"}}"#
        #expect(WordModerationService.unavailableReason(http(429, body)) == "the key is out of credit")
    }

    @Test func networkFailureReadsAsUnreachable() {
        #expect(WordModerationService.unavailableReason(URLError(.timedOut))
                == "the review service could not be reached")
    }

    @Test func rejectedKeyReadsAsRefused() {
        #expect(WordModerationService.unavailableReason(http(401, "")) == "the key was refused")
    }

    /// The core rule. A word nothing objected to is not a word something cleared.
    @Test func uncheckedWordsAreDowngraded() {
        let out = WordModerationService.downgradingUnchecked(
            ["beer": .allowed, "apple": .allowed],
            among: ["beer", "apple"],
            reason: "the key is out of credit")
        #expect(out["beer"] == .unreviewed(reason: "the key is out of credit"))
        #expect(out["apple"] == .unreviewed(reason: "the key is out of credit"))
    }

    /// A partial outage must not discard the judgements that did land — tier 2
    /// can block while tier 3 is unreachable, and that block still stands.
    @Test func realVerdictsSurviveAnOutage() {
        let out = WordModerationService.downgradingUnchecked(
            ["porn": .blocked(reason: "policy: sexual"),
             "penis": .flagged(reason: "sensitive"),
             "beer": .allowed],
            among: ["porn", "penis", "beer"],
            reason: "the key is out of credit")
        #expect(out["porn"] == .blocked(reason: "policy: sexual"))
        #expect(out["penis"] == .flagged(reason: "sensitive"))
        #expect(out["beer"]?.isUnreviewed == true)
    }

    /// Both mean "a human looks before the child does", which is the only
    /// question any consumer actually asks.
    @Test func unreviewedNeedsACaregiverJustLikeFlagged() {
        #expect(WordVerdict.unreviewed(reason: "x").needsCaregiver)
        #expect(WordVerdict.flagged(reason: "x").needsCaregiver)
        #expect(!WordVerdict.allowed.needsCaregiver)
        #expect(!WordVerdict.blocked(reason: "x").needsCaregiver)
    }

    /// The consequence that made this a safety bug rather than a cosmetic one:
    /// the word must not come out of the Add-Tiles path visible to the child.
    @MainActor
    @Test func anUncheckedWordIsHiddenFromTheChild() throws {
        let context = TestStore.freshContainer().mainContext
        let tile = TileModel(key: "beer", wordClass: "drinks")
        context.insert(tile)

        // What `reviewTiles` does with an unreviewed verdict, asserted through
        // the tile's own transition rather than by re-running the audit — the
        // tiers are not injectable, so the network half cannot be faked here.
        tile.flagForReview()

        #expect(tile.needsReview)
        #expect(tile.isHiddenFromChild)
        #expect(!tile.isRetired)   // held for review, not hidden as if judged
    }

    /// Catch-up picks the page's words with no class, once each, and leaves
    /// hidden and system words alone.
    @MainActor
    @Test func catchUpTakesOnlyThePagesUnclassedWords() {
        let zorb = TileModel(key: "zorb", wordClass: VocabularyClasses.unspecified)
        let pony = TileModel(key: "pony", wordClass: "animal")
        let gone = TileModel(key: "gone", wordClass: VocabularyClasses.unspecified)
        gone.retire()
        let lookup = ["zorb": zorb, "pony": pony, "gone": gone]
        let entries = ["zorb", "pony", "gone", "zorb", "missing"].map {
            TileEntry(key: $0)
        }
        #expect(WordModerationService.catchUpCandidates(entries, lookup: lookup).map(\.key) == ["zorb"])
    }

    /// A word caught up may already be on the child's board: it is flagged for
    /// the caregiver, never retired, and an allowed verdict never un-hides.
    @MainActor
    @Test func catchUpFlagsButNeverHides() {
        let blocked = TileModel(key: "sword", wordClass: VocabularyClasses.unspecified)
        let fine = TileModel(key: "zorb", wordClass: VocabularyClasses.unspecified)
        let chosen = TileModel(key: "pony", wordClass: "toy")
        var review = WordModerationService.Review()
        review.verdicts = ["sword": .blocked(reason: "weapon"), "zorb": .allowed, "pony": .allowed]
        review.classes = ["sword": "object", "zorb": "describe", "pony": "animal"]

        WordModerationService.applyCatchUp(review, to: [blocked, fine, chosen])

        #expect(!blocked.isRetired)
        #expect(blocked.needsReview)
        #expect(blocked.wordClass == "object")
        #expect(!fine.needsReview)
        #expect(fine.wordClass == "describe")
        #expect(chosen.wordClass == "toy")   // a class someone chose is kept
    }

    /// A class audit in the bundle reaches a store seeded before it; a word a
    /// caregiver added keeps the class they gave it.
    @MainActor
    @Test func bundledClassesReachExistingSystemWords() {
        let context = TestStore.freshContainer().mainContext
        let next = TileModel(key: "next", wordClass: "describe"); next.isSystem = true
        let mine = TileModel(key: "zorb", wordClass: "toy")
        context.insert(next); context.insert(mine)
        let vocab = [TileModelCodable(key: "next", wordClass: "time"),
                     TileModelCodable(key: "zorb", wordClass: "animal")]

        #expect(BootstrapLoader.applyBundledClasses(vocab, context: context) == 1)
        #expect(next.wordClass == "time")
        #expect(mine.wordClass == "toy")
    }
}
