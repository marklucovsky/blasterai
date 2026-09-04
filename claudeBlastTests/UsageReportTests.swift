// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageReportTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct UsageReportTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                           hour: hour, minute: minute))!
    }

    private func utterance(_ keys: [String], _ sentence: String,
                           at date: Date, pages: [String] = []) -> LoggedUtterance {
        LoggedUtterance(tileKeys: keys, sentence: sentence,
                        pageKeys: pages, createdAt: date)
    }

    private func sampleScene() -> BlasterScene {
        let scene = BlasterScene(name: "Core-First", homePageKey: "home")
        scene.pages = [
            PageSpec(key: "home", tiles: [
                TileEntry(key: "want", link: "", isAudible: true),
                TileEntry(key: "more", link: "", isAudible: true),
                TileEntry(key: "what", link: "", isAudible: true),
            ]),
        ]
        return scene
    }

    private func sampleEntries() -> [LoggedUtterance] {
        [
            utterance(["want", "more"], "I want more", at: at(day: 8, hour: 9), pages: ["home", "home"]),
            utterance(["want"], "I want that", at: at(day: 8, hour: 9, minute: 3), pages: ["home"]),
            utterance(["more"], "more please", at: at(day: 9, hour: 12), pages: ["home"]),
        ]
    }

    // MARK: - Composition

    /// The report is a composition, not a fourth calculation. If it computed its
    /// own totals they could disagree with the screens the caregiver just looked
    /// at, and a report that contradicts the app is worse than no report.
    @Test func theReportAgreesWithTheScreensItSummarises() {
        let entries = sampleEntries()
        let report = UsageReport.make(
            childName: "Ada", scene: sampleScene(), periodLabel: "Past Week",
            inWindow: entries, allTime: entries, tileLookup: [:],
            from: at(day: 3, hour: 0), to: at(day: 9, hour: 23),
            includesUtterances: false)

        #expect(report.sessions.count == ActivityGrouping.sessions(entries).count)
        #expect(report.summary.distinctWordCount == report.patterns.distinctWords)
        #expect(report.coverage.sceneWordCount == 3)
    }

    /// In sentence mode the middle figure counts utterances; in single-word mode
    /// it counts presses. They are different events and the label moves with it.
    @Test func theSaidCountFollowsTheMode() {
        let entries = sampleEntries()
        let report = UsageReport.make(
            childName: "Ada", scene: sampleScene(), periodLabel: "Past Week",
            inWindow: entries, allTime: entries, tileLookup: [:],
            from: at(day: 3, hour: 0), to: at(day: 9, hour: 23),
            includesUtterances: false)
        #expect(report.isSingleWord == false)
        #expect(report.summary.saidCount == 3)      // utterances, not the 4 presses
    }

    // MARK: - The privacy default

    /// Off unless asked for. A caregiver can always send more and can never
    /// unsend, so the default has to be the direction that can be walked back.
    @Test func utterancesAreExcludedByDefault() {
        #expect(UsageReportOptions().includeUtterances == false)
    }

    /// The flag reaches the report, which is what the renderer's running footer
    /// keys off — a page of this file can be forwarded on its own, so the
    /// warning cannot live only on page one.
    @Test func theIncludeFlagReachesTheReport() {
        let entries = sampleEntries()
        for included in [true, false] {
            let report = UsageReport.make(
                childName: "Ada", scene: sampleScene(), periodLabel: "Past Week",
                inWindow: entries, allTime: entries, tileLookup: [:],
                from: at(day: 3, hour: 0), to: at(day: 9, hour: 23),
                includesUtterances: included)
            #expect(report.includesUtterances == included)
        }
    }

    // MARK: - The file itself

    /// Renders a real PDF, both ways.
    @Test func itRendersAPDF() {
        let entries = sampleEntries()
        for included in [false, true] {
            let report = UsageReport.make(
                childName: "Ada", scene: sampleScene(), periodLabel: "Past Week",
                inWindow: entries, allTime: entries, tileLookup: [:],
                from: at(day: 3, hour: 0), to: at(day: 9, hour: 23),
                includesUtterances: included)
            var options = UsageReportOptions()
            options.includeUtterances = included

            let data = UsageReportRenderer.render(report, options: options)
            #expect(data.count > 1_000)
            #expect(data.prefix(4) == Data("%PDF".utf8))
        }
    }

    /// An empty period still produces a readable file rather than failing. A
    /// caregiver who shares a quiet week should get a report that says it was
    /// quiet, which is itself a finding.
    @Test func aQuietPeriodStillRenders() {
        let report = UsageReport.make(
            childName: "Ada", scene: sampleScene(), periodLabel: "Today",
            inWindow: [], allTime: [], tileLookup: [:],
            from: at(day: 9, hour: 0), to: at(day: 9, hour: 23),
            includesUtterances: false)
        let data = UsageReportRenderer.render(report)
        #expect(data.prefix(4) == Data("%PDF".utf8))
        #expect(report.sessions.isEmpty)
    }

    /// The file name has to be tellable apart in a mail thread holding eight of
    /// them — an SLP needs whose and when at a glance.
    @Test func theFileNameCarriesWhoAndWhen() {
        let report = UsageReport.make(
            childName: "Ada", scene: sampleScene(), periodLabel: "Past Week",
            inWindow: [], allTime: [], tileLookup: [:],
            from: nil, to: at(day: 9, hour: 12),
            includesUtterances: false,
            generatedAt: at(day: 9, hour: 12))
        let name = report.suggestedFileName
        #expect(name.contains("Ada"))
        #expect(name.contains("Past Week"))
        #expect(name.hasSuffix(".pdf"))
        // A slash in a period label would otherwise make a path component.
        #expect(!name.dropLast(4).contains("/"))
    }

    /// No child profile is a supported state — the Sandbox profile has no name.
    @Test func anUnnamedChildStillProducesAFile() {
        let report = UsageReport.make(
            childName: "", scene: nil, periodLabel: "All Time",
            inWindow: [], allTime: [], tileLookup: [:],
            from: nil, to: at(day: 9, hour: 12),
            includesUtterances: false)
        #expect(report.suggestedFileName.hasPrefix("Blaster"))
        #expect(UsageReportRenderer.render(report).prefix(4) == Data("%PDF".utf8))
    }
}
}
