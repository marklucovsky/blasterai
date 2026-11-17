// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageChoice.swift
//  claudeBlast
//
//  Pages to choose from, named by where they are rather than by key.
//

import Foundation

/// A page a chooser offers, named the way the board reaches it.
///
/// A caregiver never sees a page's key on the board: they go Home ›
/// Groups › Animals. A chooser that listed `animals`, or even the title
/// "Animals" alone, made them learn a second naming scheme to link a folder
/// (Mark, 2026-11-16). The route is the name they already know.
struct PageOption: Identifiable, Hashable {
    /// What choosing it hands back: a page key, or a link to one.
    let value: String
    /// The board whose page it is, the section it is listed under.
    let board: String
    /// Titles from home, home left out, ending in this page's own; empty for
    /// home itself.
    let route: [String]
    /// The page's own title; for home, home's.
    let title: String
    /// The value of the folder page it is listed under when browsing, the
    /// last step of its route before itself; nil at the top of its board.
    var parent: String? = nil
    /// The words on the page, folded for search (`ice cream`), so a search
    /// for a word finds the page to pick even when you don't know its name.
    var words: [String] = []

    var id: String { value }

    /// The route as one line, `Groups › Animals`, or the home page's title.
    var path: String { route.isEmpty ? title : route.joined(separator: " › ") }

    /// The steps before the page itself, `Groups ›`: what the row shows under
    /// the title. Empty for a page one step from home, and for home.
    var parents: String {
        route.count > 1 ? route.dropLast().joined(separator: " › ") + " ›" : ""
    }
}

/// One board's pages, in route order.
struct PageGroup: Identifiable, Hashable {
    let board: String
    var options: [PageOption]
    var id: String { board }

    /// The same pages handing back `transform(value)`, parents kept in step.
    func mapValues(_ transform: (String) -> String) -> PageGroup {
        PageGroup(board: board, options: options.map {
            PageOption(value: transform($0.value), board: $0.board, route: $0.route,
                       title: $0.title, parent: $0.parent.map(transform), words: $0.words)
        })
    }

    /// The pages as a tree for browsing: each under the folder its route
    /// passes through last. A page whose folder is not offered (home, or
    /// one left out) sits at the top.
    var tree: [PageNode] {
        let offered = Set(options.map(\.value))
        var children: [String: [PageOption]] = [:]
        var tops: [PageOption] = []
        for option in options {
            if let parent = option.parent, parent != option.value, offered.contains(parent) {
                children[parent, default: []].append(option)
            } else {
                tops.append(option)
            }
        }
        // Routes are a shortest-path tree, so no page is its own ancestor;
        // `seen` keeps a malformed board from looping anyway.
        var seen = Set<String>()
        func node(_ option: PageOption) -> PageNode? {
            guard seen.insert(option.value).inserted else { return nil }
            let kids = (children[option.value] ?? []).compactMap(node)
            return PageNode(option: option, children: kids.isEmpty ? nil : kids)
        }
        return tops.compactMap(node)
    }
}

/// A page in a board's tree, with the pages its folders open.
struct PageNode: Identifiable, Hashable {
    let option: PageOption
    /// nil for a page with nothing under it, so it shows no disclosure.
    let children: [PageNode]?
    var id: String { option.value }

    /// This node's value and every value beneath it.
    var allValues: [String] { [option.value] + (children ?? []).flatMap(\.allValues) }
}

enum PageChoice {
    /// `pages` of the board named `board`, each named by its route from
    /// `homeKey`: home first, then by route, so a page sits beneath the
    /// folder it is in. `value` turns a page key into what choosing it
    /// returns (a `sys:` link for a BlasterAI 60 page, say).
    ///
    /// The route is `WordPlaces.trail`'s: folders first, then doorways, then
    /// a page nothing reaches stands alone under its title.
    static func group(board: String, pages: [PageSpec], homeKey: String, row: [String] = [],
                      includeHome: Bool = true, excluding: Set<String> = [],
                      value: (String) -> String = { $0 }) -> PageGroup {
        let titles = Dictionary(pages.map { ($0.key, $0.title) }, uniquingKeysWith: { a, _ in a })
        // `trailKeys` per page walks the board twice each time: once both
        // ways, for every page, is the same answer.
        let folders = WordPlaces.pathsFromHome(pages: pages, homeKey: homeKey, followDoorways: false, row: row)
        let any = WordPlaces.pathsFromHome(pages: pages, homeKey: homeKey, row: row)
        var seen = Set<String>()
        let options = pages.compactMap { page -> PageOption? in
            guard !excluding.contains(page.key), includeHome || page.key != homeKey,
                  seen.insert(value(page.key)).inserted else { return nil }
            let keys = (page.key == homeKey ? [] : (folders[page.key] ?? any[page.key] ?? [page.key]))
                .filter { $0 != homeKey }
            let route = keys.map { titles[$0] ?? PageNaming.displayName($0) }
            let parent = keys.dropLast().last.map(value)
            let words = page.tiles.filter { $0.link.isEmpty && !$0.isConcealed }
                .map { WordFinder.normalize($0.key.replacingOccurrences(of: "_", with: " ")) }
            return PageOption(value: value(page.key), board: board, route: route,
                              title: page.title, parent: parent, words: words)
        }
        return PageGroup(board: board, options: options.sorted(by: inRouteOrder))
    }

    /// Home first; then by route, step by step, so a folder's pages follow it.
    static func inRouteOrder(_ a: PageOption, _ b: PageOption) -> Bool {
        if a.route.isEmpty != b.route.isEmpty { return a.route.isEmpty }
        for (x, y) in zip(a.route, b.route) where x != y {
            return x.localizedCaseInsensitiveCompare(y) == .orderedAscending
        }
        return a.route.count < b.route.count
    }

