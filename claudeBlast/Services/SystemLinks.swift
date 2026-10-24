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
