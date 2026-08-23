// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MetricCompactorTests.swift
//  claudeBlastTests
//
//  2C: folding usage history into monthly aggregates under a space budget.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct MetricCompactorTests {

    // MARK: - Fixtures

    /// A fixed "now" so month arithmetic is deterministic — mid-month, so the
    /// current month is genuinely partial and the detail floor has something to
    /// protect.
    static let now = Date(timeIntervalSince1970: 1_755_000_000)  // 2025-08-12

    /// `n` months before `now`, on `day` of that month.
    ///
    /// Built from components deliberately. `Calendar.date(bySetting:value:of:)`
    /// searches FORWARD for the next date matching the component, so from a
    /// mid-month base it silently rolls into the *following* month for any
    /// earlier day — which scattered a month's fixture rows across two months and
    /// made correct fold behaviour look like a bug.
    private func monthsAgo(_ n: Int, day: Int = 15) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: -n, to: Self.now)!
        var comps = cal.dateComponents([.year, .month], from: base)
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps)!
    }

    /// A budget small enough that any non-trivial store is "over", so folding
    /// actually runs. The production numbers are deliberately unreachable in a
    /// test — that is the point of them.
    private func tightPolicy(lowWaterBytes: Int64 = 100) -> MetricCompactor.Policy {
        MetricCompactor.Policy(budgetBytes: 200, highWaterBytes: 150,
                               lowWaterBytes: lowWaterBytes,
                               retainMonths: 6, keepDetailMonths: 2)
    }

    /// A policy whose low-water mark is exactly one row's worth of the store —
    /// "fold everything you are permitted to fold, and stop".
    ///
    /// Replaces an earlier `lowWaterBytes: 1` idiom that stopped meaning that.
    /// The compactor now sheds the *surplus* over the mark rather than deriving
    /// the whole file from its rows, so a one-byte target says something quite
    /// different: no SQLite file reaches one byte, so the target is unreachable,
    /// so the correct answer is to keep the history and report `floorHeld`. Every
    /// test using the old idiom would still have passed — while folding nothing
    /// and asserting against untouched data.
    ///
    /// Pricing the target at one row keeps the aggressive intent and stays
    /// reachable. Rounding up matters: integer division would put the mark a
    /// fraction below one row and make the target zero, which is the unreachable
    /// case again.
    private func foldEverything(_ ctx: ModelContext, measuredBytes: Int64) -> MetricCompactor.Policy {
        let metrics = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count
        let usage = ((try? ctx.fetch(FetchDescriptor<APIUsageEvent>())) ?? []).count
        let rows = Int64(max(1, metrics + usage))
        return MetricCompactor.Policy(budgetBytes: measuredBytes,
                                      highWaterBytes: measuredBytes / 2,
                                      lowWaterBytes: (measuredBytes + rows - 1) / rows,
                                      retainMonths: 6, keepDetailMonths: 2)
    }

    @discardableResult
    private func metric(_ ctx: ModelContext, subject: String, key: String,
                        type: MetricType = .selected, at date: Date) -> MetricEvent {
        let e = MetricEvent(subjectType: subject, subjectKey: key, eventType: type,
                            timestamp: date)
        ctx.insert(e)
        return e
    }

    @discardableResult
    private func usage(_ ctx: ModelContext, cause: UsageCause = .sentenceGenerate,
                       promptTokens: Int = 100, costMicros: Int = 42,
                       at date: Date) -> APIUsageEvent {
        let e = APIUsageEvent(cause: cause, model: ModelID.sentence,
                              endpoint: OpenAIEndpoint.chatCompletions,
                              promptTokens: promptTokens, completionTokens: 10,
                              costMicros: costMicros, timestamp: date)
        ctx.insert(e)
        return e
    }

    private func totals(_ ctx: ModelContext) -> (metricCount: Int, calls: Int, cost: Int, tokens: Int) {
        let m = (try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []
        let u = (try? ctx.fetch(FetchDescriptor<APIUsageEvent>())) ?? []
        return (m.reduce(0) { $0 + $1.count },
                u.reduce(0) { $0 + $1.count },
                u.reduce(0) { $0 + $1.costMicros },
                u.reduce(0) { $0 + $1.promptTokens })
    }

    // MARK: - The property everything else rests on

    /// **Totals must survive folding exactly.** Folding is allowed to be lossy
    /// about which rows contributed; it is never allowed to change what they add
    /// up to. If this fails, every number in the Activity tab is wrong after the
    /// first compaction, and silently so.
    @Test func foldingPreservesTotalsExactly() {
        let ctx = TestStore.freshContext()
        for i in 0..<40 {
            metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: 1 + i % 27))
            usage(ctx, promptTokens: 100 + i, costMicros: 10 + i,
                  at: monthsAgo(4, day: 1 + i % 27))
        }
        try? ctx.save()
        let before = totals(ctx)

        let outcome = MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                              policy: tightPolicy(), now: Self.now)

        #expect(outcome.rowsRemoved > 0, "nothing folded — the test proves nothing")
        let after = totals(ctx)
        #expect(after.metricCount == before.metricCount)
        #expect(after.calls == before.calls)
        #expect(after.cost == before.cost)
        #expect(after.tokens == before.tokens)
    }

    /// The whole design rests on doing nothing on a normal device. A fetch here
    /// would be a per-launch cost paid by every user forever.
    @Test func underTheHighWaterMarkNothingHappens() {
        let ctx = TestStore.freshContext()
        for i in 0..<20 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(5, day: 1 + i)) }
        try? ctx.save()
        let before = totals(ctx)
        let rowsBefore = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count

        // Measured size well under the high-water mark.
        let outcome = MetricCompactor.compact(
            context: ctx, measuredBytes: 10,
            policy: MetricCompactor.Policy(budgetBytes: 10_000, highWaterBytes: 8_000,
                                           lowWaterBytes: 6_000),
            now: Self.now)

        #expect(outcome.rowsRemoved == 0)
        #expect(outcome.monthsFolded == 0)
        #expect(((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count == rowsBefore)
        #expect(totals(ctx) == before)
    }

    // MARK: - Floors

    /// The detail floor protects the OpenAI reconciliation window: the cost
    /// export covers roughly a month, so the current and previous calendar months
    /// must keep per-call rows or the app's figures stop being checkable against
    /// the bill.
    @Test func recentMonthsKeepPerCallDetail() {
        let ctx = TestStore.freshContext()
        for i in 0..<30 {
            usage(ctx, at: monthsAgo(0, day: 1 + i % 11))   // current month
            usage(ctx, at: monthsAgo(1, day: 1 + i % 27))   // previous month
        }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000),
                                now: Self.now)

        let rows = (try? ctx.fetch(FetchDescriptor<APIUsageEvent>())) ?? []
        #expect(rows.count == 60, "rows inside the detail floor were folded")
        #expect(rows.allSatisfy { !$0.isAggregate })
    }

    /// The coverage floor is absolute: six months of history is never deleted to
    /// satisfy the budget. Being over budget is reported instead.
    @Test func theCoverageFloorHoldsAndSaysSo() {
        let ctx = TestStore.freshContext()
        // Everything inside the retention window, all identical so folding
        // collapses it as far as it possibly can.
        for month in 2...5 {
            for day in 1...20 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(month, day: day)) }
        }
        try? ctx.save()
        let before = totals(ctx)

        // A target no amount of permitted work can reach.
        let outcome = MetricCompactor.compact(context: ctx, measuredBytes: 10_000,
                                              policy: foldEverything(ctx, measuredBytes: 10_000),
                                              now: Self.now)

        #expect(outcome.floorHeld, "should report that it stopped rather than breaching the floor")
        #expect(outcome.monthsDeleted == 0)
        #expect(totals(ctx).metricCount == before.metricCount, "history was destroyed")
    }

    /// Beyond the coverage floor, deletion is permitted — but only after folding
    /// has already been tried, and only oldest-first.
    @Test func historyBeyondTheFloorIsDeletedOldestFirst() {
        let ctx = TestStore.freshContext()
        for day in 1...20 { metric(ctx, subject: "tile", key: "old", at: monthsAgo(9, day: day)) }
        for day in 1...20 { metric(ctx, subject: "tile", key: "recent", at: monthsAgo(3, day: day)) }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 10_000,
                                policy: foldEverything(ctx, measuredBytes: 10_000), now: Self.now)

        let keys = Set((((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? [])).map(\.subjectKey))
        #expect(!keys.contains("old"), "history beyond the coverage floor should be gone")
        #expect(keys.contains("recent"), "history inside the coverage floor was deleted")
    }

    // MARK: - Fold keys

    /// Rows that differ in anything summable-meaningless must not merge.
    @Test func rowsWithDifferentFoldKeysStaySeparate() {
        let ctx = TestStore.freshContext()
        for day in 1...10 {
            metric(ctx, subject: "tile", key: "eat", type: .selected, at: monthsAgo(4, day: day))
            metric(ctx, subject: "tile", key: "drink", type: .selected, at: monthsAgo(4, day: day))
            metric(ctx, subject: "tile", key: "eat", type: .used, at: monthsAgo(4, day: day))
        }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        let rows = (try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []
        #expect(rows.count == 3, "expected one row per (subject, key, type)")
        #expect(rows.allSatisfy { $0.count == 10 })
    }

    /// A price change mid-period must not collapse rows priced under different
    /// tables — `priceTableAsOf` is in the fold key precisely to prevent it.
    @Test func rowsPricedUnderDifferentTablesNeverMerge() {
        let ctx = TestStore.freshContext()
        let old = APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence,
                                costMicros: 10, timestamp: monthsAgo(4, day: 2))
        old.priceTableAsOf = Date(timeIntervalSince1970: 1_700_000_000)
        let new = APIUsageEvent(cause: .sentenceGenerate, model: ModelID.sentence,
                                costMicros: 20, timestamp: monthsAgo(4, day: 20))
        new.priceTableAsOf = Date(timeIntervalSince1970: 1_750_000_000)
        ctx.insert(old); ctx.insert(new)
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        #expect((((try? ctx.fetch(FetchDescriptor<APIUsageEvent>())) ?? [])).count == 2)
    }

    /// Cache events fold on subject type and event type only. Their `subjectKey`
    /// is a cache key — near-unique per row — so keeping it would produce a fold
    /// that reclaims nothing while looking like it worked.
    @Test func cacheEventsFoldByDroppingTheirKey() {
        let ctx = TestStore.freshContext()
        for day in 1...12 {
            metric(ctx, subject: "cache", key: "eat|drink|g3|v2-\(day)",
                   type: .hit, at: monthsAgo(4, day: day))
        }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        let rows = (try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []
        #expect(rows.count == 1, "near-unique cache keys should still collapse")
        #expect(rows.first?.count == 12)
        // The surviving row must not keep one combination's key and imply the
        // counts belong to it.
        #expect(rows.first?.subjectKey.isEmpty == true)
    }

    /// **Every subject type that carries a cache key must fold, not just
    /// `cache`.** `sentence` is written roughly once per utterance
    /// (`SentenceEngine:1008`) and `promoted` on every promoted-entry hit
    /// (`:1091`); both use a cache key as `subjectKey`. When only `cache` was
    /// dropped from the fold key, these survived folding almost entirely — so a
    /// compaction pass would report months folded and thousands of rows removed
    /// while handing back a fraction of the space, with nothing in the output
    /// explaining the shortfall.
    @Test func everySubjectTypeCarryingACacheKeyFolds() {
        let ctx = TestStore.freshContext()
        for day in 1...10 {
            metric(ctx, subject: "sentence", key: "eat|cookie|g3|v2-\(day)",
                   type: .used, at: monthsAgo(4, day: day))
            metric(ctx, subject: "promoted", key: "want|juice|g3|v2-\(day)",
                   type: .hit, at: monthsAgo(4, day: day))
        }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        let rows = (try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []
        #expect(rows.count == 2, "one survivor per subject type, not per key")
        #expect(rows.allSatisfy { $0.count == 10 })
        #expect(rows.allSatisfy { $0.subjectKey.isEmpty })
    }

    /// The other half of the same rule: `tile` keys come from a 492-word
    /// vocabulary and ARE the meaning of the row, so they must survive. Dropping
    /// them would fold the whole month to one row and destroy per-word counts.
    @Test func tileKeysSurviveFoldingBecauseTheyAreTheMeaning() {
        let ctx = TestStore.freshContext()
        for day in 1...10 {
            metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day))
            metric(ctx, subject: "tile", key: "drink", at: monthsAgo(4, day: day))
        }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        let rows = (try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []
        #expect(Set(rows.map(\.subjectKey)) == ["eat", "drink"])
        #expect(rows.allSatisfy { $0.count == 10 })
    }

    // MARK: - Aggregate shape

    /// A folded row must describe the period it covers, so a reader can say when
    /// the activity happened rather than only how much of it there was.
    @Test func aFoldedRowSpansItsMonth() {
        let ctx = TestStore.freshContext()
        for day in [3, 11, 27] { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day)) }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        let row = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).first
        #expect(row?.isAggregate == true)
        #expect(row?.count == 3)
        let cal = Calendar.current
        #expect(cal.component(.day, from: row?.timestamp ?? .now) == 3, "earliest event in the fold")
        #expect(cal.component(.day, from: row?.periodEnd ?? .now) == 27, "latest event in the fold")
    }

    /// Folding stops as soon as the projection is under the low-water mark —
    /// it must not fold everything it is permitted to touch every time it runs.
    @Test func foldingStopsAtTheLowWaterMark() {
        let ctx = TestStore.freshContext()
        for month in 3...6 {
            for day in 1...20 {
                metric(ctx, subject: "tile", key: "k\(month)", at: monthsAgo(month, day: day))
            }
        }
        try? ctx.save()
        let rowsBefore = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count

        // 80 rows / 1000 bytes ⇒ 12.5 B/row; a 500-byte target is ~40 rows, so
        // roughly half the months should fold and the rest be left alone.
        let outcome = MetricCompactor.compact(
            context: ctx, measuredBytes: 1_000,
            policy: MetricCompactor.Policy(budgetBytes: 1_000, highWaterBytes: 800,
                                           lowWaterBytes: 500, retainMonths: 6,
                                           keepDetailMonths: 2),
            now: Self.now)

        #expect(outcome.monthsFolded > 0)
        #expect(outcome.monthsFolded < 4, "folded every month rather than stopping at the mark")
        let rowsAfter = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count
        #expect(rowsAfter < rowsBefore)
        #expect(!outcome.floorHeld)
    }

    /// Folding is a committed transaction; reclaiming disk is a separate,
    /// best-effort file operation on the next launch. **A reclaim that never
    /// happens must cost nothing but disk** — the data is already compacted, so
    /// totals and behaviour are identical either way.
    ///
    /// The failure this pins is the retry path. Requesting the reclaim only when
    /// rows were removed stranded the store forever: a failed reclaim clears its
    /// own flag, the next launch is still over the mark so compaction reruns, but
    /// everything foldable is already folded — zero rows removed, no new request,
    /// and the free pages never offered to the filesystem again.
    @Test func aReclaimIsRequestedAgainEvenWhenThereIsNothingLeftToFold() {
        let ctx = TestStore.freshContext()
        for day in 1...20 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day)) }
        try? ctx.save()

        // One policy, fixed before the first pass and reused — the point of the
        // test is a store that has not moved between launches. Recomputing it
        // per call would price the target against the already-folded row count
        // and quietly describe a store that is no longer over its mark.
        let policy = foldEverything(ctx, measuredBytes: 10_000)

        // First pass folds everything it can.
        let first = MetricCompactor.compact(context: ctx, measuredBytes: 10_000,
                                            policy: policy, now: Self.now)
        #expect(first.rowsRemoved > 0)
        let afterFirst = totals(ctx)

        // Second pass — the state after a reclaim that failed. The file is the
        // same size, so the store is still over its mark with nothing left to
        // fold, and the data must be untouched and still correct.
        let second = MetricCompactor.compact(context: ctx, measuredBytes: 10_000,
                                             policy: policy, now: Self.now)
        #expect(second.rowsRemoved == 0)
        #expect(totals(ctx) == afterFirst, "a re-run changed the data it had already folded")
        #expect(second.floorHeld, "still over budget, so it must say the floor is holding")
    }

    // MARK: - What a row is worth

    /// The defect a real soak found. Four launches at an 8 MB budget read
    /// 145, then 316, then 593, then 603 bytes per row — not because rows grew,
    /// but because dividing the whole file by a shrinking row count charges each
    /// survivor for fixed overhead and for pages SQLite has freed but not
    /// returned. Every inflated reading demanded another fold; the second launch
    /// destroyed 15,214 rows chasing a target it had already met.
    ///
    /// Pinned as the invariant that matters: a store already under the mark on
    /// its live data must not be folded merely because the *file* is over.
    @Test func aStoreIsNotFoldedForBytesItsRowsDoNotHold() {
        let ctx = TestStore.freshContext()
        for day in 1...20 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day)) }
        try? ctx.save()
        let before = totals(ctx)

        // 20 rows in a 10,000-byte file, low-water 6,000. The naive reading is
        // 500 B/row and demands a target of 12 rows. But the surplus is only
        // 4,000 bytes, which those 20 rows can cover — so folding is legitimate
        // here and this is the control for the next test.
        let outcome = MetricCompactor.compact(
            context: ctx, measuredBytes: 10_000,
            policy: MetricCompactor.Policy(budgetBytes: 10_000, highWaterBytes: 8_000,
                                           lowWaterBytes: 6_000, retainMonths: 6,
                                           keepDetailMonths: 2),
            now: Self.now)
        #expect(outcome.rowsRemoved > 0, "the surplus was reachable, so it should have folded")
        #expect(!outcome.floorHeld)
        #expect(totals(ctx).metricCount == before.metricCount, "folding must preserve totals")
    }

    /// The guard itself: when the surplus is larger than every row in the store
    /// is worth, the file is over the mark for reasons that are not history.
    /// Folding cannot fix that, so it must not be attempted.
    @Test func anUnreachableTargetKeepsHistoryInsteadOfChasingIt() {
        let ctx = TestStore.freshContext()
        for month in 3...8 {
            for day in 1...20 { metric(ctx, subject: "tile", key: "k\(month)", at: monthsAgo(month, day: day)) }
        }
        try? ctx.save()
        let before = totals(ctx)
        let rowsBefore = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count

        // 120 rows, a 100,000-byte file, and a 100-byte low-water. Shedding every
        // row recovers at most the file itself; 99,900 bytes of surplus is not
        // something 120 rows can pay for.
        let outcome = MetricCompactor.compact(
            context: ctx, measuredBytes: 100_000,
            policy: MetricCompactor.Policy(budgetBytes: 100_000, highWaterBytes: 80_000,
                                           lowWaterBytes: 100, retainMonths: 6,
                                           keepDetailMonths: 2),
            now: Self.now)

        #expect(outcome.floorHeld, "an unreachable target must be reported, not chased")
        #expect(outcome.rowsRemoved == 0, "history was destroyed for a target it could not reach")
        #expect(outcome.monthsFolded == 0)
        #expect(outcome.monthsDeleted == 0)
        #expect(((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count == rowsBefore)
        #expect(totals(ctx) == before)
    }

    /// With no completed run to learn from, the estimate is the file over its
    /// rows — accurate precisely when it is needed, because the first compaction
    /// runs on a store its rows dominate.
    @Test func theExchangeRateIsEstimatedUntilAPassHasMeasuredIt() {
        let ctx = TestStore.freshContext()
        for day in 1...10 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day)) }
        try? ctx.save()

        let rate = MetricCompactor.exchangeRate(context: ctx, measuredBytes: 1_450, liveRows: 10)
        #expect(rate.source == "estimated")
        #expect(rate.bytesPerRow == 145)
    }

    /// Once a pass has folded rows and the launch after it has handed bytes back,
    /// that realised figure replaces the estimate — it is the only number with
    /// fragmentation and partial vacuums already priced in.
    @Test func aCompletedPassSuppliesTheMeasuredExchangeRate() {
        let ctx = TestStore.freshContext()
        let run = CompactionRun()
        run.startedAt = Self.now
        run.rowsRemoved = 71_437
        run.reclaimedBytes = 4_050_944
        run.reclaimAttempted = true
        ctx.insert(run)
        try? ctx.save()

        let rate = MetricCompactor.exchangeRate(context: ctx, measuredBytes: 9_101_632,
                                                liveRows: 28_799)
        #expect(rate.source == "measured")
        // 4,050,944 / 71,437 — what the store actually traded at, not the 316
        // B/row the naive ratio would have read from these same numbers.
        #expect(rate.bytesPerRow == 56)
    }

    /// A `floorHeld` pass removes nothing and still reclaims stray pages on the
    /// launch afterwards. It must not shadow the last pass that actually priced
    /// a row: in a soak it did exactly that, dropping the rate from a measured
    /// 57 B/row back to an estimated 316 and destroying 15,214 rows on the next
    /// launch.
    @Test func aPassThatRemovedNoRowsDoesNotShadowARealMeasurement() {
        let ctx = TestStore.freshContext()

        let traded = CompactionRun()
        traded.startedAt = monthsAgo(1)
        traded.rowsRemoved = 71_437
        traded.reclaimedBytes = 4_050_944
        traded.reclaimAttempted = true
        ctx.insert(traded)

        // Newer, reclaimed real bytes, but folded nothing — it measured no
        // exchange rate, only the tail of the previous pass's freelist.
        let heldTheFloor = CompactionRun()
        heldTheFloor.startedAt = Self.now
        heldTheFloor.rowsRemoved = 0
        heldTheFloor.reclaimedBytes = 98_912
        heldTheFloor.reclaimAttempted = true
        ctx.insert(heldTheFloor)
        try? ctx.save()

        let rate = MetricCompactor.exchangeRate(context: ctx, measuredBytes: 9_101_632,
                                                liveRows: 28_795)
        #expect(rate.source == "measured", "fell back to the estimate the guard exists to avoid")
        #expect(rate.bytesPerRow == 56, "took the newer pass that priced nothing")
    }

    /// A pass whose reclaim has not happened yet has measured nothing, and one
    /// that reclaimed nothing would price rows at zero — read as "rows are free",
    /// which would fold the entire history in a single step.
    @Test func anIncompleteOrEmptyPassIsNotTreatedAsAMeasurement() {
        let ctx = TestStore.freshContext()
        let pending = CompactionRun()
        pending.startedAt = Self.now
        pending.rowsRemoved = 5_000
        pending.reclaimedBytes = 0
        pending.reclaimAttempted = false
        ctx.insert(pending)

        let barren = CompactionRun()
        barren.startedAt = Self.now
        barren.rowsRemoved = 5_000
        barren.reclaimedBytes = 0
        barren.reclaimAttempted = true
        ctx.insert(barren)
        try? ctx.save()

        let rate = MetricCompactor.exchangeRate(context: ctx, measuredBytes: 1_000, liveRows: 10)
        #expect(rate.source == "estimated", "a run that reclaimed nothing is not a measurement")
        #expect(rate.bytesPerRow == 100)
    }

    /// Running twice must not double-count, and must not thrash rows that are
    /// already as folded as they can get.
    @Test func compactionIsIdempotent() {
        let ctx = TestStore.freshContext()
        for day in 1...20 { metric(ctx, subject: "tile", key: "eat", at: monthsAgo(4, day: day)) }
        try? ctx.save()

        MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)
        let after = totals(ctx)
        let rows = ((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count

        let second = MetricCompactor.compact(context: ctx, measuredBytes: 1_000,
                                             policy: foldEverything(ctx, measuredBytes: 1_000), now: Self.now)

        #expect(second.rowsRemoved == 0, "a second pass should find nothing left to fold")
        #expect(((try? ctx.fetch(FetchDescriptor<MetricEvent>())) ?? []).count == rows)
        #expect(totals(ctx) == after)
    }
}
}
