// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordPlaces.swift
//  claudeBlast
//
//  Where a word is on the boards — CoughDrop's "Find a Button", for Manage
//  Vocabulary. A caregiver asked "where is `hurt`?" needs the taps that get
//  there, not a page key: "BlasterAI 60 › Groups › Body Health". And all of them,
//  because since the session-8 placement pass a word can have several homes
//  (`hurt` is on Feelings, Body & Health and Actions) in several scenes.
//

import Foundation

/// One place a word appears: a page of a scene, and the route to it.
struct WordPlace: Hashable {
    let sceneName: String
    /// Page titles from the scene's home to the page, excluding home itself —
    /// `["Groups", "Animals"]`. Empty when the word is on the home page.
    let route: [String]
    /// The page's title, for a page no folder leads to (`route` is empty then).
    let pageTitle: String
    /// 1-based screen of the page the word lands on, on the scene's grid.
    let screen: Int
    /// False when no chain of folders from home reaches the page — the word
    /// is in the scene but a child cannot get to it.
    let isReachable: Bool

    /// "BlasterAI 60 › Groups › Animals", "BlasterAI 60 › Home",
    /// "BlasterAI 60 › Actions · screen 2", "BlasterAI 60 › Spare (no folder leads here)".
    var label: String {
        var parts = [sceneName]
        if !isReachable {
            parts.append(pageTitle)
        } else if route.isEmpty {
            parts.append("Home")
        } else {
            parts += route
        }
        var text = parts.joined(separator: " › ")
        if screen > 1 { text += " · screen \(screen)" }
        if !isReachable { text += " (no folder leads here)" }
        return text
    }
}

enum WordPlaces {

    /// Every place every word appears, across `scenes`.
    ///
    /// Scenes are ordered active first, then the default, then by name, so the
    /// first line under a word is where the child will find it today. Within a
    /// scene, the shortest route comes first.
    ///
    /// - Parameters:
    ///   - hidden: keys hidden from the child (retired / needs review). The
    ///     board reflows around them, so they change which screen a later
    ///     word lands on — the same filter `TileGridView` applies.
    ///   - grid: the grid for a scene — its declared one, or this device's.
    static func index(scenes: [BlasterScene], hidden: Set<String>,
                      grid: (BlasterScene) -> (cols: Int, rows: Int)) -> [String: [WordPlace]] {
        let ordered = scenes.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.baseName.localizedCaseInsensitiveCompare(b.baseName) == .orderedAscending
        }
        var result: [String: [WordPlace]] = [:]
        for scene in ordered {
            for (key, places) in index(scene: scene, hidden: hidden, grid: grid(scene)) {
                result[key, default: []] += places
            }
        }
        return result
    }

    /// The places in one scene, keyed by word.
    static func index(scene: BlasterScene, hidden: Set<String>,
                      grid: (cols: Int, rows: Int)) -> [String: [WordPlace]] {
        // The board as the child has it: above-level words are not places yet.
        let pages = scene.visiblePages
        let routes = routesFromHome(pages: pages, homeKey: scene.homePageKey)
        // Home takes cell 0 of every screen.
        let perScreen = max(1, grid.cols * grid.rows - 1)

        var result: [String: [WordPlace]] = [:]
        var seen = Set<String>()
        for page in pages {
            let visible = page.tiles.filter { $0.isEmptyCell || !hidden.contains($0.key) }
            for (i, entry) in visible.enumerated() where !entry.isEmptyCell {
                let route = routes[page.key]
                let place = WordPlace(sceneName: scene.baseName,
                                      route: route ?? [],
                                      pageTitle: page.title,
                                      screen: i / perScreen + 1,
                                      isReachable: route != nil)
                // A word twice on one screen is one place.
                guard seen.insert("\(entry.key)|\(page.key)|\(place.screen)").inserted else { continue }
                result[entry.key, default: []].append(place)
            }
        }
        for key in result.keys {
            result[key]?.sort { a, b in
                if a.isReachable != b.isReachable { return a.isReachable }
                return a.route.count < b.route.count
            }
        }
        return result
    }

    /// The shortest folder route from home to each page, as page titles.
    /// Breadth-first, following folders in page and cell order, so among
    /// equally short routes the one a child meets first wins. A page absent
    /// from the result is not reachable from home.
    static func routesFromHome(pages: [PageSpec], homeKey: String) -> [String: [String]] {
        let byKey = Dictionary(pages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return pathsFromHome(pages: pages, homeKey: homeKey)
            .mapValues { path in path.compactMap { byKey[$0]?.title } }
    }

    /// Where a page sits in the hierarchy, as titles from home: `Home ›
    /// Describe › How much`. Folders first, so a page a doorway also opens is
    /// placed under its category; a page only a doorway reaches comes next, and
    /// a page nothing reaches is just its own title.
    static func trail(to key: String, pages: [PageSpec], homeKey: String) -> [String] {
        let byKey = Dictionary(pages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let home = byKey[homeKey]?.title ?? PageNaming.displayName(homeKey)
        return [home] + trailKeys(to: key, pages: pages, homeKey: homeKey)
            .map { byKey[$0]?.title ?? PageNaming.displayName($0) }
    }

    /// `trail` as page keys, home left out: the pages whose tiles the board
    /// marks "you are here" (the last) and "on the way here" (the rest).
    static func trailKeys(to key: String, pages: [PageSpec], homeKey: String) -> [String] {
        let path = pathsFromHome(pages: pages, homeKey: homeKey, followDoorways: false)[key]
            ?? pathsFromHome(pages: pages, homeKey: homeKey)[key]
            ?? [key]
        return path.filter { $0 != homeKey }
    }

    /// `routesFromHome` as page keys rather than titles — the pages to open, in
    /// order, to reach each page. Find Word walks these.
    ///
    /// `followDoorways: false` walks folders only, leaving out words that also
    /// open a page (*wear* → Clothes from Actions): the route the hierarchy
    /// gives, not a shortcut into it.
    static func pathsFromHome(pages: [PageSpec], homeKey: String,
                              followDoorways: Bool = true) -> [String: [String]] {
        let byKey = Dictionary(pages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        guard byKey[homeKey] != nil else { return [:] }
        var paths: [String: [String]] = [homeKey: []]
        var queue = [homeKey]
        while !queue.isEmpty {
            let key = queue.removeFirst()
            guard let page = byKey[key], let here = paths[key] else { continue }
            // A concealed folder is not a way in: the child sees an empty cell.
            for entry in page.tiles where !entry.link.isEmpty && !entry.isEmptyCell
                && (followDoorways || !entry.isAudible) {
                let target = entry.link == TileToken.home ? homeKey : entry.link
                guard paths[target] == nil, byKey[target] != nil else { continue }
                paths[target] = here + [target]
                queue.append(target)
            }
        }
        return paths
    }
}
