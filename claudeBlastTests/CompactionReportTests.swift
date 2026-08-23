// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CompactionReportTests.swift
//  claudeBlastTests
//
//  2C: the storage budget as a setting, and the record of what compaction did
//  with it.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CompactionReportTests {

    /// A `UserDefaults` of its own, so a test can never leave the real budget
    /// changed on the machine running it.
    private func scratchDefaults() -> UserDefaults {
        let suite = "compaction-report-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - The budget as a setting

    /// Unset must mean "ship as designed". The setting was introduced into a
    /// sealed 256 MB policy, and every install that never touches it has to keep
    /// behaving exactly as it did.
    @Test func anUnsetBudgetIsTheShippingPolicy() {
        let defaults = scratchDefaults()
        let policy = MetricCompactor.Policy.resolved(defaults: defaults)
        #expect(policy.budgetBytes == MetricCompactor.Policy.default.budgetBytes)
        #expect(policy.highWaterBytes == MetricCompactor.Policy.default.highWaterBytes)
    }

    @Test func aChosenBudgetScalesBothWatermarks() {
        let defaults = scratchDefaults()
        defaults.set(128, forKey: AppSettingsKey.compactionBudgetMB)
        let policy = MetricCompactor.Policy.resolved(defaults: defaults)

        #expect(policy.budgetBytes == 128 * 1024 * 1024)
        // 80% / 60% — the same shape as the shipping thresholds, so a smaller
        // budget reacts at the same relative point rather than at a new one.
        #expect(policy.highWaterBytes == policy.budgetBytes * 4 / 5)
        #expect(policy.lowWaterBytes == policy.budgetBytes * 3 / 5)
        #expect(policy.highWaterBytes < policy.budgetBytes)
        #expect(policy.lowWaterBytes < policy.highWaterBytes)
    }

    /// **The floors must not scale with the budget.** This is the property that
    /// keeps a smaller budget honest: it may make the app hold the floor and
    /// report it, but it must never quietly retain less of the child's history.
    @Test func theRetentionFloorsIgnoreTheBudget() {
        let defaults = scratchDefaults()
        for mb in [8, 128, 512, 4096] {
            defaults.set(mb, forKey: AppSettingsKey.compactionBudgetMB)
            let policy = MetricCompactor.Policy.resolved(defaults: defaults)
            #expect(policy.retainMonths == MetricCompactor.Policy.default.retainMonths)
            #expect(policy.keepDetailMonths == MetricCompactor.Policy.default.keepDetailMonths)
        }
    }

    /// Below a few megabytes the store's own fixed overhead dominates and a run
    /// would be measuring SQLite rather than the app's data.
    @Test func absurdlySmallBudgetsAreFloored() {
        let defaults = scratchDefaults()
        defaults.set(1, forKey: AppSettingsKey.compactionBudgetMB)
        #expect(MetricCompactor.Policy.resolved(defaults: defaults).budgetBytes
                == 8 * 1024 * 1024)
    }

    // MARK: - Completing a run across two launches

    /// Reclamation happens before the app has a store, so its result is parked
    /// in `UserDefaults` and collected on the next launch. If that hand-off
    /// breaks, the report can say what compaction destroyed but never what it
    /// bought — which is exactly the comparison the record exists for.
    @Test func aParkedReclaimIsAttachedToItsRun() {
        let container = TestStore.freshContainer()
        let run = CompactionRun()
        run.startBytes = 10_000_000
        run.rowsRemoved = 5_000
        container.mainContext.insert(run)

        let defaults = scratchDefaults()
        defaults.set(run.id, forKey: AppSettingsKey.compactionLastRunID)
        defaults.set(4_000_000, forKey: AppSettingsKey.compactionReclaimedBytes)

        MetricCompactor.attachPendingReclaim(container: container, defaults: defaults)

        #expect(run.reclaimAttempted)
        #expect(run.reclaimedBytes == 4_000_000)
        // Consumed, so a later launch cannot attach the same result twice.
        #expect(defaults.object(forKey: AppSettingsKey.compactionReclaimedBytes) == nil)
        #expect(defaults.string(forKey: AppSettingsKey.compactionLastRunID) == nil)
    }

    /// "Tried and got nothing back" must not read as "hasn't run yet" — the
    /// first would condemn the policy, the second is the normal state of the
    /// most recent run.
    @Test func aReclaimThatFreedNothingIsStillRecordedAsAttempted() {
        let container = TestStore.freshContainer()
        let run = CompactionRun()
        run.startBytes = 10_000_000
        container.mainContext.insert(run)

        let defaults = scratchDefaults()
        defaults.set(run.id, forKey: AppSettingsKey.compactionLastRunID)
        defaults.set(0, forKey: AppSettingsKey.compactionReclaimedBytes)

        MetricCompactor.attachPendingReclaim(container: container, defaults: defaults)

        #expect(run.reclaimAttempted)
        #expect(run.reclaimedBytes == 0)
        #expect(run.reclaimedFraction == 0)
    }

    @Test func nothingParkedMeansNothingTouched() {
        let container = TestStore.freshContainer()
        let run = CompactionRun()
        container.mainContext.insert(run)

        MetricCompactor.attachPendingReclaim(container: container,
                                             defaults: scratchDefaults())
        #expect(!run.reclaimAttempted)
    }

    /// A pending run reports a zero fraction rather than a flattering one — the
    /// exchange rate is unknown until the space actually comes back.
    @Test func aPendingRunClaimsNoReclaim() {
        let run = CompactionRun()
        run.startBytes = 1_000_000
        run.reclaimedBytes = 900_000     // set, but not yet attempted
        #expect(run.reclaimedFraction == 0)
    }

    @Test func theExchangeRateIsBytesFreedPerRowDestroyed() {
        let run = CompactionRun()
        run.startBytes = 10_000_000
        run.rowsRemoved = 1_000
        run.reclaimedBytes = 300_000
        run.reclaimAttempted = true
        #expect(run.bytesPerRowRemoved == 300)
        #expect(abs(run.reclaimedFraction - 0.03) < 0.0001)
    }

    // MARK: - Export

    @Test func theExportCarriesStorageAndHistory() throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        ctx.insert(MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected))
        ctx.insert(MetricEvent(subjectType: "tile", subjectKey: "drink", eventType: .selected))

        let report = StorageReporter.report(container: container)
        let data = try #require(StorageExport.json(container: container, report: report))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(root["generatedAt"] != nil)
        #expect(root["storage"] is [String: Any])
        #expect(root["policy"] is [String: Any])
        let history = try #require(root["history"] as? [String: Any])
        #expect(history["metricRows"] as? Int == 2)
        #expect(history["metricEvents"] as? Int == 2)
    }

    /// The export is meant to be handed to someone. `subjectKey` for a cache row
    /// *is* the tile combination — the child's speech — so nothing that could
    /// carry it may appear.
    @Test func theExportLeaksNoContent() throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        ctx.insert(MetricEvent(subjectType: "cache", subjectKey: "eat|cookie|g2",
                               eventType: .hit))
        let tile = TileModel(key: "cookie", wordClass: "food")
        ctx.insert(tile)

        let report = StorageReporter.report(container: container)
        let data = try #require(StorageExport.json(container: container, report: report))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(!text.contains("cookie"))
        #expect(!text.contains("subjectKey"))
    }

    /// Folding removes rows while preserving summed `count`, so the two
    /// diverging is the export's visible trace of compaction having happened.
    @Test func theExportDistinguishesRowsFromEvents() throws {
        let container = TestStore.freshContainer()
        let folded = MetricEvent(subjectType: "tile", subjectKey: "eat",
                                 eventType: .selected, count: 500,
                                 timestamp: .now, periodEnd: .now)
        container.mainContext.insert(folded)

        let report = StorageReporter.report(container: container)
        let data = try #require(StorageExport.json(container: container, report: report))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let history = try #require(root["history"] as? [String: Any])

        #expect(history["metricRows"] as? Int == 1)
        #expect(history["metricEvents"] as? Int == 500)
        #expect(history["foldedMetricRows"] as? Int == 1)
    }
}
}
