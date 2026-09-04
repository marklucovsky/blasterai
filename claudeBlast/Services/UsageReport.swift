// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageReport.swift
//  claudeBlast
//
//  What gets sent to someone who does not hold the device.
//

import Foundation

/// Everything the readable report shows, gathered once.
///
/// ## Why this is a separate export from `StorageExport`
///
/// `StorageExport` is aggregates-never-content by explicit design — it omits even
/// `MetricEvent.subjectKey`, because for cache rows that field *is* the child's
/// speech. This report deliberately crosses that line: a usage report is only
/// useful if it contains the words. Which ones, how often, on which pages, at
/// what times.
///
/// So the two exports stay separate rather than one growing options. Device
/// health can be sent to anyone; this cannot, and a single export with a
/// checkbox would make that difference a setting rather than a decision.
///
/// ## Who it is for
///
/// Not the person holding the iPad. In a two-device family CloudKit already
/// syncs `LoggedUtterance`, so a parent's own phone has all of this. The report
/// exists for the single-device case and, mainly, for the **SLP** — who will
/// never be on this family's iCloud, and for whom a file is the only channel
/// that exists.
struct UsageReport {

    struct Summary {
        let sessionCount: Int
        /// Utterances in sentence mode; presses in single-word mode.
        let saidCount: Int
        let distinctWordCount: Int
        /// The same three over the preceding window of equal length, when there
        /// is one. Nil rather than zero — "no earlier data" and "a collapse to
        /// nothing" read identically as a number and mean opposite things.
        let previous: (said: Int, distinct: Int)?
    }

    let childName: String
    let sceneName: String
    /// "Past Week", "1–14 September" — whatever the reader should see.
    let periodLabel: String
    let generatedAt: Date

    /// True when every session in the window was single-word.
    ///
    /// Changes the labels rather than the layout: "31 words" against "31 said".
    /// Read from the rows, not from the current setting, so a child who switched
    /// modes on Thursday is not described by Thursday's choice.
    let isSingleWord: Bool

    let summary: Summary
    let coverage: CoverageReport
    let patterns: PatternsReport

    /// Sessions, newest first — always present, and always countable.
    let sessions: [ActivitySession]

    /// Whether the sessions carry what was actually said.
    ///
    /// **The one open question in 4E**, held for Brandi: how much of the child's
    /// speech a readable report should carry. Defaulting to false answers it in
    /// the only direction that can be walked back — a caregiver can always send
    /// more, and can never unsend.
    ///
    /// With it off the report still says a great deal: how often, when, which
    /// words, how much of the board. What it withholds is the sentences.
    let includesUtterances: Bool
}

extension UsageReport {

    static func make(childName: String,
                     scene: BlasterScene?,
                     periodLabel: String,
                     inWindow: [LoggedUtterance],
                     allTime: [LoggedUtterance],
                     tileLookup: [String: TileModel],
                     from start: Date?,
                     to end: Date = .now,
                     includesUtterances: Bool,
                     generatedAt: Date = .now) -> UsageReport {

        let sessions = ActivityGrouping.sessions(inWindow)
        let singleWord = !sessions.isEmpty
            && sessions.allSatisfy { $0.isSingleWord(resolving: tileLookup) }

        let patterns = PatternsReport.make(inWindow: inWindow, allTime: allTime,
                                           from: start, to: end)

        let coverage = CoverageReport.make(
            sceneName: scene?.name ?? "",
            pages: scene?.pages ?? [],
            inWindow: inWindow,
            allTime: allTime)

        let summary = Summary(
            sessionCount: sessions.count,
            saidCount: singleWord ? patterns.totalPresses : inWindow.count,
            distinctWordCount: patterns.distinctWords,
            previous: patterns.previous.map { (said: $0.presses, distinct: $0.distinctWords) })

        return UsageReport(
            childName: childName,
            sceneName: scene?.name ?? "",
            periodLabel: periodLabel,
            generatedAt: generatedAt,
            isSingleWord: singleWord,
            summary: summary,
            coverage: coverage,
            patterns: patterns,
            sessions: sessions,
            includesUtterances: includesUtterances)
    }

    /// A file name a recipient can tell apart from five others in a mail thread.
    ///
    /// Child and period, not a timestamp: an SLP holding reports for eight
    /// children needs to know whose and when at a glance, and "report.pdf" in a
    /// Downloads folder is indistinguishable from every other one.
    var suggestedFileName: String {
        let who = childName.isEmpty ? "Blaster" : childName
        let stamp = generatedAt.formatted(.iso8601.year().month().day()
            .dateSeparator(.dash))
        return "\(who) — \(periodLabel) — \(stamp).pdf"
            .replacingOccurrences(of: "/", with: "-")
    }
}
