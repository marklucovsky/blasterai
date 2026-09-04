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
/// Days get an even share of the total. **Within a day, events arrive in
/// bursts** — a handful of utterances minutes apart, then an hour or more of
/// nothing — because that is how a child uses a board: a few sittings at meals
/// and therapy, silence in between.
///
/// This used to scatter uniformly through waking hours, on the argument that the
/// consumers bucket by month so intraday shape did not matter. That was true of
/// the compaction consumers and false of everything read as *behaviour*. Thirty
/// events spread evenly over thirteen hours sit twenty-four minutes apart, so
/// `ActivityGrouping.sessions` — which cuts at a ten-minute gap — reported
/// almost exactly one session per utterance. The load looked like it worked and
/// the feature it was feeding looked broken.
///
/// Bursts are still a simplification: every day gets the same number of sittings
/// of the same length, and nothing knows that Tuesday is a therapy day. What
/// they buy is that gap-based grouping has something real to cut on.
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

    /// Utterances per sitting.
    ///
    /// Four is a plausible short exchange and, more usefully, it is enough that
    /// a session reads as a session: a `1 said` row tells a caregiver nothing
    /// about how a sitting developed.
    private static let burstLength = 4

    /// Spacing between utterances inside one sitting, before jitter.
    ///
    /// Deliberately well under `ActivityGrouping.sessionGap` so a burst holds
    /// together. The jitter can stretch a gap to about four and a half minutes,
    /// which is still comfortably inside ten — bursts split only when the
    /// grouping rule changes, not at the generator's whim.
    private static let withinBurstGap: TimeInterval = 3 * 60

    private let calendar: Calendar
    private let firstDay: Date
    private let spanDays: Int
    private let count: Int
    private let now: Date
    private var rng: SeededRNG
    private let seed: UInt64
    private var index = 0

    /// A stable fraction for a coordinate pair — same inputs, same answer, no
    /// matter when it is asked.
    ///
    /// Needed because a sitting's start time belongs to the sitting, not to
    /// whichever event happens to ask first. The sequential generator cannot
    /// give that: every call advances it, so four events in one burst would get
    /// four different answers for the same question.
    ///
    /// splitmix64's finalizer — cheap, and enough mixing that adjacent days and
    /// adjacent bursts land nowhere near each other.
    private static func hashFraction(_ a: Int, _ b: Int, _ seed: UInt64) -> Double {
        var z = seed &+ (UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15)
        z = z &+ (UInt64(bitPattern: Int64(b)) &* 0xBF58_476D_1CE4_E5B9)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }

    /// - Parameters:
    ///   - spanDays: how many days the window covers, **ending today** — so 90
    ///     means the 89 days before today plus today itself. **Zero or less
    ///     means "no simulation"** — every timestamp is `endingAt`, which is the
    ///     behaviour bulk generation had before this existed, so leaving it
    ///     unset changes nothing.
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
        self.seed = seed
        // `spanDays` days ENDING TODAY, so the window is [now - (spanDays - 1),
        // now] and today is one of the buckets rather than a boundary.
        //
        // Reaching back a full `spanDays` instead gives spanDays + 1 distinct
        // days for spanDays buckets to cover, and the extra one can only be hit
        // at progress == 1 exactly — so today collected a single event out of
        // three thousand rather than its share. `days: 90` now means ninety
        // days including today, which is also what a reader expects it to mean.
        self.firstDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(self.spanDays - 1), to: now) ?? now)
    }

    /// The next timestamp in the walk. Advances on every call.
    mutating func next() -> Date {
        guard spanDays > 0 else { return now }
        defer { index += 1 }

        // Which day this event falls on, walked linearly across the window.
        //
        // Progress stays strictly below 1, so the offset lands in
        // `0 ..< spanDays` — exactly the buckets `firstDay` was placed to cover.
        // Every day gets its share, today included.
        let walked = min(index, count - 1)
        let progress = Double(walked) / Double(count)
        let dayOffset = Int(progress * Double(spanDays))
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else {
            return now
        }

        // Where this event sits inside its day. The walk is linear, so a day's
        // events are a contiguous run of indices and the same map that chose the
        // day gives the run's first index.
        let firstIndexOfDay = Int(
            (Double(dayOffset) * Double(count) / Double(spanDays)).rounded(.up))
        let localIndex = max(0, walked - firstIndexOfDay)

        let burst = localIndex / Self.burstLength
        let positionInBurst = localIndex % Self.burstLength

        // Sittings share out the waking window. The jitter is half a slot, so
        // sittings never drift into each other's territory and the gaps between
        // them stay far wider than the ten minutes that would merge them.
        let perDay = max(1, Int((Double(count) / Double(spanDays)).rounded(.up)))
        let burstsPerDay = max(1, (perDay + Self.burstLength - 1) / Self.burstLength)
        let slot = Self.wakingLength / Double(burstsPerDay)
        // The anchor's jitter is a property of the SITTING, so it is hashed from
        // (day, burst) rather than drawn from the sequential generator. Drawing
        // it per event — the obvious way, and the way this was first written —
        // gives every member of a burst its own anchor, scattering them across
        // half a slot: measured, a "burst" of four spanned 43 minutes and
        // grouping cut it into three. The events must share a start.
        let anchor = Self.wakingStart
            + Double(burst) * slot
            + Self.hashFraction(dayOffset, burst, seed) * slot * 0.5

        // The step inside a burst still varies per event, which is fine once the
        // anchor is shared: the multiplier is narrow enough that the worst step
        // between neighbouring positions is about seven and a half minutes,
        // inside `sessionGap`. A wider range (0.5–1.5, also tried) puts position
        // 3 at thirteen minutes and splits the burst on its own.
        let spread = Self.withinBurstGap * Double(positionInBurst) * (0.7 + rng.fraction() * 0.6)

        // Clamp inside waking hours. Only bites at densities far past anything
        // the load scripts ask for, where a day holds more sittings than the day
        // has room for; the tail bunches at 8pm rather than running into night.
        let offset = min(anchor + spread, Self.wakingStart + Self.wakingLength)

        // Today is only partly elapsed, and a row stamped in the future would be
        // read as "now" by every consumer and never age out.
        //
        // Clamping each future draw to `now` is the obvious answer and the wrong
        // one: run this at lunchtime and every afternoon draw collapses onto the
        // same instant, so today arrives as one heap at one timestamp. Session
        // grouping then reports a single sitting of zero duration — a generator
        // artefact indistinguishable from a finding.
        //
        // Instead the whole day is squeezed into the part that has happened,
        // uniformly. Uniformly matters: scaling only the draws that overshot
        // would map a 6pm event below a 5pm one and shuffle the bursts.
        let dayEnd = day.addingTimeInterval(Self.wakingStart + Self.wakingLength)
        guard dayEnd > now else { return day.addingTimeInterval(offset) }

        // The squeeze maps the waking window onto the waking time that has
        // actually elapsed — 7am stays 7am, 8pm becomes now — rather than
        // squeezing from midnight, which would push a morning event into the
        // small hours and make the generated history read as machine-made.
        let elapsedWaking = now.timeIntervalSince(day) - Self.wakingStart
        guard elapsedWaking > 0 else { return now }
        let squeeze = elapsedWaking / Self.wakingLength
        return day.addingTimeInterval(Self.wakingStart + (offset - Self.wakingStart) * squeeze)
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
