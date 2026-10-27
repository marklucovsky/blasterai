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
    /// - Anywhere else a plain link is a page of the active scene.
    static func destination(of link: String, fromPage: String,
                            homePageKey: String, systemHomePageKey: String?) -> String {
        if link == TileToken.home { return homePageKey }
        if TileToken.systemPageKey(link) != nil { return link }
        if TileToken.systemPageKey(fromPage) != nil {
            return link == systemHomePageKey ? homePageKey : TileToken.systemLink(to: link)
        }
        return link
    }

    /// The page a navigation key shows: the active scene's page, or for a
    /// `<system>:` key, the system scene's.
    ///
    /// A system page shows all its words. Graded reveal is set per scene, and
    /// the level a caregiver chose for BlasterAI 60 says nothing about a child
    /// who is using another board.
    static func page(forKey key: String, scenePages: [PageSpec],
                     systemPages: [PageSpec]) -> PageSpec? {
        if let systemKey = TileToken.systemPageKey(key) {
            return systemPages.first { $0.key == systemKey }
        }
        return scenePages.first { $0.key == key }
    }

    /// A short, readable name for where a link goes — "BlasterAI › Actions"
    /// for a system page — for the editor and for print.
    static func displayName(of link: String) -> String {
        if let systemKey = TileToken.systemPageKey(link) {
            return "BlasterAI › " + PageNaming.displayName(systemKey)
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

    init(scene: BlasterScene, system: BlasterScene?) {
        self.scene = scene
        // A scene under the system row reaches BlasterAI 60 from every page,
        // whether or not any page stores a link into it.
        if let system, system.persistentModelID != scene.persistentModelID,
           BoardChrome.inherits(scene) || Self.linksIntoSystem(scene.pages) {
            self.system = system
        } else {
            self.system = nil
        }
    }

    /// Steps on the dial; 0 when neither board has levels.
    var count: Int { max(scene.revealLevelCount, system?.revealLevelCount ?? 0) }

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
        guard let system else { return [] }
        return system.pages(atLevel: Self.clamp(level, to: system.revealLevelCount))
    }

    /// Words and folders a child at `level` can press: the scene's own, plus
    /// those on every core-board page the scene can reach.
    func visibleTileCount(atLevel level: Int) -> Int {
        let own = scene.visibleTileCount(atLevel: Self.clamp(level, to: scene.revealLevelCount))
        guard let system else { return own }
        let reachable = Self.reachableSystemKeys(from: scene.pages, system: system,
                                                 inheritsRow: BoardChrome.inherits(scene))
        let pages = system.pages(atLevel: Self.clamp(level, to: system.revealLevelCount))
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
    static func reachableSystemKeys(from pages: [PageSpec], system: BlasterScene,
                                    inheritsRow: Bool = false) -> Set<String> {
        let byKey = Dictionary(system.pages.map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })
        var queue = pages.flatMap { $0.tiles.compactMap { TileToken.systemPageKey($0.link) } }
        if inheritsRow { queue += BoardChrome.pageKeys }
        var seen = Set<String>()
        while let key = queue.popLast() {
            guard key != system.homePageKey, !seen.contains(key),
                  let page = byKey[key] else { continue }
            seen.insert(key)
            queue += page.tiles.map(\.link).filter { !$0.isEmpty && $0 != TileToken.home }
        }
        return seen
    }
}
