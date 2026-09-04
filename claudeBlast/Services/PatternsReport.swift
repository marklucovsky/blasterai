// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PatternsReport.swift
//  claudeBlast
//
//  When a child talks, and whether their range is growing.
//

import Foundation

/// Shape of use over time: when in the week, how much per day, and how varied.
///
/// ## What is deliberately not here
///
/// CoughDrop's report opens with eight figures — words per utterance, words per
/// minute, utterances per minute, buttons per minute. Three problems with that,
/// and the third is the one that matters:
///
/// 1. They are not independent. In their own published sample total words
///    (20,702) and total buttons (20,763) are the same event counted twice, and
///    words-per-minute and buttons-per-minute are both 2.05.
/// 2. At least one is wrong: words-per-utterance reads 20.93 where the division
///    gives 7.0.
/// 3. Rate measures a keyboard. A child who takes four minutes to build one
///    sentence they meant is not producing 0.25 utterances per minute in any
///    sense a therapist would act on — and reporting it that way rewards
///    exactly the wrong thing.
///
/// So: one number per day, and the pair that carries a finding — how much was
/// said against how many *different* words it used.
struct PatternsReport {

    /// One day.
    struct Day: Identifiable, Equatable {
        let date: Date
        /// Tile presses that day.
        let presses: Int
        /// Distinct words used that day.
        let distinctWords: Int
        var id: Date { date }
    }

    /// One weekday-and-hour cell.
    struct Cell: Identifiable, Equatable {
        /// 1 = Sunday, matching `Calendar.component(.weekday:)`.
        let weekday: Int
        let hour: Int
        let presses: Int
        var id: String { "\(weekday)-\(hour)" }
    }

    /// Days in the window, oldest first, **including days with nothing on
    /// them**.
    ///
    /// Unlike `ActivityGrouping.hourBands`, which drops silent hours. The
    /// difference is deliberate: a band list is read as a list of events, where
    /// an empty row is noise, but a chart is read as a shape, and dropping empty
    /// days would silently compress a fortnight of silence into a flat line
    /// beside a busy week.
    let days: [Day]

    /// Non-empty cells only — a 7×24 grid is mostly zero, and the view draws
    /// the grid regardless.
    let cells: [Cell]

    /// Busiest cell, for scaling the heatmap. Zero when nothing was said.
    let busiestCell: Int

    /// Hours that carry anything, so the grid can show a legible span rather
    /// than 24 columns of which four are used. Empty when nothing was said.
    ///
    /// The span is min-to-max rather than a trimmed range: a lone 3am press
    /// widens the axis, and it should. Hiding an outlier to keep the grid narrow
    /// would suppress exactly the cell a caregiver most needs to see.
    let activeHours: ClosedRange<Int>?

    /// Weekdays the window can actually contain, Monday first.
    ///
    /// Drawn from the span, not from what has data — a Tuesday inside the window
    /// with nothing on it is a real empty row, while a Tuesday the window never
    /// reached is not a row at all.
    ///
    /// Without this a one-day window rendered seven rows, six of them
    /// necessarily blank: a weekday heatmap over a single day, which cannot say
    /// anything about weekdays and quietly implies six silent ones.
    let weekdays: [Int]

    /// The utterance with the most tiles in it, and how many.
    ///
    /// A high-water mark rather than an average. Mean length is dragged down by
    /// every one-word answer, so it moves late and slightly; the longest thing a
    /// child managed moves the moment it happens, which is when a therapist
    /// wants to hear about it.
    let longest: LoggedUtterance?

    let totalPresses: Int
    let distinctWords: Int

    /// The same two figures over the preceding window of equal length, or nil
    /// when there is no history to compare against.
    ///
    /// Nil rather than zero: "no data yet" and "you said nothing" read the same
    /// as a number and mean opposite things.
    let previous: (presses: Int, distinctWords: Int)?
}

extension PatternsReport {

    static func make(inWindow: [LoggedUtterance],
                     allTime: [LoggedUtterance],
                     from start: Date?,
                     to end: Date = .now,
                     calendar: Calendar = .current) -> PatternsReport {

        var cellCounts: [String: Int] = [:]
        var dayPresses: [Date: Int] = [:]
        var dayWords: [Date: Set<String>] = [:]
        var hoursSeen: Set<Int> = []
        var allWords: Set<String> = []
        var presses = 0

        for entry in inWindow {
            let day = calendar.startOfDay(for: entry.createdAt)
            let weekday = calendar.component(.weekday, from: entry.createdAt)
            let hour = calendar.component(.hour, from: entry.createdAt)
            let count = entry.tileKeys.count

            presses += count
            dayPresses[day, default: 0] += count
            dayWords[day, default: []].formUnion(entry.tileKeys)
            allWords.formUnion(entry.tileKeys)
            cellCounts["\(weekday)-\(hour)", default: 0] += count
            hoursSeen.insert(hour)
        }

        let cells = cellCounts.compactMap { key, count -> Cell? in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let weekday = Int(parts[0]), let hour = Int(parts[1]) else { return nil }
            return Cell(weekday: weekday, hour: hour, presses: count)
        }

        // Every day in the span, not just the ones with something on them — but
        // never a day before there was anything to record.
        //
        // The window start alone claims silence for days that predate the first
        // utterance, which on a fresh install is most of them: fifty taps this
        // afternoon drew a full week, six rows of it asserting the child said
        // nothing on days when the app was not yet running. A real silent
        // Tuesday inside the recorded span is a finding and still shows; a
        // Tuesday before recording began is not ours to report.
        var days: [Day] = []
        let earliestRecorded = inWindow.map(\.createdAt).min()
        let windowStart = start ?? earliestRecorded ?? end
        let firstDay = calendar.startOfDay(for: max(windowStart, earliestRecorded ?? windowStart))
        var cursor = firstDay
        let lastDay = calendar.startOfDay(for: end)
        while cursor <= lastDay {
            days.append(Day(date: cursor,
                            presses: dayPresses[cursor] ?? 0,
                            distinctWords: dayWords[cursor]?.count ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // The preceding window of equal length. Only meaningful for a bounded
        // one — "all time" has nothing before it, and comparing it to itself
        // would report no change with great confidence.
        var previous: (presses: Int, distinctWords: Int)?
        if let start {
            let span = end.timeIntervalSince(start)
            let priorStart = start.addingTimeInterval(-span)
            let prior = allTime.filter { $0.createdAt >= priorStart && $0.createdAt < start }
            if !prior.isEmpty {
                previous = (presses: prior.reduce(0) { $0 + $1.tileKeys.count },
                            distinctWords: Set(prior.flatMap(\.tileKeys)).count)
            }
        }

        // Monday-first: a Sunday-first week puts the two quiet days at opposite
        // ends, which is where a weekday pattern is hardest to read.
        let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
        let covered = Set(days.map { calendar.component(.weekday, from: $0.date) })
        let weekdays = mondayFirst.filter { covered.contains($0) }

        return PatternsReport(
            days: days,
            cells: cells,
            busiestCell: cells.map(\.presses).max() ?? 0,
            activeHours: hoursSeen.isEmpty ? nil : (hoursSeen.min()!...hoursSeen.max()!),
            weekdays: weekdays,
            longest: inWindow.max { $0.tileKeys.count < $1.tileKeys.count },
            totalPresses: presses,
            distinctWords: allWords.count,
            previous: previous
        )
    }
}