    /// The groups narrowed to pages whose route, title or board holds the
    /// query, then pages holding a word that starts with it; a group left
    /// empty is dropped.
    static func filter(_ groups: [PageGroup], query: String) -> [PageGroup] {
        let q = WordFinder.normalize(query)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            var out = group
            let named = group.options.filter { namesMatch($0, q) }
            let holding = group.options.filter { !namesMatch($0, q) && word(in: $0, startingWith: q) != nil }
            out.options = named + holding
            return out.options.isEmpty ? nil : out
        }
    }

    private static func namesMatch(_ option: PageOption, _ q: String) -> Bool {
        ([option.board, option.title] + option.route).contains { WordFinder.normalize($0).contains(q) }
    }

    /// Why a search found `option` when its name doesn't say: the first word
    /// on it starting with the query (whole word first). nil when its name
    /// matched, or nothing on it does.
    static func matchedWord(in option: PageOption, query: String) -> String? {
        let q = WordFinder.normalize(query)
        guard !q.isEmpty, !namesMatch(option, q) else { return nil }
        return word(in: option, startingWith: q)
    }

    private static func word(in option: PageOption, startingWith q: String) -> String? {
        if option.words.contains(q) { return q }
        return option.words.first { word in
            word.hasPrefix(q) || word.split(separator: " ").contains { $0.hasPrefix(q) }
        }
    }

    /// Values more than one group offers: a Me page context is a page name,
    /// so choosing Places on one board chooses it on every board.
    static func sharedValues(_ groups: [PageGroup]) -> Set<String> {
        var count: [String: Int] = [:]
        for group in groups { for option in group.options { count[option.value, default: 0] += 1 } }
        return Set(count.filter { $0.value > 1 }.keys)
    }

    /// Where `value` is, `BlasterAI 60 › Groups › Animals`; nil when no
    /// group has it.
    static func fullPath(of value: String, in groups: [PageGroup]) -> String? {
        for group in groups {
            if let option = group.options.first(where: { $0.value == value }) {
                return group.board + " › " + option.path
            }
        }
        return nil
    }
}

// MARK: - The choosers' page lists

extension PageChoice {
    /// Pages a tile on `scene` can link to: the scene's own, then each
    /// template's under its name (nearest first), then BlasterAI 60's. Each
    /// value is the link as stored: a bare key for the scene's own page, a
    /// `sys:` link for the rest. With no chain (editing BlasterAI 60 itself)
    /// only the scene's own.
    static func linkTargets(scene: BlasterScene, chain: TemplateChain?) -> [PageGroup] {
        var groups = [group(board: BlasterScene.copyRoot(of: scene.baseName), pages: scene.pages,
                            homeKey: scene.homePageKey, row: BoardChrome.rowPages(of: scene))]
        guard let chain else { return groups }
        // A template page under its template key; one a nearer template
        // already gives is left out, as `TemplateChain.pages` leaves it.
        var given = Set<String>()
        for template in chain.templates {
            let keys = Dictionary(template.pages.map { ($0.key, TemplateChain.templateKey(of: $0)) },
                                  uniquingKeysWith: { a, _ in a })
            let taken = Set(keys.filter { given.contains($0.value) }.keys)
            let g = group(board: BlasterScene.copyRoot(of: template.name), pages: template.pages,
                          homeKey: template.homePageKey, includeHome: false, excluding: taken,
                          value: { TileToken.systemLink(to: keys[$0] ?? $0) })
            given.formUnion(keys.values)
            if !g.options.isEmpty { groups.append(g) }
        }
        if let system = chain.system {
            groups.append(group(board: system.baseName, pages: system.pages,
                                homeKey: system.homePageKey, row: BoardChrome.rowPages(of: system),
                                value: { TileToken.systemLink(to: $0) }))
        }
        return groups
    }

    /// Pages of `scene` alone, by bare key.
    static func ownPages(of scene: BlasterScene, includeHome: Bool = true,
                         excluding: Set<String> = []) -> PageGroup {
        group(board: BlasterScene.copyRoot(of: scene.baseName), pages: scene.pages,
              homeKey: scene.homePageKey, row: BoardChrome.rowPages(of: scene),
              includeHome: includeHome, excluding: excluding)
    }

    /// The pages a Me page context can be for (`MeScene.contextChoices`), by
    /// board and route; the value is the context's page name, so a copy of a
    /// BlasterAI 60 page is chosen as that page.
    static func contextTargets(system: BlasterScene?, scenes: [BlasterScene],
                               excludingScene: String? = nil) -> [PageGroup] {
        var boards: [BlasterScene] = system.map { [$0] } ?? []
        boards += scenes.filter { scene in
            scene.sceneID != excludingScene && MeScene.offersContexts(scene)
        }
        return boards.compactMap { board in
            let shadows = Dictionary(board.pages.map {
                ($0.key, $0.isShadow ? TileToken.bareKey($0.shadows) : $0.key)
            }, uniquingKeysWith: { a, _ in a })
            let g = group(board: BlasterScene.copyRoot(of: board.name), pages: board.pages,
                          homeKey: board.homePageKey, row: BoardChrome.rowPages(of: board),
                          includeHome: false, value: { shadows[$0] ?? $0 })
            // A copy standing in for a page is reached as that page; its
            // home is the board's, which clears the context.
            var out = g
            out.options.removeAll { $0.value == board.homePageKey }
            return out.options.isEmpty ? nil : out
        }
    }
}
