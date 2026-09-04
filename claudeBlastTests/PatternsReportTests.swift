// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PatternsReportTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PatternsReportTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Wednesday 2 September 2026, 10am.
    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                           hour: hour, minute: minute))!
    }

    private func utterance(_ keys: [String], at date: Date) -> LoggedUtterance {
        LoggedUtterance(tileKeys: keys, sentence: keys.joined(separator: " "), createdAt: date)
    }

    // MARK: - Days

    /// Silent days are kept, unlike the hour bands in `ActivityGrouping`.
    ///
    /// A band list reads as a list of events, where an empty row is noise. A
    /// chart reads as a shape, and dropping empty days would compress a
    /// fortnight of silence into a flat line beside a busy week — the two would
    /// look identical, which is the opposite of what the chart is for.
    @Test func silentDaysAreKeptInTheSeries() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 1, hour: 9)),
                       utterance(["b"], at: at(day: 5, hour: 9))],
            allTime: [],
            from: at(day: 1, hour: 0),
            to: at(day: 5, hour: 23)
        )
        #expect(report.days.count == 5)
        #expect(report.days.map(\.presses) == [1, 0, 0, 0, 1])
    }

    /// Presses and distinct words are separate series, and they must be able to
    /// diverge — that gap is the finding the chart exists to show.
    @Test func pressesAndDistinctWordsAreCountedSeparately() {
        let report = PatternsReport.make(
            inWindow: [utterance(["want", "want", "want"], at: at(day: 2, hour: 9)),
                       utterance(["want", "more"], at: at(day: 2, hour: 10))],
            allTime: [],
            from: at(day: 2, hour: 0),
            to: at(day: 2, hour: 23)
        )
        let day = try! #require(report.days.first)
        #expect(day.presses == 5)
        #expect(day.distinctWords == 2)
    }

    /// The series never starts before the first thing recorded.
    ///
    /// A window start alone claims silence for days that predate any data. On a
    /// fresh install that is most of the week: fifty taps this afternoon drew
    /// seven weekday rows, six of them asserting the child said nothing on days
    /// when the app was not yet running.
    @Test func theSeriesDoesNotClaimSilenceBeforeRecordingBegan() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 9, hour: 14))],
            allTime: [],
            // A week-wide window over a store holding one afternoon.
            from: at(day: 3, hour: 0),
            to: at(day: 9, hour: 23)
        )
        #expect(report.days.count == 1)
        #expect(report.weekdays.count == 1)
    }

    /// A silent day INSIDE the recorded span is still a row — that one is a
    /// finding, and the fix above must not take it with it.
    @Test func aSilentDayAfterRecordingBeganIsStillShown() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 7, hour: 9)),
                       utterance(["b"], at: at(day: 9, hour: 9))],
            allTime: [],
            from: at(day: 3, hour: 0),
            to: at(day: 9, hour: 23)
        )
        // Days 7, 8, 9 — the 8th silent and kept; days 3-6 predate the data.
        #expect(report.days.count == 3)
        #expect(report.days.map(\.presses) == [1, 0, 1])
    }

    // MARK: - Heatmap

    /// Every week in the window folds onto one, so a habit reads as a column
    /// rather than as scattered dots.
    @Test func weeksFoldOntoOneWeek() {
        // Two Wednesdays, same hour.
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 2, hour: 12)),
                       utterance(["b"], at: at(day: 9, hour: 12))],
            allTime: [],
            from: at(day: 1, hour: 0),
            to: at(day: 9, hour: 23)
        )
        #expect(report.cells.count == 1)
        #expect(report.cells.first?.presses == 2)
    }

    /// Only hours that carry something define the span, so a grid of 24 columns
    /// with four in use never gets drawn.
    @Test func activeHoursSpanOnlyWhatWasUsed() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 2, hour: 8)),
                       utterance(["b"], at: at(day: 2, hour: 17))],
            allTime: [],
            from: at(day: 2, hour: 0),
            to: at(day: 2, hour: 23)
        )
        #expect(report.activeHours == 8...17)
    }

    @Test func anEmptyWindowHasNoActiveHours() {
        let report = PatternsReport.make(
            inWindow: [], allTime: [],
            from: at(day: 2, hour: 0), to: at(day: 2, hour: 23)
        )
        #expect(report.activeHours == nil)
        #expect(report.busiestCell == 0)
        #expect(report.longest == nil)
    }

    /// Only weekdays the window can contain get a row.
    ///
    /// A one-day window used to draw all seven, six of them necessarily blank —
    /// a weekday heatmap over a single day, which cannot say anything about
    /// weekdays and quietly implies six silent ones.
    @Test func aOneDayWindowHasOneWeekdayRow() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 2, hour: 12))],
            allTime: [],
            from: at(day: 2, hour: 0),
            to: at(day: 2, hour: 23)
        )
        // 2 September 2026 is a Wednesday: weekday 4.
        #expect(report.weekdays == [4])
    }

    /// A day inside the window with nothing on it is still a row — an empty
    /// Tuesday is a fact, where a Tuesday the window never reached is not.
    @Test func aSilentDayInsideTheWindowStillGetsARow() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 1, hour: 12))],
            allTime: [],
            from: at(day: 1, hour: 0),
            to: at(day: 3, hour: 23)
        )
        // Tue, Wed, Thu — Monday-first ordering puts them in calendar order here.
        #expect(report.weekdays == [3, 4, 5])
    }

    /// A window of a week or more covers every weekday, in Monday-first order.
    @Test func aFullWeekIsOrderedMondayFirst() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 2, hour: 12))],
            allTime: [],
            from: at(day: 1, hour: 0),
            to: at(day: 8, hour: 23)
        )
        #expect(report.weekdays == [2, 3, 4, 5, 6, 7, 1])
    }

    // MARK: - Comparison

    /// The comparison window is the one immediately before, of equal length.
    @Test func comparisonUsesTheEqualLengthWindowBefore() {
        let start = at(day: 8, hour: 0)
        let end = at(day: 9, hour: 0)          // a 1-day window
        let prior = utterance(["x", "y"], at: at(day: 7, hour: 12))   // inside the prior day
        let older = utterance(["z"], at: at(day: 1, hour: 12))        // well outside it
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 8, hour: 12))],
            allTime: [prior, older],
            from: start, to: end
        )
        let previous = try! #require(report.previous)
        #expect(previous.presses == 2)
        #expect(previous.distinctWords == 2)
    }

    /// Nil, not zero, when there is nothing before.
    ///
    /// "No data yet" and "you said nothing" read identically as a number and
    /// mean opposite things — one is a missing comparison, the other is a
    /// collapse worth acting on.
    @Test func noEarlierHistoryReportsNoComparisonRatherThanZero() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 8, hour: 12))],
            allTime: [],
            from: at(day: 8, hour: 0), to: at(day: 9, hour: 0)
        )
        #expect(report.previous == nil)
    }

    /// An unbounded window has nothing before it, so it must not compare
    /// against itself and report no change with great confidence.
    @Test func anUnboundedWindowHasNoComparison() {
        let report = PatternsReport.make(
            inWindow: [utterance(["a"], at: at(day: 8, hour: 12))],
            allTime: [utterance(["a"], at: at(day: 8, hour: 12))],
            from: nil, to: at(day: 9, hour: 0)
        )
        #expect(report.previous == nil)
    }

    // MARK: - Longest

    /// The high-water mark, by tile count.
    @Test func longestIsTheMostTilesNotTheMostRecent() {
        let big = utterance(["a", "b", "c", "d"], at: at(day: 2, hour: 9))
        let recent = utterance(["e"], at: at(day: 2, hour: 20))
        let report = PatternsReport.make(
            inWindow: [big, recent], allTime: [],
            from: at(day: 2, hour: 0), to: at(day: 2, hour: 23)
        )
        #expect(report.longest?.tileKeys.count == 4)
    }
}
}
