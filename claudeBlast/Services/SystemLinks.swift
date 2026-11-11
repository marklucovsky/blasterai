// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SystemLinks.swift
//  claudeBlast
//
//  Where a link goes, for every scene: its own pages, Home, or a page of the
//  system scene (BlasterAI 60). See `TileToken.systemPrefix` for why scenes
//  link to the core board's pages rather than copying them.
//

import Foundation
import SwiftData

enum SystemLinks {
    /// The navigation key a tap on `link` leads to, made on the page showing
    /// as `fromPage` (itself a navigation key, so `<system>:actions` when the
    /// child is on BlasterAI 60's Actions page).
    ///
    /// - `<home>` is the active scene's home.
    /// - A `<system>:` link is already a navigation key.
    /// - On a system page, a plain link names a page of the system scene, so it
    ///   gains the prefix — except a link to the system scene's own home, which
    ///   is Home: the child is in *their* scene, and Home means its home.
    /// - A `<scene:ID>:` link is already a navigation key, and on a mounted
    ///   scene's page a plain link names a page of that scene.
    /// - Anywhere else a plain link is a page of the active scene.
    ///
    /// `systemIsActive`: the board *is* BlasterAI 60, so its pages are the
    /// active scene's and a `<system>:` link names one of them plainly. Only a
    /// mounted page (a Me page doorway to `<system>:i_page`) can carry such a
    /// link onto the system board; kept prefixed, it named a page nothing
    /// could find and the board showed "This Scene Has No Home Page".
    ///
    /// `shadowed`: the system pages the active scene has its own copy of
    /// (`PageSpec.shadows`). On such a page the links are the scene's — the
    /// copy's links to the core board were written out as `<system>:` when it
    /// was made — so a plain link there is a page of the scene.
    static func destination(of link: String, fromPage: String,
                            homePageKey: String, systemHomePageKey: String?,
                            systemIsActive: Bool = false,
                            shadowed: Set<String> = []) -> String {
        if link == TileToken.home { return homePageKey }
        if let systemKey = TileToken.systemPageKey(link) {
            guard systemIsActive else { return link }
            return systemKey == systemHomePageKey ? homePageKey : systemKey
        }
        if TileToken.scenePageKey(link) != nil { return link }
        if let mounted = TileToken.scenePageKey(fromPage) {
            return TileToken.sceneLink(mounted.sceneID, to: link)
        }
        if let fromSystem = TileToken.systemPageKey(fromPage) {
            if shadowed.contains(fromSystem) { return link }
            // A template's pages carry whole links (`TemplateChain.absolute`);
            // a plain one left on one is the template's page.
            if TileToken.isTemplateKey(fromSystem) { return TileToken.templateLink(to: link) }
            return link == systemHomePageKey ? homePageKey : TileToken.systemLink(to: link)
        }
        return link
    }

    /// The page a navigation key shows: the active scene's page, for a
    /// `<system>:` key the system scene's, and for a `<scene:ID>:` key the
    /// page of the mounted scene `mountedPages` finds for ID (nil when that
    /// scene is gone, e.g. deleted on another device).
    ///
    /// A `<system>:` key opens the scene's own copy of that page when it has
    /// one (copy-on-write, `PageSpec.shadows`), else BlasterAI 60's.
    ///
    /// A system page shows all its words. Graded reveal is set per scene, and
    /// the level a caregiver chose for BlasterAI 60 says nothing about a child
    /// who is using another board.
    static func page(forKey key: String, scenePages: [PageSpec],
                     systemPages: [PageSpec],
                     mountedPages: (String) -> [PageSpec]? = { _ in nil }) -> PageSpec? {
        if let systemKey = TileToken.systemPageKey(key) {
            if let own = scenePages.first(where: { $0.shadows == systemKey }) { return own }
            return systemPages.first { $0.key == systemKey }
        }
        if let mounted = TileToken.scenePageKey(key) {
            return mountedPages(mounted.sceneID)?.first { $0.key == mounted.page }
        }
        return scenePages.first { $0.key == key }
    }

    /// A short, readable name for where a link goes — "BlasterAI › Actions"
    /// for a system page, "Brandi Board › Random" for a template's — for the
    /// editor and for print.
    static func displayName(of link: String, chain: TemplateChain? = nil) -> String {
        if let systemKey = TileToken.systemPageKey(link) {
            let board = TileToken.isTemplateKey(systemKey)
                ? (chain?.owner(ofSystemPage: systemKey).map { BlasterScene.copyRoot(of: $0.name) } ?? "Template")
                : "BlasterAI"
            return board + " › " + PageNaming.displayName(systemKey)
        }
        if let mounted = TileToken.scenePageKey(link) {
            return PageNaming.displayName(mounted.page)
        }
        return PageNaming.displayName(link)
    }
}

/// The level dial of a board that reaches into BlasterAI 60.
///
/// One dial governs everything the child sees, the system pages included —
/// a level 2 zoo board must not open onto all of Actions. So the dial's range
/// is the wider of the two: a scene with 3 levels linking into a core board
/// with 5 steps 1…5, and at 4 or 5 its own pages are simply at their top
/// while the core board's keep revealing.
///
/// Nothing new is stored. The scene's `revealLevel` holds the dial and may sit
/// above the scene's own count; `effectiveRevealLevel` already reads that as
/// the scene's top, so `visiblePages` and every other reader of the scene's
/// own pages are unchanged. A scene without levels still opens at the top:
/// its stored 0 is out of range, which reads as the top here too.
struct BoardLevels {
    let scene: BlasterScene
    /// The system scene, when this board links into it; nil otherwise and
    /// for the system scene itself, whose dial is its own.
    let system: BlasterScene?
    /// The templates the scene is built on, ending at BlasterAI 60
    /// (`TemplateChain`); nil exactly when `system` is.
    let chain: TemplateChain?

