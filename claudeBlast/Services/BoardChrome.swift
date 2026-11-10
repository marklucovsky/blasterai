// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardChrome.swift
//  claudeBlast
//
//  Row 1: the system folders every page draws and no page stores.
//

import Foundation

/// The system row: People, Questions, Actions … Small words, on row 1 of every
/// page of a scene on a current grid.
///
/// Scenes inherit it rather than store it (Mark 2026-10-27: from this build
/// on, scenes "ALWAYS inherit system chrome from row 1"). One definition, in
/// `page_templates.json`, so changing the core board's folders changes every
/// board at once and no scene carries a stale copy. Home, Back and the
/// keyboard are not in it: they are on the control rail.
///
/// A scene inherits when it declares a grid this build knows (`designedFor`).
/// Anything else — a 12 × 5 scene from before, an undeclared flat pack — draws
/// its pages as they are, every cell content.
enum BoardChrome {
    /// Whether `scene`'s pages are drawn under the system row.
    static func inherits(_ scene: BlasterScene) -> Bool {
        inherits(designedFor: scene.designedFor)
    }

    static func inherits(designedFor: String) -> Bool {
        DesignedLayout(rawValue: designedFor) != nil
    }

    /// The row as tiles. On BlasterAI 60 itself a folder opens one of its own
    /// pages; anywhere else it opens the core board's page through a
    /// `<system>:` link, the way a scene's other links into it do.
    ///
    /// Each folder carries its BlasterAI 60 level, so a board at level 2 shows
    /// the row it showed when the folders were stored on its pages.
    static func row(inSystemScene: Bool) -> [TileEntry] {
        PageTemplate.scheme.systemRow.map { entry in
            TileEntry(key: entry.key,
                      link: inSystemScene ? entry.page : TileToken.systemLink(to: entry.page),
                      isAudible: false, linkColor: entry.linkColor, linkColorIsAuto: false,
                      revealLevel: entry.level ?? 0)
        }
    }

    /// The row for `scene` at `level`: folders above it draw as empty cells,
    /// like any other word above the board's level.
    ///
    /// `underMountedPage`: the page showing is a mounted scene's (the Me page,
    /// a topic). The row is still the board's, but a plain link there names a
    /// page of the *mounted* scene (`SystemLinks.destination`), so Actions
    /// opened `<scene:me-…>:actions`, which does not exist, and the child was
    /// sent Home. Under a mounted page the links keep the system prefix;
    /// `destination` makes them plain again when BlasterAI 60 is the board.
    ///
    /// A scene with its own row (`BlasterScene.ownRow`) draws that instead.
    static func row(for scene: BlasterScene, level: Int?,
                    underMountedPage: Bool = false) -> [TileEntry] {
        let entries = ownRow(of: scene).map {
            padded($0.tiles, to: scene.designedLayout?.grid.cols ?? PageTemplate.cols)
        } ?? row(inSystemScene: scene.isDefault && !underMountedPage)
        return entries.map { entry in
            guard entry.isAboveLevel(level) else { return entry }
            var hidden = entry
            hidden.isConcealed = true
            return hidden
        }
    }

    /// The BlasterAI 60 pages the row opens.
    static var pageKeys: [String] { PageTemplate.scheme.systemRow.map(\.page) }

    /// A bar shorter than the grid, filled out with gaps. A bar is stored
    /// only as far as its last word, but it takes the grid's whole width:
    /// anything laying the bar and a page out as one run of cells would
    /// otherwise start the page in the bar's empty cells. The gaps' keys are
    /// fixed, so the same bar is the same views from one render to the next.
    static func padded(_ entries: [TileEntry], to cols: Int) -> [TileEntry] {
        guard entries.count < cols else { return entries }
        return entries + (entries.count..<cols).map {
            TileEntry(key: TileToken.spacerPrefix + "bar\($0)", link: "", isAudible: false)
        }
    }

    /// The scene's own row, when it has one and draws a row at all.
    /// BlasterAI 60's row is the template's, never stored.
    static func ownRow(of scene: BlasterScene) -> PageSpec? {
        guard !scene.isDefault, inherits(scene) else { return nil }
        return scene.ownRow
    }

    /// The BlasterAI 60 pages `scene`'s row opens: its own row's links into
    /// the core board, else the template's.
    static func systemPageKeys(of scene: BlasterScene) -> [String] {
        guard let own = ownRow(of: scene) else { return pageKeys }
        return own.tiles.compactMap { TileToken.systemPageKey($0.link) }
    }

    /// Row 1 as a scene starts its own: BlasterAI 60's, its folders opening
    /// the core board's pages. Copy-on-write, like a page — the scene's row
    /// follows BlasterAI 60's until a caregiver makes it theirs.
    static func ownRowStart() -> PageSpec {
        PageSpec(key: BlasterScene.rowPageKey, displayName: "Navigation Bar", tiles: row(inSystemScene: false))
    }

    /// The rail's Keyboard opens BlasterAI 60's keyboard page from every page.
    static let keyboardPage = "keyboard"

    /// The pages among `scene`'s own that every page opens: on BlasterAI 60,
    /// the row's folders and the rail's keyboard. Another scene's row opens
    /// BlasterAI 60's pages, not its own, so there are none. A folder above
    /// the board's level is an empty cell, not a way in.
    static func rowPages(of scene: BlasterScene) -> [String] {
        if let own = ownRow(of: scene) {
            // Its own row may open the scene's pages: those are ways in from
            // every page, as BlasterAI 60's folders are on BlasterAI 60.
            let level = scene.effectiveRevealLevel
            return own.tiles.filter { !$0.isAboveLevel(level) }.map(\.link)
                .filter { !$0.isEmpty && $0 != TileToken.home
                    && TileToken.systemPageKey($0) == nil && TileToken.scenePageKey($0) == nil }
        }
        guard scene.isDefault, inherits(scene) else { return [] }
        let level = scene.effectiveRevealLevel
        return PageTemplate.scheme.systemRow
            .filter { entry in
                guard let level, let first = entry.level, first > 0 else { return true }
                return first <= level
            }
            .map(\.page) + [keyboardPage]
    }
}
