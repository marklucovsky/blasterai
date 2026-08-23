// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CompactionRun.swift
//  claudeBlast
//
//  What one compaction pass measured, decided, and reclaimed.
//

import Foundation
import SwiftData

/// A durable record of a single `MetricCompactor` pass.
///
/// ## Why this is persisted rather than logged
///
/// Compaction is automatic, runs at launch, and deletes data. Three properties
/// that together mean "it wrote something to the console" is not good enough: by
/// the time anyone asks whether it behaved, the log is gone. The question that
/// matters — *did it give back enough space to justify what it destroyed?* — can
/// only be answered by comparing a before to an after, and the after arrives on
/// a **different launch** than the before.
///
/// So each pass leaves a row. `startBytes` and `endBytes` are measured on the
/// launch that folded; `reclaimedBytes` is filled in by the next one, once the
/// pages have actually been handed back to the filesystem. A run with
/// `reclaimAttempted == false` is not a failure — it is a pass whose second half
/// has not happened yet.
///
/// Device-local, like the metric stream it manages: this is a fact about one
/// device's disk, and it would be meaningless merged across a family's iPads.
@Model
final class CompactionRun {
    var id: String = UUID().uuidString
    var startedAt: Date = Date.now

    // The policy in force, recorded rather than assumed. The budget is a
    // setting now, so a run read months later must say what it was aiming at —
    // otherwise its numbers cannot be judged.
    var budgetBytes: Int = 0
    var highWaterBytes: Int = 0
    var lowWaterBytes: Int = 0
    var retainMonths: Int = 0
    var keepDetailMonths: Int = 0

    /// Device-local bytes measured before anything was touched.
    var startBytes: Int = 0
    /// Measured after folding and deleting — but before the file was truncated,
    /// so this is usually close to `startBytes`. Rows left; pages did not.
    var endBytes: Int = 0
    /// Bytes the *following* launch handed back to the filesystem. Zero until
    /// that launch happens; see `reclaimAttempted` to tell "not yet" from "none".
    var reclaimedBytes: Int = 0
    /// True once a reclaim pass has run for this compaction, whatever it freed.
    var reclaimAttempted: Bool = false

    var monthsFolded: Int = 0
    var monthsDeleted: Int = 0
    var rowsRemoved: Int = 0
    var rowsBefore: Int = 0
    var rowsAfter: Int = 0

    /// Everything permitted was done and the store is still over budget — the
    /// six-month coverage floor held rather than being breached. The single most
    /// important field here: it is the app choosing the child's history over the
    /// disk target, and it should be visible rather than inferred.
    var floorHeld: Bool = false
    var durationMs: Int = 0

    init() {}

    /// Space actually returned, as a fraction of what the store held. The
    /// judgement call the whole record exists to support: folding that reclaims
    /// a rounding error is destroying detail for nothing.
    var reclaimedFraction: Double {
        guard startBytes > 0, reclaimAttempted else { return 0 }
        return Double(reclaimedBytes) / Double(startBytes)
    }

    /// Bytes freed per row destroyed — the exchange rate compaction ran at.
    var bytesPerRowRemoved: Int {
        guard rowsRemoved > 0, reclaimedBytes > 0 else { return 0 }
        return reclaimedBytes / rowsRemoved
    }
}
