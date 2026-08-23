// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SimulatedClock.swift
//  claudeBlast
//
//  A virtual clock for synthetic load: run 10,000 iterations in seconds while
//  the rows they write claim to span months.
//

import Foundation

/// Hands out timestamps spread across a past window, so a bulk run that finishes
/// in seconds writes history that looks months old.
///
/// ## Why this exists
///
/// Everything downstream of the metric log reasons in *calendar time*.
/// `MetricCompactor` folds in whole months and refuses to touch the current and
/// previous one; `SentenceCacheManager.evictStale` ages entries out by date. A
/// load generator that stamps every row `.now` therefore produces exactly the
/// data those paths are built to leave alone — it can prove the store gets big,
/// but never that anything gets trimmed.
///
/// Backdating is the whole trick, and it is legitimate rather than a fudge: the
/// rows are written by the real writers through the real code paths, and the only
/// synthetic input is when they claim to have happened.
///
/// ## Distribution
///
/// Events are spread uniformly across the window's days, and placed at a random
/// waking hour within their day. **This models volume and calendar spread, not
/// diurnal realism** — a real child's traffic is bursty, clustered into therapy
/// sessions and mealtimes. Uniformity is the right simplification here because
/// the consumers bucket by month: what matters is that N months each hold a
/// plausible share of rows, not that Tuesday afternoon looks busier than Tuesday
/// morning.
///
/// ## Determinism
///
/// Seeded, so the same spec replays the same history. A size measurement you
/// cannot repeat is an anecdote.
struct SimulatedClock {
    /// Waking hours, as seconds from local midnight — events land inside 7am–8pm
    /// rather than scattering through the night.
    private static let wakingStart: TimeInterval = 7 * 3600
    private static let wakingLength: TimeInterval = 13 * 3600

    private let calendar: Calendar
    private let firstDay: Date
    private let spanDays: Int
    private let count: Int
    private let now: Date
    private var rng: SeededRNG
    private var index = 0

    /// - Parameters:
    ///   - spanDays: how far back the window reaches. **Zero or less means "no
    ///     simulation"** — every timestamp is `endingAt`, which is the behaviour
    ///     bulk generation had before this existed, so leaving it unset changes
    ///     nothing.
    ///   - count: how many timestamps will be requested, used to pace the walk.
    ///   - endingAt: the window's end, normally now.
    init(spanDays: Int, count: Int, endingAt now: Date = .now, seed: UInt64 = 0x5EED) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        self.spanDays = max(0, spanDays)
        self.count = max(1, count)
        self.now = now
        self.rng = SeededRNG(seed: seed)
        // Start one full day inside the window so the oldest event has a whole
        // day to sit in, and today stays the last bucket.
        self.firstDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -self.spanDays, to: now) ?? now)
    }

    /// The next timestamp in the walk. Advances on every call.
    mutating func next() -> Date {
        guard spanDays > 0 else { return now }
        defer { index += 1 }

        // Which day this event falls on, walked linearly across the window.
        let progress = Double(min(index, count - 1)) / Double(count)
        let dayOffset = Int(progress * Double(spanDays))
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else {
            return now
        }

        let offset = Self.wakingStart + rng.fraction() * Self.wakingLength
        let stamped = day.addingTimeInterval(offset)
        // Never hand out a future date: the last day is partially elapsed, and a
        // metric row timestamped after "now" would confuse every reader of it.
        return min(stamped, now)
    }
}

/// xorshift64* — small, fast, and reproducible. Not for anything where randomness
/// quality matters; this only needs to spread synthetic events plausibly and
/// replay identically when asked.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a fixed point of xorshift, so it would emit nothing but zero.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// A value in `0..<1`.
    mutating func fraction() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 2^53
    }
}
