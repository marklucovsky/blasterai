// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NavigationCoordinator.swift
//  claudeBlast
//

import SwiftUI

/// Shared navigation state extracted from TileGridView so that both the grid
/// and TileScriptRunner can read/write the current page and its history.
@Observable
@MainActor
final class NavigationCoordinator {
    var currentPageKey: String?
    var navigationPath: [String] = []

    /// Called for every page change a press caused — a link tile, Home, Back —
    /// with the page it was made on, the page it opened, and the tile pressed.
    /// `navigateHome` (a scene switch, not a press) does not call it.
    ///
    /// A hook rather than a log call here so the board and TileScript, which
    /// both drive this, are recorded the same way without either knowing.
    var onPress: ((_ from: String, _ to: String, _ linkKey: String) -> Void)?

    /// The page showing now. `currentPageKey` is nil on the home page.
    private var showingPageKey: String { currentPageKey ?? navigationPath.first ?? "" }

    /// Reset navigation to the home page of the given scene.
    func navigateHome(homePageKey: String) {
        currentPageKey = nil
        navigationPath = [homePageKey]
    }

    /// How many pages of history Back can retrace. A child ping-ponging
    /// between two linked pages (food ↔ drinks) would otherwise grow it for
    /// the whole session; the home page at the root is always kept.
    static let maxHistory = 50

    /// Navigate to a specific page key, recording it in the history.
    ///
    /// **A true history, not a breadcrumb.** This used to truncate on a revisit
    /// — going back to a page already on the path cut the path back to it — so
    /// `eat → drinks → food` collapsed to `[home, food]` and Back had nowhere to
    /// go, though the child had plainly come from drinks. Back now retraces what
    /// the child did, hop by hop, the way a browser's does.
    ///
    /// Two exceptions. The home page resets the history, exactly as the Home
    /// button does. A link to the page already showing changes nothing.
    func navigate(to pageKey: String, linkKey: String? = nil) {
        let from = showingPageKey
        defer { onPress?(from, pageKey, linkKey ?? pageKey) }
        if pageKey == navigationPath.first {
            navigationPath = [pageKey]
        } else if pageKey != navigationPath.last {
            navigationPath.append(pageKey)
            if navigationPath.count > Self.maxHistory {
                navigationPath.remove(at: 1)
            }
        }
        currentPageKey = pageKey
    }

    /// Whether there is anywhere to go back to.
    ///
    /// Back is a fixed control on the rail now, so it works one level down as
    /// well, where it lands on home. It used to share Home's cell and appear
    /// only two levels down, where it added a destination Home could not reach.
    var canGoBack: Bool { navigationPath.count > 1 }

    /// What a script writes for a Back tap: `<back>`. The history is a true
    /// history now, so recording where Back *landed* would replay as a forward
    /// step and leave a different history behind; recording the Back itself
    /// replays exactly. No page may use this key.
    static let backPageKey = "back"

    /// Step back one page along the history.
    func goBack() {
        guard canGoBack else { return }
        let from = showingPageKey
        navigationPath.removeLast()
        // Back onto home is home, as the Home button leaves it.
        currentPageKey = navigationPath.count == 1 ? nil : navigationPath.last
        onPress?(from, showingPageKey, Self.backPageKey)
    }

    /// Show a page as though it had been reached by opening `path` from home,
    /// one folder at a time — what Find Word does — so Back and Home behave
    /// afterwards exactly as they would after those taps.
    ///
    /// Not a press, so `onPress` is not called: the caregiver went there, the
    /// child did not, and the navigation log is the child's.
    func show(path: [String], homePageKey: String) {
        navigationPath = [homePageKey] + path.suffix(Self.maxHistory - 1)
        currentPageKey = path.last
    }

    /// Navigate home (nil key) — pops breadcrumb to root.
    func navigateToRoot() {
        let from = showingPageKey
        if let home = navigationPath.first {
            navigationPath = [home]
        }
        currentPageKey = nil
        onPress?(from, showingPageKey, Self.homeLinkKey)
    }

    /// The `linkKey` a Home press is logged under.
    static let homeLinkKey = "home"
}
