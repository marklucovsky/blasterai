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

    // MARK: - Sessions

    private func at(_ minutes: Double) -> Date {
        date(9).addingTimeInterval(minutes * 60)
    }

    /// The gap is the only thing that splits a session. Ten minutes exactly is
    /// still the same sitting; a second more is not.
    @Test func gapSplitsSessionsAndTheBoundaryIsInclusive() {
        let onTheLine = ActivityGrouping.sessions([
            utterance(["a"], at: at(0)),
            utterance(["b"], at: at(10)),
        ])
        #expect(onTheLine.count == 1)

        let justOver = ActivityGrouping.sessions([
            utterance(["a"], at: at(0)),
            utterance(["b"], at: at(10.5)),
        ])
        #expect(justOver.count == 2)
    }

    /// The gap is measured from the *previous utterance*, not from the session's
    /// start — otherwise a long steady sitting would be cut at an arbitrary
    /// point once it outran the window.
    @Test func aLongSteadySittingIsOneSession() {
        let entries = (0..<12).map { utterance(["a"], at: at(Double($0) * 9)) }
        let sessions = ActivityGrouping.sessions(entries)
        #expect(sessions.count == 1)
        #expect(sessions[0].count == 12)
        // 11 gaps of 9 minutes: an hour and 39, far past the 10-minute window.
        #expect(sessions[0].duration == 99 * 60)
    }

    /// Sessions newest first, entries within a session oldest first. The two
    /// orders are opposite on purpose: you scan sittings backwards and read one
    /// forwards.
    @Test func sessionsAreNewestFirstButEntriesReadForwards() {
        let sessions = ActivityGrouping.sessions([
            utterance(["a"], at: at(0)),
            utterance(["b"], at: at(2)),
            utterance(["c"], at: at(40)),
            utterance(["d"], at: at(42)),
        ])
        #expect(sessions.count == 2)
        #expect(sessions[0].startedAt == at(40))
        #expect(sessions[1].startedAt == at(0))
        #expect(sessions[1].entries.map(\.tileKeys) == [["a"], ["b"]])
    }

    /// Input order must not matter — entries arrive newest-first from the
    /// `@Query`, and CloudKit can deliver them in any order at all.
    @Test func unsortedInputGroupsIdentically() {
        let a = utterance(["a"], at: at(0))
        let b = utterance(["b"], at: at(3))
        let c = utterance(["c"], at: at(40))
        let forwards = ActivityGrouping.sessions([a, b, c])
        let backwards = ActivityGrouping.sessions([c, b, a])
        let shuffled = ActivityGrouping.sessions([b, c, a])
        #expect(forwards.map(\.count) == [1, 2])
        #expect(backwards.map(\.count) == forwards.map(\.count))
        #expect(shuffled.map(\.count) == forwards.map(\.count))
    }

    /// Presses and distinct words are different numbers, and the pair is what
    /// carries the meaning. Five utterances over three words is a child
    /// insisting; five over eleven is a child ranging.
    @Test func distinctWordCountCountsWordsNotPresses() {
        let sessions = ActivityGrouping.sessions([
            utterance(["want", "bathroom"], at: at(0)),
            utterance(["bathroom"], at: at(1)),
            utterance(["bathroom", "now"], at: at(2)),
        ])
        #expect(sessions[0].count == 3)
        #expect(sessions[0].distinctWordCount == 3)
    }

    /// Escalation counts utterances that were escalated, not the depth they
    /// reached — one utterance re-tapped four times is one escalated utterance.
    @Test func escalatedCountCountsUtterancesNotDepth() {
        let sessions = ActivityGrouping.sessions([
            utterance(["a"], at: at(0), repetitions: 4),
            utterance(["b"], at: at(1), repetitions: 0),
            utterance(["c"], at: at(2), repetitions: 1),
        ])
        #expect(sessions[0].escalatedCount == 2)
    }

    /// A single utterance is a session, with zero duration. One thing said
    /// really does take no measurable time — the alternative would be inventing
    /// a span nobody observed.
    @Test func aLoneUtteranceIsASessionOfZeroDuration() {
        let sessions = ActivityGrouping.sessions([utterance(["a"], at: at(0))])
        #expect(sessions.count == 1)
        #expect(sessions[0].duration == 0)
    }

    @Test func noEntriesIsNoSessions() {
        #expect(ActivityGrouping.sessions([]).isEmpty)
    }

    /// A sitting that runs past midnight is one sitting. Splitting on the
    /// calendar would cut a bedtime session in half for no reason the child
    /// would recognise.
    @Test func aSessionMayCrossMidnight() {
        let cal = Calendar.current
        let late = cal.date(from: DateComponents(year: 2026, month: 8, day: 27,
                                                 hour: 23, minute: 55))!
        let sessions = ActivityGrouping.sessions([
            utterance(["a"], at: late),
            utterance(["b"], at: late.addingTimeInterval(8 * 60)),
        ])
        #expect(sessions.count == 1)
    }
}
}
