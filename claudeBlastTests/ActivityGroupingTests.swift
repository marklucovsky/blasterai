// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ActivityGroupingTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ActivityGroupingTests {

    private func utterance(_ keys: [String],
                           at date: Date,
                           repetitions: Int = 0,
                           sentence: String = "s") -> LoggedUtterance {
        LoggedUtterance(tileKeys: keys,
                        sentence: sentence,
                        repetitionCount: repetitions,
                        createdAt: date)
    }

    private func date(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 27,
                                                   hour: h, minute: m))!
    }

    // MARK: - Clusters

    /// Order is by count, and a combination's identity ignores tap order —
    /// "eat apple" and "apple eat" are one want said twice, not two wants.
    @Test func clustersGroupByCombinationRegardlessOfOrder() {
        let entries = [
            utterance(["eat", "apple"], at: date(9)),
            utterance(["apple", "eat"], at: date(10)),
            utterance(["tired"], at: date(11)),
            utterance(["tired"], at: date(12)),
            utterance(["tired"], at: date(13)),
        ]
        let result = ActivityGrouping.clusters(entries)
        #expect(result.clusters.count == 2)
        #expect(result.clusters[0].tileKeys == ["tired"])
        #expect(result.clusters[0].count == 3)
        #expect(result.clusters[1].count == 2)
        #expect(result.clusters[1].tileKeys == ["apple", "eat"])   // sorted
    }

    /// Singletons are the noise this view exists to cut through: a long tail of
    /// once-said words would bury the repetition that makes it worth opening.
    @Test func singletonsAreSeparatedFromClusters() {
        let entries = [
            utterance(["tired"], at: date(9)),
            utterance(["tired"], at: date(10)),
            utterance(["pizza"], at: date(11)),
            utterance(["hello"], at: date(12)),
        ]
        let result = ActivityGrouping.clusters(entries)
        #expect(result.clusters.count == 1)
        #expect(result.infrequent.count == 2)
        // Newest first, so the collapsed bucket still reads chronologically.
        #expect(result.infrequent[0].tileKeys == ["hello"])
    }

    /// Escalation is counted separately from recurrence. Said-again and
    /// said-louder are different events, and one ×N badge merging them would
    /// misreport both.
    @Test func escalationIsCountedSeparatelyFromRecurrence() {
        let entries = [
            utterance(["tired"], at: date(9), repetitions: 0),
            utterance(["tired"], at: date(10), repetitions: 3),
            utterance(["tired"], at: date(11), repetitions: 1),
        ]
        let cluster = ActivityGrouping.clusters(entries).clusters[0]
        #expect(cluster.count == 3)          // said three times
        #expect(cluster.escalatedCount == 2) // two of them escalated
    }

    /// Span is what turns a tally into a reading: the same count over two hours
    /// and over a month mean opposite things.
    @Test func spanMeasuresFirstToLast() {
        let entries = [
            utterance(["tired"], at: date(9)),
            utterance(["tired"], at: date(11)),
        ]
        let cluster = ActivityGrouping.clusters(entries).clusters[0]
        #expect(cluster.span == 2 * 3600)
        #expect(cluster.firstAt == date(9))
        #expect(cluster.latestAt == date(11))
    }

    @Test func emptyInputProducesNothing() {
        let result = ActivityGrouping.clusters([])
        #expect(result.clusters.isEmpty)
        #expect(result.infrequent.isEmpty)
    }

    // MARK: - Hour bands

    /// The point of the view: a day is mostly silence, so empty hours are
    /// dropped entirely rather than rendered as filler. Each band carries its
    /// own timestamp, so the gap is still visible from the labels.
    @Test func hourBandsOmitSilentHours() {
        let entries = [
            utterance(["a"], at: date(9, 5)),
            utterance(["b"], at: date(9, 40)),
            utterance(["c"], at: date(14, 10)),
        ]
        let bands = ActivityGrouping.hourBands(entries)
        #expect(bands.count == 2)                 // not 6 — 10am–1pm are gone
        #expect(bands[0].count == 1)              // newest first: the 2pm band
        #expect(bands[1].count == 2)              // the 9am band holds both
    }

    @Test func hourBandsAreNewestFirst() {
        let entries = [
            utterance(["a"], at: date(8)),
            utterance(["b"], at: date(17)),
        ]
        let bands = ActivityGrouping.hourBands(entries)
        #expect(bands.count == 2)
        #expect(bands[0].start > bands[1].start)
    }

    /// Entries in the same clock hour on *different days* are different bands —
    /// 9am Tuesday is not 9am Wednesday.
    @Test func sameHourOnDifferentDaysAreDistinctBands() {
        let cal = Calendar.current
        let tuesday = date(9)
        let wednesday = cal.date(byAdding: .day, value: 1, to: tuesday)!
        let bands = ActivityGrouping.hourBands([
            utterance(["a"], at: tuesday),
            utterance(["b"], at: wednesday),
        ])
        #expect(bands.count == 2)
    }
}
}
