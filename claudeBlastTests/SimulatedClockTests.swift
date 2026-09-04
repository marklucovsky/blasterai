// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SimulatedClockTests.swift
//  claudeBlastTests
//
//  The clock that lets a seconds-long load run write months of history.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SimulatedClockTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// The default must be a no-op. Every existing script omits `days:`, and a
    /// clock that silently backdated them would rewrite the meaning of scripts
    /// nobody edited.
    @Test func zeroSpanKeepsEverythingAtNow() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 0, count: 100, endingAt: now)
        for _ in 0..<10 { #expect(clock.next() == now) }
    }

    /// The point of the whole exercise: a run that takes seconds must produce
    /// rows sitting in distinct calendar months, because that is the only unit
    /// `MetricCompactor` folds in.
    @Test func aRunSpansTheMonthsItClaims() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 180, count: 1_000, endingAt: now)

        var months = Set<DateComponents>()
        for _ in 0..<1_000 {
            months.insert(calendar.dateComponents([.year, .month], from: clock.next()))
        }
        // 180 days touches six or seven calendar months depending on where it
        // starts; either way it must be enough for the detail floor (2) to leave
        // real work behind.
        #expect(months.count >= 6)
    }

    /// Days in the window, oldest first, for a full walk.
    private func dayHistogram(spanDays: Int, count: Int, now: Date) -> [Date: Int] {
        var clock = SimulatedClock(spanDays: spanDays, count: count, endingAt: now)
        var histogram: [Date: Int] = [:]
        for _ in 0..<count {
            histogram[calendar.startOfDay(for: clock.next()), default: 0] += 1
        }
        return histogram
    }

    /// `spanDays` days, ending today, each with a real share — and today is not
    /// special.
    ///
    /// Two bugs lived here in succession and the second is the instructive one.
    /// Pacing by `index / count` never reached the far bucket, so nothing landed
    /// today at all. Pacing by `index / (count - 1)` reached it only at progress
    /// exactly 1 — one event out of three thousand — because `firstDay` sat a
    /// full `spanDays` back, leaving `spanDays + 1` days for `spanDays` buckets.
    /// The endpoint had measure zero either way. Only moving `firstDay` makes
    /// the buckets and the days line up.
    @Test func everyDayInTheWindowGetsAShare() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let histogram = dayHistogram(spanDays: 90, count: 3_000, now: now)

        #expect(histogram.count == 90)
        // 3000 over 90 days is ~33 each. A day with one event is the bug this
        // catches, so the floor is what matters, not the ceiling.
        #expect(histogram.values.min() ?? 0 >= 20)
        #expect(histogram[calendar.startOfDay(for: now)] ?? 0 >= 20)
    }

    /// The window reaches back `spanDays - 1` days and no further: 90 days
    /// *including today*, which is what the parameter reads as.
    @Test func theWindowIsSpanDaysEndingToday() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let days = dayHistogram(spanDays: 90, count: 3_000, now: now).keys.sorted()
        let oldest = try! #require(days.first)
        let newest = try! #require(days.last)
        #expect(newest == calendar.startOfDay(for: now))
        #expect(calendar.dateComponents([.day], from: oldest, to: newest).day == 89)
    }

    /// Today's events spread across the elapsed part of the day rather than
    /// piling onto `now`.
    ///
    /// Clamping future draws to `now` is the obvious guard and it stacks every
    /// afternoon draw on one instant. Session grouping then reports today as a
    /// single sitting of zero duration — a generator artefact that reads exactly
    /// like a finding.
    @Test func todaysEventsDoNotStackOnNow() {
        // Mid-afternoon, so a good half of the waking window is still ahead and
        // would have been clamped.
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2,
                                                     hour: 15, minute: 0))!
        var clock = SimulatedClock(spanDays: 30, count: 900, endingAt: now)
        var today: [Date] = []
        for _ in 0..<900 {
            let stamp = clock.next()
            if calendar.isDate(stamp, inSameDayAs: now) { today.append(stamp) }
        }
        #expect(today.count >= 20)
        #expect(today.allSatisfy { $0 <= now })
        // The tell: distinct instants, not one repeated. Allow a couple of
        // collisions from the RNG rather than demanding perfection.
        #expect(Set(today).count >= today.count - 2)
    }

    /// A day's events arrive in sittings, not evenly spread.
    ///
    /// This is the test that was missing. Uniform scatter put thirty-odd events
    /// twenty-four minutes apart across thirteen hours, so `ActivityGrouping`,
    /// cutting at a ten-minute gap, saw one session per utterance — a load that
    /// ran perfectly and made the feature it fed look broken.
    ///
    /// Asserted through the real grouping rather than against a gap threshold,
    /// so the two cannot drift apart without this failing.
    @Test func aDaysEventsArriveInSittings() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 90, count: 3_000, endingAt: now)

        // A full day well inside the window, so neither end is clipped.
        let target = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -45, to: now)!)
        var stamps: [Date] = []
        for _ in 0..<3_000 {
            let stamp = clock.next()
            if calendar.isDate(stamp, inSameDayAs: target) { stamps.append(stamp) }
        }

        let entries = stamps.map {
            LoggedUtterance(tileKeys: ["a"], sentence: "s", createdAt: $0)
        }
        let sessions = ActivityGrouping.sessions(entries)

        #expect(stamps.count >= 20)
        // The old behaviour scored one session per utterance. Four to a sitting
        // means roughly a quarter as many, and anything near 1.0 is the bug.
        let perSession = Double(stamps.count) / Double(sessions.count)
        #expect(perSession >= 2.5)
    }

    /// A single-event run must not divide by zero, and has nowhere to walk to.
    @Test func aRunOfOneIsStampedWithinTheWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 90, count: 1, endingAt: now)
        let only = clock.next()
        #expect(only <= now)
        #expect(only > calendar.date(byAdding: .day, value: -91, to: now)!)
    }

    /// A metric row stamped in the future would be read as "now" by every
    /// consumer and would never age out. The final day of the window is only
    /// partly elapsed, so this is a live edge, not a theoretical one.
    @Test func neverHandsOutAFutureDate() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 30, count: 500, endingAt: now)
        for _ in 0..<500 { #expect(clock.next() <= now) }
    }

    /// Same seed, same history — a size measurement that cannot be repeated is
    /// an anecdote rather than a number.
    @Test func sameSeedReplaysTheSameHistory() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var a = SimulatedClock(spanDays: 90, count: 200, endingAt: now, seed: 42)
        var b = SimulatedClock(spanDays: 90, count: 200, endingAt: now, seed: 42)
        var c = SimulatedClock(spanDays: 90, count: 200, endingAt: now, seed: 43)

        let first = (0..<200).map { _ in a.next() }
        let second = (0..<200).map { _ in b.next() }
        let other = (0..<200).map { _ in c.next() }

        #expect(first == second)
        #expect(first != other)
    }

    /// Events land in waking hours. Not cosmetic: history where a child is
    /// equally active at 3am reads as machine-generated to anyone reviewing it.
    @Test func eventsLandInWakingHours() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var clock = SimulatedClock(spanDays: 60, count: 300, endingAt: now)
        for _ in 0..<300 {
            let date = clock.next()
            guard date < now else { continue }   // the clamped final day is exempt
            let hour = calendar.component(.hour, from: date)
            #expect(hour >= 7 && hour < 20)
        }
    }

    /// Zero is a fixed point of xorshift, so an unguarded seed of 0 would emit
    /// nothing but zero and every "random" choice would collapse to the same one.
    @Test func zeroSeedStillProducesVariation() {
        var rng = SeededRNG(seed: 0)
        let values = (0..<10).map { _ in rng.next() }
        #expect(Set(values).count == 10)
    }

    /// `fraction()` feeds a time-of-day offset, so a value outside 0..<1 would
    /// push events out of the day they belong to.
    @Test func fractionStaysInRange() {
        var rng = SeededRNG(seed: 7)
        for _ in 0..<1_000 {
            let f = rng.fraction()
            #expect(f >= 0 && f < 1)
        }
    }
}
}
