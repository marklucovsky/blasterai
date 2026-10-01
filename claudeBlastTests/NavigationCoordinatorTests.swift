// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NavigationCoordinatorTests.swift
//  claudeBlastTests
//

import Testing
@testable import claudeBlast

/// Back, as the board's Home cell offers it. See `HomeGridCell`.
@MainActor
struct NavigationCoordinatorTests {

    private func at(_ pages: String...) -> NavigationCoordinator {
        let c = NavigationCoordinator()
        c.navigateHome(homePageKey: "home")
        for p in pages { c.navigate(to: p) }
        return c
    }

    /// One level down, the previous page is home, and Home already goes there.
    @Test func noBackOnHomeOrItsChildren() {
        #expect(!at().canGoBack)
        #expect(!at("groups").canGoBack)
    }

    @Test func backFromAGrandchildReturnsToItsParent() {
        let c = at("groups", "feelings")
        #expect(c.canGoBack)
        c.goBack()
        #expect(c.currentPageKey == "groups")
        #expect(c.navigationPath == ["home", "groups"])
        #expect(!c.canGoBack)   // now one level down: Home's job again
    }

    /// Sideways trips count: actions → food → drinks retraces through food.
    @Test func backRetracesASidewaysRoute() {
        let c = at("actions", "food", "drinks")
        c.goBack()
        #expect(c.currentPageKey == "food")
        c.goBack()
        #expect(c.currentPageKey == "actions")
    }

    /// Eat → drinks → food is a loop back to food, and Back still goes to
    /// drinks: it retraces what the child did, not the shortest route. The
    /// path used to collapse loops, which left Back with nowhere to go.
    @Test func backRetracesALoop() {
        let c = at("food", "drinks", "food")
        #expect(c.navigationPath == ["home", "food", "drinks", "food"])
        #expect(c.canGoBack)
        c.goBack()
        #expect(c.currentPageKey == "drinks")
        c.goBack()
        #expect(c.currentPageKey == "food")
    }

    /// The home page resets the history, as the Home button does.
    @Test func reachingHomeResetsTheHistory() {
        let c = at("groups", "feelings", "home")
        #expect(c.navigationPath == ["home"])
        #expect(!c.canGoBack)
    }

    /// A link to the page already showing is not a step.
    @Test func samePageIsNotAStep() {
        let c = at("food", "food")
        #expect(c.navigationPath == ["home", "food"])
    }

    /// Ping-ponging between two pages for a whole session must not grow the
    /// history without bound. Home stays at the root.
    @Test func historyIsCapped() {
        let c = at()
        for i in 0..<200 { c.navigate(to: i.isMultiple(of: 2) ? "food" : "drinks") }
        #expect(c.navigationPath.count == NavigationCoordinator.maxHistory)
        #expect(c.navigationPath.first == "home")
        #expect(c.currentPageKey == "drinks")
    }

    @Test func backWithNowhereToGoIsANoOp() {
        let c = at("groups")
        c.goBack()
        #expect(c.currentPageKey == "groups")
        #expect(c.navigationPath == ["home", "groups"])
    }
}
