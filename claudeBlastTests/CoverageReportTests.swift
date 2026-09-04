// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoverageReportTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CoverageReportTests {

    private func utterance(_ keys: [String], daysAgo: Int = 0,
                           pages: [String] = []) -> LoggedUtterance {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return LoggedUtterance(tileKeys: keys, sentence: "s",
                               pageKeys: pages, createdAt: when)
    }

    private func page(_ key: String, _ tiles: [(String, String)]) -> PageSpec {
        PageSpec(key: key, tiles: tiles.map { TileEntry(key: $0.0, link: $0.1, isAudible: true) })
    }

    // MARK: - Vocabulary

    /// A page link is a door, not a word.
    ///
    /// Counting it as vocabulary inflates the scene and drops a word the child
    /// cannot say into "never used" — where it sits forever, because it is not a
    /// word and can never be pressed as one. This is the same confusion that
    /// once sent `body_health` through word moderation.
    @Test func vocabularyExcludesPageLinks() {
        let keys = CoverageReport.vocabularyKeys(of: [
            page("home", [("want", ""), ("food", "food_page"), ("more", "")]),
        ])
        #expect(keys == ["want", "more"])
    }

    /// A word on three pages is one word, and page order decides which.
    @Test func vocabularyDeduplicatesAcrossPages() {
        let keys = CoverageReport.vocabularyKeys(of: [
            page("home", [("want", ""), ("more", "")]),
            page("food", [("more", ""), ("pizza", "")]),
        ])
        #expect(keys == ["want", "more", "pizza"])
    }

    // MARK: - Coverage

    /// Coverage counts DISTINCT words, not presses. Saying "want" forty times
    /// reaches one word, and a report that let repetition inflate coverage would
    /// flatter exactly the child who needs the opposite reading.
    @Test func coverageCountsDistinctWordsNotPresses() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("want", ""), ("more", ""), ("eat", "")])],
            inWindow: Array(repeating: utterance(["want"]), count: 40),
            allTime: Array(repeating: utterance(["want"]), count: 40)
        )
        #expect(report.usedCount == 1)
        #expect(report.sceneWordCount == 3)
    }

    /// Words said that are not in this scene are reported, not silently dropped.
    /// Without the count the rows fail to add up and nothing on screen says why.
    @Test func offSceneWordsAreCountedSeparately() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("want", "")])],
            inWindow: [utterance(["want", "elephant", "trombone"])],
            allTime: [utterance(["want", "elephant", "trombone"])]
        )
        #expect(report.usedCount == 1)
        #expect(report.offSceneWordCount == 2)
    }

    /// Words the index cannot classify are surfaced rather than dropped. On a
    /// heavily customised scene they could be most of it, and coverage bars that
    /// quietly omit them would describe a scene nobody has.
    @Test func unclassifiedSceneWordsAreCounted() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("want", ""), ("zzz_not_a_real_key", "")])],
            inWindow: [],
            allTime: []
        )
        #expect(report.unclassifiedCount == 1)
    }

    /// A kind the scene carries none of is omitted, not shown as nought of
    /// nought — that is a scene-authoring question, not a usage one.
    @Test func absentKindsAreOmittedFromCoverage() {
        let report = CoverageReport.make(
            sceneName: "B", pages: [page("p", [("want", "")])], inWindow: [], allTime: []
        )
        #expect(report.coverage.allSatisfy { $0.available > 0 })
    }

    // MARK: - Never used

    /// Never-used is measured all-time, so a word used last month does not
    /// reappear as never used just because this week was quiet.
    @Test func neverUsedIsAllTimeNotWindowed() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("want", ""), ("more", "")])],
            inWindow: [],
            allTime: [utterance(["want"], daysAgo: 40)]
        )
        #expect(report.allTimeUsedCount == 1)
        #expect(report.neverUsedCount == 1)
    }

    /// Ranked by SHARE of its own kind, not by raw count.
    ///
    /// This is the whole point of the section. By count, the biggest kind wins
    /// every time — a fact about the scene. By share, a kind that is wholly
    /// untouched rises above a larger one that is merely mostly untouched, which
    /// is the finding a therapist acts on.
    ///
    /// Stated as utilisation, ranked most-used first — so the wholly untouched
    /// kind sorts LAST, where the 0% rows collect together.
    @Test func usageRanksByShareNotCount() {
        // `what` is the only question word here and is untouched (100%);
        // the verbs are numerous and mostly untouched, but not entirely.
        let verbs = PartOfSpeechIndex.keys(.verb).prefix(20).map { $0 }
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", (verbs + ["what"]).map { ($0, "") })],
            inWindow: [],
            allTime: [utterance(Array(verbs.prefix(4)))]
        )
        let last = try! #require(report.usageByKind.last)
        #expect(last.partOfSpeech == .question)
        #expect(last.usedFraction == 0.0)
        // The verb row has more never-used words in absolute terms and still
        // ranks above — the sort is on share, not count.
        let verbRow = try! #require(report.usageByKind.first { $0.partOfSpeech == .verb })
        #expect(verbRow.neverUsed > last.neverUsed)
        #expect(verbRow.usedFraction > last.usedFraction)
    }

    /// A fully-used kind is KEPT, and reads as 100%.
    ///
    /// It used to be filtered out, which was right while the column meant "never
    /// used" — a zero row there said nothing. Read as utilisation it is a
    /// result, and dropping it would make the list silently incomplete.
    @Test func fullyUsedKindsAreShownAtOneHundredPercent() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("what", "")])],
            inWindow: [utterance(["what"])],
            allTime: [utterance(["what"])]
        )
        let row = try! #require(report.usageByKind.first { $0.partOfSpeech == .question })
        #expect(row.usedFraction == 1.0)
        #expect(report.neverUsedCount == 0)
        #expect(report.usedFraction == 1.0)
    }

    // MARK: - By page

    /// A press is credited to the page it was made on, and to no other.
    ///
    /// The whole reason `LoggedUtterance.pageKeys` exists. Crediting every page
    /// that carries a used word is the obvious reconstruction and it fails
    /// exactly where the section is useful: Food here is buried and untouched,
    /// but shares `more` with Home, so the reconstruction would score it as
    /// partly used on the strength of a press made on Home.
    @Test func aPressIsCreditedOnlyToThePageItWasMadeOn() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [
                page("home", [("want", ""), ("more", "")]),
                page("food", [("more", ""), ("pizza", "")]),
            ],
            inWindow: [utterance(["want", "more"], pages: ["home", "home"])],
            allTime: [utterance(["want", "more"], pages: ["home", "home"])]
        )
        let food = try! #require(report.usageByPage.first { $0.pageKey == "food" })
        #expect(food.available == 2)
        #expect(food.used == 0)          // `more` was pressed on home, not here
        #expect(food.usedFraction == 0.0)
        // Home is fully used and still listed — utilisation keeps its 100% rows.
        let home = try! #require(report.usageByPage.first { $0.pageKey == "home" })
        #expect(home.usedFraction == 1.0)
        // Most-used first, so the untouched page is last.
        #expect(report.usageByPage.first?.pageKey == "home")
        #expect(report.usageByPage.last?.pageKey == "food")
        #expect(report.unattributedPresses == 0)
    }

    /// Rows written before pages were recorded are counted as unattributed
    /// rather than guessed at, so the shortfall is visible instead of silently
    /// depressing every page.
    @Test func presetsWithoutPagesAreCountedNotGuessed() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [page("home", [("want", ""), ("more", "")])],
            inWindow: [utterance(["want", "more"])],
            allTime: [utterance(["want", "more"])]
        )
        #expect(report.unattributedPresses == 2)
        let home = try! #require(report.usageByPage.first { $0.pageKey == "home" })
        #expect(home.used == 0)
        #expect(home.usedFraction == 0.0)
    }

    /// A page with no vocabulary of its own contributes no row — pure
    /// navigation. A 0-of-0 row would read as a finding and is only an absence.
    @Test func aNavigationOnlyPageIsOmitted() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [
                page("home", [("food", "food")]),
                page("food", [("pizza", "")]),
            ],
            inWindow: [],
            allTime: []
        )
        // Home is pure navigation and contributes no row at all.
        #expect(report.usageByPage.map(\.pageKey) == ["food"])
    }

    // MARK: - Drill-down keys

    /// A page carries its words in PAGE ORDER, which is what the drill-down grid
    /// lays out.
    ///
    /// Sorting them would destroy the only thing the grid adds over a
    /// percentage: laid out as the child sees them, an untouched bottom row
    /// reads as a reaching problem rather than a vocabulary one. Alphabetical
    /// order would scatter that shape.
    @Test func aPageCarriesItsWordsInPageOrder() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [page("home", [("zebra", ""), ("apple", ""), ("mango", "")])],
            inWindow: [],
            allTime: [utterance(["apple"], pages: ["home"])]
        )
        let home = try! #require(report.usageByPage.first)
        #expect(home.keys == ["zebra", "apple", "mango"])
        #expect(home.usedKeys == ["apple"])
    }

    /// A word repeated on a page appears once — the grid draws cells, not
    /// presses.
    @Test func aPageDeduplicatesItsWordsButKeepsFirstPosition() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [page("home", [("more", ""), ("eat", ""), ("more", "")])],
            inWindow: [],
            allTime: []
        )
        #expect(report.usageByPage.first?.keys == ["more", "eat"])
    }

    /// A part of speech has no board position, so its words are alphabetical —
    /// and the view says so rather than inviting a layout reading that is not
    /// there.
    @Test func aKindCarriesItsWordsAlphabetically() {
        let verbs = PartOfSpeechIndex.keys(.verb).prefix(5).map { $0 }
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [page("p", verbs.reversed().map { ($0, "") })],
            inWindow: [],
            allTime: []
        )
        let row = try! #require(report.usageByKind.first { $0.partOfSpeech == .verb })
        #expect(row.keys == verbs.sorted())
    }

    /// The keys and the counts must describe the same set — a row saying "3 of
    /// 10" and then opening onto eleven tiles is worse than no drill-down.
    @Test func keysAndCountsAgree() {
        let report = CoverageReport.make(
            sceneName: "S",
            pages: [page("home", [("want", ""), ("more", ""), ("eat", "")])],
            inWindow: [],
            allTime: [utterance(["want", "more"], pages: ["home", "home"])]
        )
        for row in report.usageByPage {
            #expect(row.keys.count == row.available)
            #expect(row.usedKeys.count == row.used)
        }
        for row in report.usageByKind {
            #expect(row.keys.count == row.available)
            #expect(row.usedKeys.count == row.used)
        }
    }

    // MARK: - Went quiet

    /// Used before, not in the window — and nothing else. A word never used at
    /// all has not gone quiet; it never spoke.
    @Test func wentQuietIsUsedBeforeButNotNow() {
        let report = CoverageReport.make(
            sceneName: "B",
            pages: [page("p", [("want", ""), ("more", ""), ("eat", "")])],
            inWindow: [utterance(["want"])],
            allTime: [utterance(["want"]), utterance(["more"], daysAgo: 40)]
        )
        #expect(report.wentQuiet == ["more"])
    }

    // MARK: - Empty

    /// An empty scene divides by nothing and reports nothing, rather than
    /// trapping or reporting a NaN share.
    @Test func anEmptySceneIsSafe() {
        let report = CoverageReport.make(
            sceneName: "B", pages: [], inWindow: [], allTime: []
        )
        #expect(report.sceneWordCount == 0)
        #expect(report.neverUsedFraction == 0)
        #expect(report.usedFraction == 0)
        #expect(report.coverage.isEmpty)
    }
}
}
