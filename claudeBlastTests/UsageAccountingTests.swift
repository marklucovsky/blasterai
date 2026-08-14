// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageAccountingTests.swift
//  claudeBlastTests
//
//  2A: token/cost accounting — price arithmetic and ledger aggregation.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct UsageAccountingTests {

    // MARK: - Price arithmetic

    /// A rate quoted per 1M tokens, applied to N tokens, expressed in
    /// micro-dollars, is exactly `N × rate`. 700 × $0.15/M = 105 micros.
    @Test func chatCostIsTokensTimesRate() {
        let cost = ModelPricing.costMicros(
            model: ModelID.sentence,
            promptTokens: 700,
            completionTokens: 20
        )
        // 700 × 0.15 = 105, 20 × 0.60 = 12
        #expect(cost == 117)
    }

    /// The whole point of the cache: cached prompt tokens bill at half rate, and
    /// must not ALSO be charged at the full input rate.
    @Test func cachedPromptTokensAreDiscountedNotDoubleCharged() {
        let allFresh = ModelPricing.costMicros(
            model: ModelID.sentence, promptTokens: 1000, completionTokens: 0)
        let halfCached = ModelPricing.costMicros(
            model: ModelID.sentence, promptTokens: 1000,
            cachedPromptTokens: 500, completionTokens: 0)

        #expect(allFresh == 150)        // 1000 × 0.15
        #expect(halfCached == 113)      // 500 × 0.15 + 500 × 0.075 = 112.5 → 113
    }

    /// Image output is the expensive rate, and image input bills higher than
    /// text input. A medium 1024² generation lands around 4–5 cents.
    @Test func imageCostUsesImageRates() {
        let cost = ModelPricing.costMicros(
            model: ModelID.image,
            promptTokens: 120,
            imageInputTokens: 0,
            completionTokens: 1056
        )
        // 120 × 5 = 600, 1056 × 40 = 42_240
        #expect(cost == 42_840)
        #expect(Double(cost!) / 1_000_000 > 0.04)
    }

    @Test func imageInputBillsAboveTextInput() {
        let textOnly = ModelPricing.costMicros(
            model: ModelID.image, promptTokens: 1000, completionTokens: 0)
        let halfImage = ModelPricing.costMicros(
            model: ModelID.image, promptTokens: 1000,
            imageInputTokens: 500, completionTokens: 0)
        #expect(textOnly == 5_000)      // 1000 × 5
        #expect(halfImage == 7_500)     // 500 × 5 + 500 × 10
    }

    @Test func moderationIsFree() {
        #expect(ModelPricing.costMicros(
            model: ModelID.moderation, promptTokens: 500, completionTokens: 0) == 0)
    }

    /// An unpriced model must degrade to "no cost recorded", never a guess. A
    /// visible zero shows up as an anomaly against OpenAI's dashboard; an
    /// invented number silently corrupts the claim this system exists to verify.
    @Test func unknownModelReturnsNilRatherThanGuessing() {
        #expect(ModelPricing.costMicros(
            model: "gpt-9-imaginary", promptTokens: 1000, completionTokens: 100) == nil)
        #expect(ModelPricing.isPriced("gpt-9-imaginary") == false)
        #expect(ModelPricing.isPriced(ModelID.sentence))
    }

    /// **Regression, found on the first real device run.** OpenAI echoes the
    /// resolved *snapshot* id, not the alias requested: asking for `gpt-4o-mini`
    /// returns `gpt-4o-mini-2024-07-18`. Exact-match lookup missed every chat
    /// call and priced it at zero — the whole report read $0.00 for sentences
    /// while images (whose `gpt-image-1` id carries no date) priced correctly.
    @Test func datedSnapshotIDsResolveToTheirBaseModel() {
        let dated = "gpt-4o-mini-2024-07-18"
        #expect(ModelPricing.isPriced(dated))
        #expect(ModelPricing.costMicros(model: dated, promptTokens: 700, completionTokens: 20) == 117)
        // Same answer as the undated alias — that's the whole point.
        #expect(ModelPricing.costMicros(model: dated, promptTokens: 700, completionTokens: 20)
                == ModelPricing.costMicros(model: ModelID.sentence, promptTokens: 700, completionTokens: 20))
    }

    /// Prefix resolution must take the LONGEST match, or a future `gpt-4o` entry
    /// would capture `gpt-4o-mini-*` snapshots and price them at the wrong rate.
    @Test func longestPrefixWinsSoCheaperModelsAreNotOverpriced() {
        #expect(ModelPricing.resolveRates(for: "gpt-4o-mini-2099-01-01")?.textInputPerM == 0.15)
        // An unrelated id still resolves to nothing rather than a near neighbour.
        #expect(ModelPricing.resolveRates(for: "claude-something") == nil)
        #expect(ModelPricing.resolveRates(for: "gpt-image-1-2026-05-01")?.outputPerM == 40.00)
    }

    /// The cache key and the request body must never name different models.
    @Test func cacheKeyPolicyUsesTheRegistryModel() {
        #expect(CacheKeyPolicy.modelID == ModelID.sentence)
        #expect(ModelPricing.isPriced(CacheKeyPolicy.modelID))
    }

    // MARK: - Ledger aggregation

    private func event(_ cause: UsageCause,
                       cost: Int,
                       prompt: Int = 0,
                       completion: Int = 0,
                       images: Int = 0,
                       count: Int = 1,
                       at date: Date = .now) -> APIUsageEvent {
        APIUsageEvent(cause: cause, model: ModelID.sentence,
                      promptTokens: prompt, completionTokens: completion,
                      imageCount: images, costMicros: cost,
                      timestamp: date, count: count)
    }

    /// The subtlety that cuts both ways: `calls` sums `count` because a
    /// compacted row stands for many calls, but tokens and cost are summed
    /// DIRECTLY because a compacted row already holds the period total.
    /// Multiplying those by `count` would inflate them.
    @Test func aggregateRowsSumCountButNotTokensTwice() {
        let events = [
            event(.sentenceGenerate, cost: 100, prompt: 700, completion: 20),
            event(.sentenceGenerate, cost: 5_000, prompt: 35_000, completion: 1_000, count: 50),
        ]
        let s = UsageLedger.summarize(events)

        #expect(s.calls == 51)              // 1 + 50
        #expect(s.promptTokens == 35_700)   // summed directly, NOT × 50
        #expect(s.costMicros == 5_100)
        #expect(s.totalTokens == 36_720)
    }

    @Test func byCauseOrdersMostExpensiveFirst() {
        let rows = UsageLedger.byCause([
            event(.sentenceGenerate, cost: 120),
            event(.tileImageGenerate, cost: 42_000, images: 1),
            event(.wordAuditScreen, cost: 0),
        ])
        #expect(rows.first?.cause == .tileImageGenerate)
        #expect(rows.last?.cause == .wordAuditScreen)
    }

    /// The finding the GTM claim turns on: art dwarfs talking.
    @Test func speechAndAuthoringSplitApart() {
        let split = UsageLedger.speechVsAuthoring([
            event(.sentenceGenerate, cost: 120),
            event(.sentenceEscalate, cost: 130),
            event(.sentenceRefine, cost: 140),
            event(.tileImageGenerate, cost: 42_000, images: 1),
            event(.sceneGenerate, cost: 900),
        ])
        #expect(split.speech.calls == 3)
        #expect(split.speech.costMicros == 390)
        #expect(split.authoring.costMicros == 42_900)
        // One image outweighs every sentence in the set, by two orders of magnitude.
        #expect(split.authoring.costMicros > split.speech.costMicros * 100)
    }

    @Test func monthFilterExcludesPriorMonths() {
        let now = Date()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let events = [event(.sentenceGenerate, cost: 100, at: now),
                      event(.sentenceGenerate, cost: 999, at: lastMonth)]

        let month = UsageLedger.inMonth(events, containing: now)
        #expect(month.count == 1)
        #expect(UsageLedger.summarize(month).costMicros == 100)
    }

    @Test func cacheSavingsUseObservedSentenceCostAndNeedABasis() {
        let events = [event(.sentenceGenerate, cost: 100),
                      event(.sentenceGenerate, cost: 200)]
        // mean 150 micros × 10 hits
        #expect(UsageLedger.estimatedCacheSavingsMicros(events: events, cacheHits: 10) == 1_500)
        // No hits, or no generated sentence to average, means no basis to estimate.
        #expect(UsageLedger.estimatedCacheSavingsMicros(events: events, cacheHits: 0) == 0)
        #expect(UsageLedger.estimatedCacheSavingsMicros(events: [], cacheHits: 10) == 0)
    }

    // MARK: - Formatting

    /// "$0.00" reads as "nothing was recorded" when the truth is "this costs
    /// almost nothing" — which is the actual finding and must not round away.
    @Test func subCentCostsKeepTheirPrecision() {
        #expect(UsageLedger.formatUSD(micros: 120) == "$0.0001")
        #expect(UsageLedger.formatUSD(micros: 0) == "$0.00")
        #expect(UsageLedger.formatUSD(micros: 42_000) == "$0.04")
        #expect(UsageLedger.formatUSD(micros: 1_400_000) == "$1.40")
    }

    /// A real word-review call cost 42 micros and rendered as "$0.0000" — one row
    /// below a "free" moderations call. Two different facts that looked the same.
    @Test func tinyButRealCostsShowAsABoundNotARoundedZero() {
        #expect(UsageLedger.formatUSD(micros: 42) == "<$0.0001")
        #expect(UsageLedger.formatUSD(micros: 99) == "<$0.0001")
        // At and above the threshold the real figure is meaningful again.
        #expect(UsageLedger.formatUSD(micros: 100) == "$0.0001")
    }

    @Test func tokenCountsAbbreviate() {
        #expect(UsageLedger.formatTokens(999) == "999")
        #expect(UsageLedger.formatTokens(12_400) == "12.4K")
        #expect(UsageLedger.formatTokens(2_000_000) == "2.0M")
    }

    /// A free call and an unpriceable call must not look alike. `/v1/moderations`
    /// genuinely costs nothing, so `$0.00` is true; a chat call that burned 3.2K
    /// tokens and shows `$0.00` is a row we failed to price, and saying "free"
    /// there is a false claim about real money.
    @Test func unpricedIsDistinguishedFromGenuinelyFree() {
        let free = APIUsageEvent(cause: .wordAuditScreen, model: ModelID.moderation,
                                 promptTokens: 0, completionTokens: 0, costMicros: 0)
        #expect(!free.isUnpriced)
        #expect(free.isFreeCall)

        // /v1/models names no model at all, so a price lookup can say nothing
        // about it — free-ness has to come from the cause, not the table.
        let keyCheck = APIUsageEvent(cause: .keyValidation, model: "", costMicros: 0)
        #expect(keyCheck.isFreeCall)
        #expect(!keyCheck.isUnpriced)

        let unpriceable = APIUsageEvent(cause: .sceneGenerate, model: "gpt-4o-mini",
                                        promptTokens: 2_500, completionTokens: 700,
                                        costMicros: 0)
        // Stored zero cost with real tokens spent — the pre-fix rows on device.
        unpriceable.model = "some-model-we-had-no-price-for"
        #expect(unpriceable.isUnpriced)

        let priced = APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence,
                                   promptTokens: 700, completionTokens: 20, costMicros: 117)
        #expect(!priced.isUnpriced)
    }

    /// A total containing unpriceable calls must admit it's a floor rather than
    /// quietly understating — history is never re-priced, so those rows stay $0.
    @Test func totalsFlagWhenTheyUnderstate() {
        let unpriceable = APIUsageEvent(cause: .sceneGenerate, model: "unknown-model",
                                        promptTokens: 2_500, completionTokens: 700, costMicros: 0)
        let priced = APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence,
                                   promptTokens: 700, completionTokens: 20, costMicros: 117)

        let mixed = UsageLedger.summarize([unpriceable, priced])
        #expect(mixed.unpricedCalls == 1)
        #expect(mixed.hasUnpriced)
        #expect(UsageLedger.formatCost(mixed) == "~$0.0001")

        let allUnpriced = UsageLedger.summarize([unpriceable])
        #expect(UsageLedger.formatCost(allUnpriced) == "unpriced")

        let clean = UsageLedger.summarize([priced])
        #expect(!clean.hasUnpriced)
        #expect(UsageLedger.formatCost(clean) == "$0.0001")
    }

    /// The three zeros must read as three different statements. "$0.00" claims a
    /// cost was computed and came to nothing; a free endpoint never billed at
    /// all; an unpriced row billed and we don't know what it cost.
    @Test func theThreeKindsOfZeroReadDifferently() {
        let freeSummary = UsageLedger.summarize([
            APIUsageEvent(cause: .wordAuditScreen, model: ModelID.moderation, costMicros: 0)
        ])
        #expect(UsageLedger.formatCost(freeSummary, isFreeCause: true) == "free")

        let unpricedSummary = UsageLedger.summarize([
            APIUsageEvent(cause: .sceneGenerate, model: "unknown-model",
                          promptTokens: 2_500, completionTokens: 700, costMicros: 0)
        ])
        #expect(UsageLedger.formatCost(unpricedSummary) == "unpriced")

        // A billable call that genuinely rounds to nothing still shows a figure.
        let tiny = UsageLedger.summarize([
            APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence,
                          promptTokens: 10, completionTokens: 1, costMicros: 2)
        ])
        #expect(UsageLedger.formatCost(tiny) == "<$0.0001")
    }

    @Test func onlyNonBillingEndpointsAreFree() {
        #expect(UsageCause.wordAuditScreen.isFreeEndpoint)
        #expect(UsageCause.keyValidation.isFreeEndpoint)
        // The rubric costs money even though it sits beside the free screen.
        #expect(!UsageCause.wordAuditRubric.isFreeEndpoint)
        #expect(!UsageCause.sentenceGenerate.isFreeEndpoint)
        #expect(!UsageCause.tileImageGenerate.isFreeEndpoint)
    }

    @Test func countsArePluralizedCorrectly() {
        #expect(UsageLedger.pluralize(1, "call") == "1 call")
        #expect(UsageLedger.pluralize(0, "call") == "0 calls")
        #expect(UsageLedger.pluralize(27, "call") == "27 calls")
        #expect(UsageLedger.pluralize(1, "day") == "1 day")
    }

    // MARK: - Cause coverage

    /// Every cause needs a caregiver-facing label; a missing one would surface
    /// as a blank row in the report.
    @Test func everyCauseHasALabel() {
        for cause in UsageCause.allCases {
            #expect(!cause.label.isEmpty)
        }
    }

    @Test func onlySentenceCausesCountAsChildSpeech() {
        #expect(UsageCause.sentenceGenerate.isChildSpeech)
        #expect(UsageCause.sentenceEscalate.isChildSpeech)
        #expect(UsageCause.sentenceRefine.isChildSpeech)
        #expect(!UsageCause.tileImageGenerate.isChildSpeech)
        #expect(!UsageCause.sceneGenerate.isChildSpeech)
        #expect(!UsageCause.wordAuditRubric.isChildSpeech)
    }

    /// An unrecognized raw value must degrade, not trap — a row written by a
    /// newer build has to remain readable.
    @Test func unknownCauseRawDegradesGracefully() {
        let e = APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence)
        e.causeRaw = "somethingFromTheFuture"
        #expect(e.cause == .unknown)
        #expect(e.cause.label == "Other")
    }
}
}
