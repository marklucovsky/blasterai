// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NavigationLogTests.swift
//  claudeBlastTests
//
//  Link presses: what the coordinator reports, how coverage counts a page's
//  folders, and how page changes read in the activity log.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct NavigationLogTests {

    private typealias Press = (from: String, to: String, link: String)

    private func coordinator(recording presses: @escaping (Press) -> Void) -> NavigationCoordinator {
        let c = NavigationCoordinator()
        c.navigateHome(homePageKey: "home")
        c.onPress = { presses(($0, $1, $2)) }
        return c
    }

    private func nav(_ from: String, _ to: String, link: String? = nil,
                     at offset: TimeInterval = 0) -> LoggedNavigation {
        LoggedNavigation(fromPageKey: from, toPageKey: to, linkKey: link ?? to,
                         createdAt: Date(timeIntervalSince1970: 1_000_000 + offset))
    }

    private func said(_ keys: [String], at offset: TimeInterval) -> LoggedUtterance {
        LoggedUtterance(tileKeys: keys, sentence: keys.joined(separator: " "),
                        createdAt: Date(timeIntervalSince1970: 1_000_000 + offset))
    }

    // MARK: - Coordinator

    /// Every press that changes page is reported with where it was made, where
    /// it went, and the tile pressed — Home and Back included, since a child
    /// going Home again and again is the trail worth seeing.
    @Test func everyPressReportsFromToAndTile() {
        var presses: [Press] = []
        let c = coordinator { presses.append($0) }

        c.navigate(to: "food", linkKey: "eat")
        c.navigate(to: "drinks")
        c.goBack()
        c.navigateToRoot()

        #expect(presses.map(\.from) == ["home", "food", "drinks", "food"])
        #expect(presses.map(\.to) == ["food", "drinks", "food", "home"])
        #expect(presses.map(\.link) == ["eat", "drinks", NavigationCoordinator.backPageKey,
                                        NavigationCoordinator.homeLinkKey])
    }

    /// A scene switch resets the board; nobody pressed anything.
    @Test func aSceneSwitchIsNotAPress() {
        var presses: [Press] = []
        let c = coordinator { presses.append($0) }
        c.navigateHome(homePageKey: "home")
        #expect(presses.isEmpty)
    }

    /// Back with nowhere to go does nothing, and reports nothing.
    @Test func aBackThatGoesNowhereIsNotLogged() {
        var presses: [Press] = []
        let c = coordinator { presses.append($0) }
        c.navigate(to: "food")
        c.goBack()                       // food's parent is home: not a Back
        #expect(presses.count == 1)
    }

    // MARK: - Coverage

    private func page(_ key: String, _ tiles: [TileEntry]) -> PageSpec {
        PageSpec(key: key, tiles: tiles)
    }

    /// A folder is a cell the page offers. Opened from this page, it counts;
    /// never opened, it is a dimmed cell like an unpressed word.
    @Test func aFolderOpenedFromThePageCountsAsUsed() {
        let pages = [page("home", [TileEntry(key: "want"),
                                   TileEntry(key: "food", link: "food", isAudible: false),
                                   TileEntry(key: "places", link: "places", isAudible: false)])]
        let report = CoverageReport.make(
            sceneName: "S", pages: pages, inWindow: [], allTime: [],
            navigations: [nav("home", "food")])
        let home = try! #require(report.usageByPage.first)
        #expect(home.available == 3)
        #expect(home.linkCount == 2)
        #expect(home.usedKeys == ["food"])
        // Folders are cells, not vocabulary: the scene's word count is unchanged.
        #expect(report.sceneWordCount == 1)
    }

    /// A press is credited to the page it was made on. Opening Food from Groups
    /// says nothing about Home's Food folder.
    @Test func aFolderOpenedFromElsewhereDoesNotCount() {
        let pages = [page("home", [TileEntry(key: "food", link: "food", isAudible: false)])]
        let report = CoverageReport.make(
            sceneName: "S", pages: pages, inWindow: [], allTime: [],
            navigations: [nav("groups", "food")])
        #expect(report.usageByPage.first?.used == 0)
    }

    /// `eat` speaks and opens Food. Either record of the press reaches it:
    /// the utterance (its word) or the navigation (its link).
    @Test func aWordThatAlsoOpensAPageCountsFromEitherRecord() {
        let pages = [page("home", [TileEntry(key: "eat", link: "food", isAudible: true)])]
        let fromWord = CoverageReport.make(
            sceneName: "S", pages: pages, inWindow: [],
            allTime: [LoggedUtterance(tileKeys: ["eat"], sentence: "eat", pageKeys: ["home"])])
        let fromLink = CoverageReport.make(
            sceneName: "S", pages: pages, inWindow: [], allTime: [],
            navigations: [nav("home", "food", link: "eat")])
        #expect(fromWord.usageByPage.first?.used == 1)
        #expect(fromLink.usageByPage.first?.used == 1)
    }

    /// `eat` opens Food. A TileScript `<food>` knows only the page, so the
    /// press is matched to the folder by where it landed.
    @Test func aFolderIsCreditedByThePageItOpens() {
        let pages = [page("home", [TileEntry(key: "eat", link: "food", isAudible: true),
                                   TileEntry(key: "drink", link: "drinks", isAudible: true)])]
        let report = CoverageReport.make(
            sceneName: "S", pages: pages, inWindow: [], allTime: [],
            navigations: [nav("home", "food")])          // linkKey "food", not "eat"
        #expect(report.usageByPage.first?.usedKeys == ["eat"])
    }

    /// Spacers and concealed cells hold a place but offer nothing to press.
    @Test func emptyCellsAreNotCounted() {
        let pages = [page("home", [TileEntry(key: "want"),
                                   TileEntry(key: TileToken.newSpacerKey()),
                                   TileEntry(key: "more", isConcealed: true)])]
        let report = CoverageReport.make(sceneName: "S", pages: pages, inWindow: [], allTime: [])
        let home = try! #require(report.usageByPage.first)
        #expect(home.available == 1)
        #expect(home.keys == ["want"])
        // The layout keeps every cell, for drawing.
        #expect(home.entries.count == 3)
    }

    /// Replaces `CoverageReportTests.aNavigationOnlyPageIsOmitted`, which this
    /// change deliberately inverts: a page of nothing but folders is a page of
    /// choices, and a folder nobody opens is a finding.
    @Test func aPageOfOnlyFoldersGetsARow() {
        let pages = [page("groups", [TileEntry(key: "animals", link: "animals", isAudible: false)])]
        let report = CoverageReport.make(sceneName: "S", pages: pages, inWindow: [], allTime: [])
        #expect(report.usageByPage.map(\.pageKey) == ["groups"])
        #expect(report.usageByPage.first?.available == 1)
    }

    /// The bug this fixes: BlasterAI 60's Home read "of 47" on a page with 59
    /// cells. Its grid is 12 × 5 with Home in cell 0, so a full page offers 59.
    @Test func blasterAI60HomeCountsEveryCell() throws {
        let scene = BootstrapLoader.loadDefaultVocabulary(
            context: TestStore.freshContainer().mainContext).scene
        let report = CoverageReport.make(sceneName: scene.name, pages: scene.pages,
                                         inWindow: [], allTime: [])
        let home = try #require(report.usageByPage.first { $0.pageKey == scene.homePageKey })
        let grid = try #require(scene.designedLayout?.grid)
        #expect(home.available == grid.cols * grid.rows - 1)
        #expect(home.available == 59)
        #expect(home.linkCount >= 11)
    }

    // MARK: - Activity

    /// Wandering with nothing said is a sitting of its own — the lost child.
    @Test func pageChangesAloneMakeASession() {
        let sessions = ActivityGrouping.sessions(
            [], navigations: [nav("home", "actions", at: 0), nav("actions", "home", at: 5),
                              nav("home", "groups", at: 9), nav("groups", "home", at: 14)])
        #expect(sessions.count == 1)
        #expect(sessions.first?.count == 0)
        #expect(sessions.first?.navigations.count == 4)
    }

    /// A page change bridges two sentences that would otherwise be separate
    /// sittings: the child never left.
    @Test func pageChangesExtendASession() {
        let gap = ActivityGrouping.sessionGap
        let utterances = [said(["want"], at: 0), said(["more"], at: gap * 1.6)]
        #expect(ActivityGrouping.sessions(utterances).count == 2)
        let bridged = ActivityGrouping.sessions(
            utterances, navigations: [nav("home", "food", at: gap * 0.8)])
        #expect(bridged.count == 1)
    }

    /// Between two sentences, a run of page changes reads as one trail.
    @Test func consecutivePageChangesCollapseIntoOneTrail() {
        let timeline = ActivityGrouping.timeline(
            [said(["want"], at: 0), said(["pizza"], at: 30)],
            [nav("home", "actions", at: 5), nav("actions", "home", at: 8),
             nav("home", "food", at: 12)])
        #expect(timeline.count == 3)
        guard case .moved(let trail) = timeline[1] else {
            Issue.record("expected a trail between the two sentences")
            return
        }
        #expect(ActivityGrouping.trailPages(trail) == ["home", "actions", "home", "food"])
    }

    /// Counts stay counts of what was said. Page changes are not utterances.
    @Test func pageChangesDoNotCountAsSaid() {
        let sessions = ActivityGrouping.sessions(
            [said(["want"], at: 0)], navigations: [nav("home", "food", at: 5)])
        #expect(sessions.first?.count == 1)
        #expect(sessions.first?.distinctWordCount == 1)
    }
}
}
