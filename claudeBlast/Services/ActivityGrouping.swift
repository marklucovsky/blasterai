// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ActivityGrouping.swift
//  claudeBlast
//
//  Turning a flat utterance log into something a caregiver can read.
//

import Foundation

/// One tile combination, and every time it was said in the window.
struct ActivityCluster: Identifiable {
    /// Sorted tile keys — the combination's identity. "eat apple" and
    /// "apple eat" are the same want said twice, not two wants.
    let tileKeys: [String]
    let entries: [LoggedUtterance]
    /// Most recent sentence for this combination, for the collapsed row.
    let latestSentence: String

    var id: String { tileKeys.joined(separator: "+") }
    var count: Int { entries.count }
    var firstAt: Date { entries.map(\.createdAt).min() ?? .distantPast }
    var latestAt: Date { entries.map(\.createdAt).max() ?? .distantPast }

    /// How many of these were escalated — the child re-tapped Play to say the
    /// same thing louder.
    ///
    /// Kept separate from `count` on purpose. Recurring across the window ("I
    /// said it again later") and escalating within one utterance ("I said it
    /// louder") are different events with different clinical readings, and a
    /// single ×N badge that merged them would misreport both.
    var escalatedCount: Int { entries.filter { $0.repetitionCount > 0 }.count }

    /// Wall-clock time from first to last. This is what makes a count mean
    /// something: "tired ×15 in two hours" is an unmet need, "tired ×15 this
    /// month" is a common word. Same tally, opposite readings.
    var span: TimeInterval { latestAt.timeIntervalSince(firstAt) }
}

/// A one-hour window that actually contains speech.
struct ActivityHourBand: Identifiable {
    let start: Date
    let entries: [LoggedUtterance]

    var id: Date { start }
    var count: Int { entries.count }
}

/// Grouping the activity log, as pure functions over the entries.
///
/// Deliberately not computed properties on a view. The Admin snippet and the
/// full log must show the *same* answer — the snippet is the top of the list
/// the full view renders — and a caregiver comparing the two and finding them
/// different would be right to distrust both. Pure functions also make this
/// testable, which the previous view-embedded grouping was not: that is how a
/// "Most Used" filter that silently ignored the time window survived.
enum ActivityGrouping {

    /// Combinations said fewer than this many times are rolled into the
    /// said-once bucket rather than listed individually.
    ///
    /// Two is the floor that means anything: a "cluster" of one is not a
    /// cluster, it is a line in a timeline. It is also the smallest number that
    /// can be justified without real usage data to tune against — a higher cut
    /// would be a guess about a distribution nobody has measured yet. Revisit
    /// once pilot logs exist; the number is here, alone, so that is a one-line
    /// change.
    static let minimumClusterCount = 2

    struct ClusterResult {
        /// Combinations said `minimumClusterCount`+ times, most-said first.
        let clusters: [ActivityCluster]
        /// Everything below the cut, newest first. Collapsed behind one row so
        /// the long tail of once-said words cannot bury the repetition that
        /// makes this view worth opening.
        let infrequent: [LoggedUtterance]
    }

    /// Group by tile combination.
    static func clusters(_ entries: [LoggedUtterance],
                         minimumCount: Int = minimumClusterCount) -> ClusterResult {
        let buckets = Dictionary(grouping: entries) { $0.tileKeys.sorted().joined(separator: "+") }

        var clusters: [ActivityCluster] = []
        var infrequent: [LoggedUtterance] = []

        for (_, group) in buckets {
            guard group.count >= minimumCount else {
                infrequent.append(contentsOf: group)
                continue
            }
            let newest = group.max(by: { $0.createdAt < $1.createdAt })
            clusters.append(ActivityCluster(
                tileKeys: group.first?.tileKeys.sorted() ?? [],
                entries: group.sorted { $0.createdAt > $1.createdAt },
                latestSentence: newest?.sentence ?? ""
            ))
        }

        clusters.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.latestAt > rhs.latestAt
        }
        infrequent.sort { $0.createdAt > $1.createdAt }
        return ClusterResult(clusters: clusters, infrequent: infrequent)
    }

    /// Group into hour bands, **omitting every hour with nothing in it**.
    ///
    /// A day is mostly silence — a child does not talk for 24 hours — so
    /// rendering empty hours would bury the handful that matter. Nothing is
    /// lost by dropping them: each band carries its own timestamp, so a jump
    /// from 9 AM to 2 PM shows the gap more compactly than five empty rows
    /// could.
    static func hourBands(_ entries: [LoggedUtterance],
                          calendar: Calendar = .current) -> [ActivityHourBand] {
        let buckets = Dictionary(grouping: entries) { entry -> Date in
            calendar.dateInterval(of: .hour, for: entry.createdAt)?.start
                ?? entry.createdAt
        }
        return buckets
            .map { ActivityHourBand(start: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.start > $1.start }
    }
}