    /// - Parameter templates: every scene marked as a template, for a scene
    ///   built on one. Without them the board is BlasterAI 60's, as before.
    init(scene: BlasterScene, system: BlasterScene?, templates: [BlasterScene] = []) {
        self.scene = scene
        // A scene under the system row reaches BlasterAI 60 from every page,
        // whether or not any page stores a link into it.
        if let system, system.persistentModelID != scene.persistentModelID,
           BoardChrome.inherits(scene) || Self.linksIntoSystem(scene.pages) {
            self.system = system
            self.chain = TemplateChain(scene: scene, templates: templates, system: system)
        } else {
            self.system = nil
            self.chain = nil
        }
    }

    /// Steps on the dial; 0 when neither board has levels.
    var count: Int { max(scene.revealLevelCount, chain?.revealLevelCount ?? 0) }

    /// The key `<system>:` links treat as Home.
    var systemHomePageKey: String? { chain?.homePageKey ?? system?.homePageKey }

    /// The navigation bar the scene's templates give it, when it has none of
    /// its own (`TemplateChain.navBar`).
    var inheritedNavBar: [TileEntry]? { chain?.navBar }

    /// Where the dial is, or nil when there are no levels.
    var level: Int? {
        guard count > 0 else { return nil }
        return (1...count).contains(scene.revealLevel) ? scene.revealLevel : count
    }

    /// Move the dial, clamped to its range. Writes the scene's synced level.
    func setLevel(_ level: Int) {
        guard count > 0 else { return }
        scene.revealLevel = min(max(level, 1), count)
    }

    /// The system scene's pages as this board shows them: at the dial, or at
    /// the core board's top when the dial is above it.
    var systemPages: [PageSpec] {
        chain?.pages(atLevel: level) ?? []
    }

    /// Words and folders a child at `level` can press: the scene's own, plus
    /// those on every core-board page the scene can reach.
    func visibleTileCount(atLevel level: Int) -> Int {
        let own = scene.visibleTileCount(atLevel: Self.clamp(level, to: scene.revealLevelCount))
        guard let chain else { return own }
        let pages = chain.pages(atLevel: level)
        // A page the scene has its own copy of is counted once, as its own.
        let reachable = Self.reachableSystemKeys(from: scene.pages, systemPages: pages,
                                                 homePageKey: chain.homePageKey,
                                                 inheritsRow: BoardChrome.inherits(scene),
                                                 rowKeys: BoardChrome.systemPageKeys(of: scene, inherited: chain.navBar))
            .subtracting(scene.shadowedSystemKeys)
        return own + pages.filter { reachable.contains($0.key) }
            .reduce(0) { $0 + $1.tiles.count { !$0.isEmptyCell } }
    }

    /// A board's level applied to one scene: capped at its top, nil when it
    /// has no levels (so stale placement levels stay ignored).
    static func clamp(_ level: Int?, to count: Int) -> Int? {
        guard count > 0, let level else { return nil }
        return min(level, count)
    }

    static func linksIntoSystem(_ pages: [PageSpec]) -> Bool {
        pages.contains { $0.tiles.contains { TileToken.systemPageKey($0.link) != nil } }
    }

    /// Keys of the system pages a scene's links reach, following the folders
    /// on those pages (the system home is Home, so it is not a way in).
    /// `inheritsRow`: the scene draws the system row, so its folders are ways
    /// in from every page.
    /// `rowKeys`: the system pages the row opens, when not the template's
    /// (a scene's own row, `BoardChrome.systemPageKeys`).
    static func reachableSystemKeys(from pages: [PageSpec], system: BlasterScene,
                                    inheritsRow: Bool = false, rowKeys: [String]? = nil) -> Set<String> {
        reachableSystemKeys(from: pages, systemPages: system.pages, homePageKey: system.homePageKey,
                            inheritsRow: inheritsRow, rowKeys: rowKeys)
    }

    /// The same, over the pages a template chain gives (`TemplateChain.pages`).
    static func reachableSystemKeys(from pages: [PageSpec], systemPages: [PageSpec], homePageKey: String?,
                                    inheritsRow: Bool = false, rowKeys: [String]? = nil) -> Set<String> {
        let byKey = Dictionary(systemPages.map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })
        var queue = pages.flatMap { $0.tiles.compactMap { TileToken.systemPageKey($0.link) } }
        if inheritsRow { queue += rowKeys ?? BoardChrome.pageKeys }
        var seen = Set<String>()
        while let key = queue.popLast() {
            guard key != homePageKey, !seen.contains(key),
                  let page = byKey[key] else { continue }
            seen.insert(key)
            // A BlasterAI 60 page's plain links are its own pages; a
            // template page's are whole (`TemplateChain.absolute`).
            queue += page.tiles.map(\.link).filter { !$0.isEmpty && $0 != TileToken.home
                && TileToken.scenePageKey($0) == nil }
                .map { TileToken.systemPageKey($0) ?? $0 }
        }
        return seen
    }
}
