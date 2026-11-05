// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageCover.swift
//  claudeBlast
//
//  The picture that stands for a page wherever a folder opens it — the page's
//  twin of `SceneCover` (Mark, 2026-11-04).
//

import Foundation
import SwiftData

/// A folder and the page it opens are one thing, so the folder's picture is
/// the page's: `PageSpec.cover`, the key of the tile whose art it shows.
///
/// ## What a cover can be
///
/// - **Any word of the vocabulary**, by key: the cover borrows its art, as a
///   scene cover does. BlasterAI 60's pages use their curated folders
///   (`folder_family` for Family).
/// - **The page's own picture**: a photo or AI art, held on a `page_link` tile
///   scoped to the scene and page (`pagecover_<scene>_<page>`). A copied scene
///   shares its source's cover until it picks its own, and then gets its own
///   key, so a change never reaches another scene.
///
/// ## Folders follow it
///
/// A silent folder whose picture is its page's cover is the default; one
/// showing anything else is an override (`[word] > page` in a cell). Choosing
/// a new cover (`setCover`) moves every default folder with it.
///
/// ## The default
///
/// A page with no cover chosen takes the folder that already opens it — on
/// one of the scene's pages, or on the inherited system row — then a spoken
/// word that opens it, and failing those its `page_<key>` tile. No page is without one, and a page that was
/// working before covers existed looks exactly as it did.
enum PageCover {
    static let prefix = "pagecover_"

    /// The cover in force for `page`: chosen, else the default.
    static func key(of page: PageSpec, in pages: [PageSpec], isSystemScene: Bool = false,
                    systemRow: [(key: String, page: String)] = BoardCell.systemRowFolders) -> String {
        if !page.cover.isEmpty { return page.cover }
        return defaultKey(of: page.key, in: pages, isSystemScene: isSystemScene, systemRow: systemRow)
    }

    /// The cover of the page `pageKey` of `scene`, chosen or default.
    static func key(ofPage pageKey: String, in scene: BlasterScene) -> String {
        guard let page = scene.page(withKey: pageKey) else {
            return defaultKey(of: pageKey, in: scene.pages, isSystemScene: scene.isDefault)
        }
        return key(of: page, in: scene.pages, isSystemScene: scene.isDefault)
    }

    /// A folder already opening the page, else the system row's (on BlasterAI
    /// 60, whose row folders are never stored on a page), else `page_<key>`.
    static func defaultKey(of pageKey: String, in pages: [PageSpec], isSystemScene: Bool,
                           systemRow: [(key: String, page: String)] = BoardCell.systemRowFolders) -> String {
        for page in pages {
            if let entry = page.tiles.first(where: { isFolder($0) && $0.link == pageKey }) {
                return entry.key
            }
        }
        if isSystemScene, let folder = systemRow.first(where: { $0.page == pageKey }) {
            return folder.key
        }
        // A page only a spoken word opens (Food by *eat*) borrows that word.
        for page in pages {
            if let entry = page.tiles.first(where: { $0.link == pageKey && !$0.isEmptyCell }) {
                return entry.key
            }
        }
        return PageLink.key(forPage: pageKey)
    }

    /// `pages` with every unchosen cover written down as its default — run on
    /// BlasterAI 60 as it is built, so its covers are data, not inference.
    static func assigningDefaults(_ pages: [PageSpec], isSystemScene: Bool,
                                  systemRow: [(key: String, page: String)] = BoardCell.systemRowFolders) -> [PageSpec] {
        pages.map { page in
            guard page.cover.isEmpty else { return page }
            var page = page
            page.cover = defaultKey(of: page.key, in: pages, isSystemScene: isSystemScene, systemRow: systemRow)
            return page
        }
    }

    /// A silent tile that opens a page: a folder.
    static func isFolder(_ entry: TileEntry) -> Bool {
        !entry.isAudible && !entry.link.isEmpty && !entry.isSpacer && entry.link != TileToken.home
    }

    /// `pages` with `page`'s cover set to `newKey`, and every folder in them
    /// that showed the old cover showing the new one.
    static func setting(_ newKey: String, forPage pageKey: String, in pages: [PageSpec],
                        isSystemScene: Bool = false) -> [PageSpec] {
        guard let index = pages.firstIndex(where: { $0.key == pageKey }) else { return pages }
        let old = key(of: pages[index], in: pages, isSystemScene: isSystemScene)
        var result = pages
        result[index].cover = newKey
        for p in result.indices {
            for t in result[p].tiles.indices {
                let entry = result[p].tiles[t]
                if isFolder(entry), entry.link == pageKey, entry.key == old {
                    result[p].tiles[t].key = newKey
                }
            }
        }
        return result
    }

    /// Sets `page`'s cover in `scene`.
    @MainActor
    static func setCover(_ newKey: String, forPage pageKey: String, in scene: BlasterScene) {
        scene.pages = setting(newKey, forPage: pageKey, in: scene.pages, isSystemScene: scene.isDefault)
    }

    // MARK: - The page's own picture

    /// The key of the tile holding `page`'s own photo or art in `scene`.
    static func ownKey(forPage pageKey: String, in scene: BlasterScene) -> String {
        let sceneID = scene.sceneID.isEmpty ? scene.id : scene.sceneID
        let folded = sceneID.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return prefix + folded + "_" + pageKey
    }

    /// The page's own cover tile, minted if need be and made the cover. Its
    /// picture starts as the current cover's, so choosing to add a photo or
    /// generate art changes nothing until the photo or art arrives.
    @MainActor
    @discardableResult
    static func ensureOwn(forPage pageKey: String, in scene: BlasterScene,
                          context: ModelContext) -> TileModel {
        let key = ownKey(forPage: pageKey, in: scene)
        let current = Self.key(ofPage: pageKey, in: scene)
        let title = scene.page(withKey: pageKey)?.title ?? PageNaming.displayName(pageKey)
        let fetch = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == key })
        let tile: TileModel
        if let found = (try? context.fetch(fetch))?.first {
            tile = found
        } else {
            tile = TileModel(key: key, value: title, wordClass: PageLink.wordClass)
            tile.isSystem = false
            let currentFetch = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == current })
            if let source = (try? context.fetch(currentFetch))?.first, source.key != key {
                tile.bundleImage = source.bundleImage
                if source.hasUserImage { tile.userImageData = source.userImageData }
            }
            context.insert(tile)
        }
        if current != key { setCover(key, forPage: pageKey, in: scene) }
        return tile
    }

    /// Keeps the page's own cover tile named after the page.
    @MainActor
    static func renamed(page pageKey: String, in scene: BlasterScene, to title: String,
                        lookup: [String: TileModel]) {
        lookup[ownKey(forPage: pageKey, in: scene)]?.displayName = title
    }
}
