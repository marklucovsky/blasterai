// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CompactionRunRow.swift
//  claudeBlast
//

import SwiftUI

/// One compaction pass, told as what it cost and what it bought.
///
/// The two numbers side by side are the point. Rows removed is the price —
/// detail that no longer exists — and reclaimed bytes is what was paid for it.
/// A pass that removed thousands of rows and handed back almost nothing is the
/// finding that would send the whole policy back for rework, and it should be
/// legible at a glance rather than buried in a log that is gone by the time
/// anyone asks.
struct CompactionRunRow: View {
    let run: CompactionRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if run.floorHeld {
                    // Not an error: the app chose the child's history over the
                    // disk target. It is the most important thing a run can say.
                    Label("Floor held", systemImage: "shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("−\(run.rowsRemoved) rows")
                if run.reclaimAttempted {
                    Text("+\(StorageReporter.format(Int64(run.reclaimedBytes))) freed")
                        .foregroundStyle(run.reclaimedBytes > 0 ? .green : .red)
                } else {
                    // Reclaim happens on the NEXT launch by design, so this is the
                    // normal state of the most recent run, not a failure.
                    Text("reclaim pending")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        var parts = ["\(StorageReporter.format(Int64(run.startBytes))) at start"]
        parts.append("folded \(run.monthsFolded) month\(run.monthsFolded == 1 ? "" : "s")")
        if run.monthsDeleted > 0 { parts.append("deleted \(run.monthsDeleted)") }
        return parts.joined(separator: " · ")
    }
}
