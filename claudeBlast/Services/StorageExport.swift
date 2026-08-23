// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  StorageExport.swift
//  claudeBlast
//
//  The storage + compaction picture as a file somebody can read off-device.
//

import Foundation
import SwiftData

/// Serialises what this device is storing and what compaction has done about it.
///
/// ## Why an export exists at all
///
/// Compaction runs unattended, on launch, and deletes data to hold a budget. The
/// only way to know whether that trade is worth making is to look at real
/// numbers from real devices — how big the store got, how often the mark was
/// crossed, how much space folding actually returned, and how often the app
/// chose the retention floor over the budget. None of that can be gathered by
/// asking a caregiver to read a screen to you.
///
/// This is also the app's **first metric export of any kind**. Until now the
/// metric stream could only be read as aggregate counts inside the Activity tab.
///
/// ## Aggregates, never content
///
/// Counts, byte totals and timings only. No sentences, no tile keys, no child
/// names, no identifiers of any kind — a file a caregiver can hand over without
/// having to trust what is inside it. `MetricEvent.subjectKey` in particular is
/// deliberately absent: for cache rows it *is* the tile combination, which is
/// the child's speech.
enum StorageExport {

    @MainActor
    static func json(container: ModelContainer,
                     report: StorageReport,
                     policy: MetricCompactor.Policy = .resolved(),
                     now: Date = .now) -> Data? {
        let context = container.mainContext
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: now),
            "schemaVersion": 1,
            "storage": storageSection(report),
            "policy": policySection(policy),
            "history": historySection(context),
            "compactionRuns": runsSection(context),
        ]
        return try? JSONSerialization.data(withJSONObject: payload,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Sections

    private static func storageSection(_ report: StorageReport) -> [String: Any] {
        [
            "appBytes": report.appBytes,
            "tileArtBytes": report.bundledArtBytes,
            "generatedArtBytes": report.generatedArtBytes,
            "syncedStoreBytes": report.syncedStoreBytes,
            "deviceLocalBytes": report.deviceLocalBytes,
            "onDeviceBytes": report.onDeviceBytes,
            "syncedBytes": report.syncedBytes,
        ]
    }

    private static func policySection(_ policy: MetricCompactor.Policy) -> [String: Any] {
        [
            "budgetBytes": policy.budgetBytes,
            "highWaterBytes": policy.highWaterBytes,
            "lowWaterBytes": policy.lowWaterBytes,
            "retainMonths": policy.retainMonths,
            "keepDetailMonths": policy.keepDetailMonths,
        ]
    }

    /// What the managed history currently holds, and — the number the whole
    /// budget rests on — what a row actually costs.
    ///
    /// `bytesPerRow` is measured, not assumed: device-local bytes divided by live
    /// rows. The plan estimated ~275 B from the schema and said to check it
    /// against reality, because every threshold is derived from the resulting
    /// six-month footprint. This is that check, on every device that exports.
    private static func historySection(_ context: ModelContext) -> [String: Any] {
        let metrics = (try? context.fetch(FetchDescriptor<MetricEvent>())) ?? []
        let usage = (try? context.fetch(FetchDescriptor<APIUsageEvent>())) ?? []
        let rows = metrics.count + usage.count

        var section: [String: Any] = [
            "metricRows": metrics.count,
            "usageRows": usage.count,
            // Folding preserves summed `count` while removing rows, so these two
            // diverging from the row counts is the visible trace of compaction.
            "metricEvents": metrics.reduce(0) { $0 + $1.count },
            "usageCalls": usage.reduce(0) { $0 + $1.count },
            "foldedMetricRows": metrics.filter { $0.periodEnd != nil }.count,
            "foldedUsageRows": usage.filter { $0.periodEnd != nil }.count,
        ]
        if let oldest = (metrics.map(\.timestamp) + usage.map(\.timestamp)).min() {
            section["oldestEvent"] = ISO8601DateFormatter().string(from: oldest)
            section["coverageDays"] = Calendar.current
                .dateComponents([.day], from: oldest, to: .now).day ?? 0
        }
        section["rows"] = rows
        return section
    }

    private static func runsSection(_ context: ModelContext) -> [[String: Any]] {
        let descriptor = FetchDescriptor<CompactionRun>(
            sortBy: [SortDescriptor(\CompactionRun.startedAt, order: .reverse)])
        let runs = (try? context.fetch(descriptor)) ?? []
        return runs.map { run in
            [
                "startedAt": ISO8601DateFormatter().string(from: run.startedAt),
                "budgetBytes": run.budgetBytes,
                "startBytes": run.startBytes,
                "endBytes": run.endBytes,
                "reclaimedBytes": run.reclaimedBytes,
                "reclaimAttempted": run.reclaimAttempted,
                "monthsFolded": run.monthsFolded,
                "monthsDeleted": run.monthsDeleted,
                "rowsBefore": run.rowsBefore,
                "rowsAfter": run.rowsAfter,
                "rowsRemoved": run.rowsRemoved,
                "floorHeld": run.floorHeld,
                "durationMs": run.durationMs,
            ]
        }
    }

    /// Suggested filename. Dated, because the interesting comparison is between
    /// two exports from the same device rather than between devices.
    static func filename(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "blaster-storage-\(formatter.string(from: now)).json"
    }
}
