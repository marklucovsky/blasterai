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
