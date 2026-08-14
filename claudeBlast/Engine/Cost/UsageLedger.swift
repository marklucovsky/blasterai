// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageLedger.swift
//  claudeBlast
//
//  Read-side aggregation over APIUsageEvent. Pure functions over an array so
//  the view can hold a @Query and the arithmetic stays testable.
//

import Foundation

/// Rolled-up consumption for a set of calls.
struct UsageSummary: Equatable {
    var calls = 0
    var promptTokens = 0
    var completionTokens = 0
    var imageCount = 0
    var costMicros = 0
    /// Calls that consumed billable tokens but couldn't be priced. Tracked so a
    /// total can admit it is incomplete instead of quietly understating.
    var unpricedCalls = 0

    var totalTokens: Int { promptTokens + completionTokens }
    var costUSD: Double { Double(costMicros) / 1_000_000 }
    var hasUnpriced: Bool { unpricedCalls > 0 }
}

enum UsageLedger {
    /// Sum a set of events.
    ///
    /// **The one subtlety, and it cuts both ways:** `calls` sums `count`, because
    /// a compacted row stands for many calls. But the token and cost fields are
    /// summed *directly* — on a compacted row those already hold the total for
    /// the period, so multiplying by `count` would inflate them. Getting either
    /// half backwards produces a plausible, wrong number.
    static func summarize(_ events: [APIUsageEvent]) -> UsageSummary {
        events.reduce(into: UsageSummary()) { acc, e in
            acc.calls += e.count
            acc.promptTokens += e.promptTokens
            acc.completionTokens += e.completionTokens
            acc.imageCount += e.imageCount
            acc.costMicros += e.costMicros
            if e.isUnpriced { acc.unpricedCalls += e.count }
        }
    }

    /// Events falling in the calendar month containing `now`.
    static func inMonth(_ events: [APIUsageEvent], containing now: Date = .now,
                        calendar: Calendar = .current) -> [APIUsageEvent] {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return events }
        return events.filter { interval.contains($0.timestamp) }
    }

    /// Per-cause rollup, most expensive first, then by call volume so free
    /// causes still order sensibly among themselves.
    static func byCause(_ events: [APIUsageEvent]) -> [(cause: UsageCause, summary: UsageSummary)] {
        Dictionary(grouping: events, by: \.cause)
            .map { (cause: $0.key, summary: summarize($0.value)) }
            .sorted {
                $0.summary.costMicros != $1.summary.costMicros
                    ? $0.summary.costMicros > $1.summary.costMicros
                    : $0.summary.calls > $1.summary.calls
            }
    }

    /// Split by whether the spend was the child talking or a caregiver authoring
    /// the board — the comparison the public cost claim rests on.
    static func speechVsAuthoring(_ events: [APIUsageEvent]) -> (speech: UsageSummary, authoring: UsageSummary) {
        (summarize(events.filter { $0.cause.isChildSpeech }),
         summarize(events.filter { !$0.cause.isChildSpeech }))
    }

    /// What the cache avoided spending, in micro-dollars.
    ///
    /// Estimated as `hits × mean observed cost of a generated sentence` — using
    /// what sentences *actually* cost on this device rather than a constant, so
    /// the figure tracks real prompt sizes. Returns 0 until at least one sentence
    /// has been generated, since there is then no basis for the estimate.
    ///
    /// Deliberately an estimate and labelled as one in the UI: a cache hit's
    /// counterfactual cost is unknowable, and inventing precision here would
    /// undermine the honest numbers next to it.
    static func estimatedCacheSavingsMicros(events: [APIUsageEvent], cacheHits: Int) -> Int {
        let sentences = events.filter { $0.cause == .sentenceGenerate }
        let summary = summarize(sentences)
        guard summary.calls > 0, cacheHits > 0 else { return 0 }
        let meanCost = Double(summary.costMicros) / Double(summary.calls)
        return Int((meanCost * Double(cacheHits)).rounded())
    }

    // MARK: - Formatting

    /// Cost for display. Sub-cent amounts get more precision, because "$0.00"
    /// reads as "nothing was recorded" when the truth is "this costs almost
    /// nothing" — which is the actual finding and shouldn't be rounded away.
    static func formatUSD(micros: Int) -> String {
        let dollars = Double(micros) / 1_000_000
        if micros == 0 { return "$0.00" }
        // Below the fourth decimal, "$0.0000" is indistinguishable from "free"
        // sitting a row above it — and the two mean different things. A bound is
        // both truer and clearer than a rounded zero.
        if micros < 100 { return "<$0.0001" }
        if dollars < 0.01 { return String(format: "$%.4f", dollars) }
        return String(format: "$%.2f", dollars)
    }

    /// Cost for a summary, distinguishing the three things a zero can mean.
    ///
    /// `$0.00` asserts that a cost was computed and came to nothing. That's only
    /// true for a *billable* call that happened to be free. The other two zeros
    /// say something different and deserve their own words:
    ///
    /// - **"free"** — this endpoint doesn't bill (`/v1/moderations`, `/v1/models`)
    /// - **"unpriced"** / `~$N` — it billed, but we had no price for the model,
    ///   so the figure is a floor. Understating loudly beats understating silently.
    ///
    /// `isFreeCause` is passed in because a summary aggregates rows and can't ask
    /// them individually; the caller knows which cause it grouped.
    static func formatCost(_ summary: UsageSummary, isFreeCause: Bool = false) -> String {
        if isFreeCause && summary.costMicros == 0 { return "free" }
        guard summary.hasUnpriced else { return formatUSD(micros: summary.costMicros) }
        if summary.costMicros == 0 { return "unpriced" }
        return "~" + formatUSD(micros: summary.costMicros)
    }

    /// Compact token counts — 12_400 → "12.4K".
    static func formatTokens(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }

    /// "1 call" / "2 calls". Small thing, but the report is read by caregivers
    /// and "1 calls" makes the whole panel look unfinished.
    static func pluralize(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
