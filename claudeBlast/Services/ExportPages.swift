// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ExportPages.swift
//  claudeBlast
//
//  A scene's pages made whole, for a file that leaves the app.
//

import Foundation

/// A scene's pages with the BlasterAI 60 pages it reaches written in, for a
/// format read outside Blaster (Open Board, print).
///
/// Inside the app a scene links into the core board rather than copying it
/// (`TileToken.systemPrefix`), and a copy of BlasterAI 60 holds only the
/// pages a caregiver edited (copy-on-write, `PageSpec.shadows`). A Blaster
/// scene file can stay that sparse, because every device has BlasterAI 60.
/// An .obz cannot: its reader has no core board, and every `<system>:` link
/// was a gap. Here each reachable core-board page comes along, under its own
/// key (or `blasterai_<key>` when the scene has a page of that name), and
/// every link names the page it now opens: the scene's own copy where it has
/// one, the page written in otherwise, Home for the core board's home.
struct ExportPages {
    /// The scene's pages, then the core-board pages they reach.
    let pages: [PageSpec]
    /// Export key for each core-board page written in, by system key.
    private let keyForSystem: [String: String]
    private let shadowKeyForSystem: [String: String]

    /// - Parameters:
    ///   - scenePages: the scene's pages, as they are to be exported.
    ///   - systemPages: BlasterAI 60's pages; empty when exporting BlasterAI 60
    ///     itself, whose links are already its own.
    ///   - rowKeys: core-board pages the system row opens from every page.
    init(scenePages: [PageSpec], systemPages: [PageSpec], systemHomePageKey: String?,
         rowKeys: [String] = []) {
        var shadows: [String: String] = [:]
        for page in scenePages where page.isShadow { shadows[page.shadows] = page.key }
        shadowKeyForSystem = shadows

        // The core-board pages reachable from the scene, following the links
        // on each page brought in. A page the scene has its own copy of is
        // reached through the copy, whose links are already the scene's.
        let byKey = Dictionary(systemPages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var queue = scenePages.flatMap { $0.tiles.compactMap { TileToken.systemPageKey($0.link) } }
            + rowKeys
        queue.reverse()
        var included: [PageSpec] = []
        var seen = Set<String>()
        while let key = queue.popLast() {
            guard key != systemHomePageKey, shadows[key] == nil,
                  seen.insert(key).inserted, let page = byKey[key] else { continue }
            included.append(page)
            let next = page.tiles.map(\.link).filter {
                !$0.isEmpty && $0 != TileToken.home && TileToken.scenePageKey($0) == nil
            }.map { TileToken.systemPageKey($0) ?? $0 }
            queue.append(contentsOf: next.reversed())
        }

        let taken = Set(scenePages.map(\.key))
        var keys: [String: String] = [:]
        var used = taken
        for page in included where !TileToken.isTemplateKey(page.key) {
            let key = taken.contains(page.key) ? "blasterai_" + page.key : page.key
            keys[page.key] = key
            used.insert(key)
        }
        // A template's page goes by its name (`template:random` → `random`),
        // or `template_random` beside a page of that name.
        for page in included where TileToken.isTemplateKey(page.key) {
            let base = TileToken.bareKey(page.key)
            var key = used.contains(base) ? "template_" + base : base
            var n = 2
            while used.contains(key) { key = "template_\(base)_\(n)"; n += 1 }
            keys[page.key] = key
            used.insert(key)
        }
        keyForSystem = keys

        let scene = scenePages.map { page in
            var page = page
            page.tiles = page.tiles.map { Self.relinked($0, to: Self.link(for: $0.link, shadows: shadows, keys: keys)) }
            return page
        }
        let brought = included.map { page in
            var page = page
            page.key = keys[page.key] ?? page.key
            page.shadows = ""
            page.tiles = page.tiles.map { entry in
                guard !entry.link.isEmpty, entry.link != TileToken.home,
                      TileToken.scenePageKey(entry.link) == nil else { return entry }
                let systemKey = TileToken.systemPageKey(entry.link) ?? entry.link
                if systemKey == systemHomePageKey { return Self.relinked(entry, to: TileToken.home) }
                return Self.relinked(entry, to: Self.link(for: TileToken.systemLink(to: systemKey),
                                                          shadows: shadows, keys: keys))
            }
            return page
        }
        pages = scene + brought
    }

    /// The page `key` and every page reachable from it, in the order they are
    /// first reached: a page shared on its own prints with what it opens.
    /// Home is the end of a path, not a way into the rest of the board.
    func reachable(from key: String) -> [PageSpec] {
        let byKey = Dictionary(pages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [PageSpec] = []
        var seen = Set<String>()
        var stack = [key]
        while let next = stack.popLast() {
            guard seen.insert(next).inserted, let page = byKey[next] else { continue }
            out.append(page)
            let links = page.tiles.map(\.link).filter { !$0.isEmpty && $0 != TileToken.home }
            stack.append(contentsOf: links.reversed())
        }
        return out
    }

    /// Where `link` leads in the exported pages; a `<system>:` link to a page
    /// that did not come along is left as it was.
    func link(_ link: String) -> String {
        Self.link(for: link, shadows: shadowKeyForSystem, keys: keyForSystem)
    }

    private static func link(for link: String, shadows: [String: String], keys: [String: String]) -> String {
        guard let systemKey = TileToken.systemPageKey(link) else { return link }
        return shadows[systemKey] ?? keys[systemKey] ?? link
    }

    private static func relinked(_ entry: TileEntry, to link: String) -> TileEntry {
        guard link != entry.link else { return entry }
        var out = entry
        out.link = link
        return out
    }
}
