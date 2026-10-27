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
    static func row(for scene: BlasterScene, level: Int?) -> [TileEntry] {
        row(inSystemScene: scene.isDefault).map { entry in
            guard entry.isAboveLevel(level) else { return entry }
            var hidden = entry
            hidden.isConcealed = true
            return hidden
        }
    }

    /// The BlasterAI 60 pages the row opens.
    static var pageKeys: [String] { PageTemplate.scheme.systemRow.map(\.page) }

    /// The rail's Keyboard opens BlasterAI 60's keyboard page from every page.
    static let keyboardPage = "keyboard"

    /// The pages among `scene`'s own that every page opens: on BlasterAI 60,
    /// the row's folders and the rail's keyboard. Another scene's row opens
    /// BlasterAI 60's pages, not its own, so there are none. A folder above
    /// the board's level is an empty cell, not a way in.
    static func rowPages(of scene: BlasterScene) -> [String] {
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
