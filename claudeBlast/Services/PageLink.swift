// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftData
import Foundation

/// A `page_link` tile is a silent navigation tile that points to a named page
/// collection. Its key encodes the target page, so the tile can be dropped on
/// any board and resolve to a link. Every page mints one when it's created,
/// encouraging reuse of named tile collections (pages).
///
/// `page_link` vs the `navigation` wordClass — both are non-words and are
/// filtered from the AI vocabulary, but they differ in intent:
/// - `navigation` is generic structural *chrome* (home / next_page /
///   previous_page) — movement with no specific destination.
/// - `page_link` jumps to a specific *named* collection, with the target
///   encoded in the key.
/// Navigation itself is a scene/placement concept: a tile navigates iff its
/// `TileEntry.link` is non-empty — never a property of the TileModel/`type`.
enum PageLink {
    static let wordClass = "page_link"
    private static let prefix = "page_"

    /// Stable tile key for the page-link tile of `pageKey` ("space" → "page_space").
    static func key(forPage pageKey: String) -> String { prefix + pageKey }

    /// The page a page-link tile navigates to (inverse of `key(forPage:)`), or nil
    /// if `key` isn't a page-link key.
    static func targetPage(forKey key: String) -> String? {
        key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
    }

    /// Find or mint the page-link tile for `pageKey`. Idempotent: returns the
    /// existing tile if present (filling in art if it had none). `image`, when
    /// given, becomes the icon; otherwise the tile renders the placeholder until
    /// art is generated.
    @discardableResult
    static func mint(pageKey: String,
                     displayName: String,
                     image: Data? = nil,
                     imageKey: String? = nil,
                     context: ModelContext,
                     existing: [String: TileModel]) -> TileModel {
        let k = key(forPage: pageKey)
        if let tile = existing[k] {
            if let image, !tile.hasUserImage { tile.userImageData = image }
            return tile
        }
        let tile = TileModel(key: k, value: displayName, wordClass: wordClass)
        tile.isSystem = false
        if let image {
            tile.userImageData = image                 // explicit cover (e.g. a pack icon)
        } else if let imageKey {
            tile.bundleImage = imageKey                // alias an existing tile's set art
        }
        context.insert(tile)
        return tile
    }

    /// Ensure every page in `scene` has a page-link tile (its image + silent link).
    /// Reuses the image already used by an existing tile that links to the page
    /// (e.g. the core scene's category links) so no new art is generated; falls
    /// back to a representative member tile. Idempotent — safe to re-run.
    static func ensurePageImages(in scene: BlasterScene, context: ModelContext,
                                 existing: [String: TileModel]) {
        let pages = scene.pages
        // page key -> image key, taken from any tile that already links to it.
        var inboundImage: [String: String] = [:]
        for page in pages {
            for tile in page.tiles where !tile.link.isEmpty {
                let dest = tile.link == "<home>" ? scene.homePageKey : tile.link
                if inboundImage[dest] == nil, existing[tile.key] != nil {
                    inboundImage[dest] = tile.key
                }
            }
        }
        for page in pages where existing[key(forPage: page.key)] == nil {
            let imageKey = inboundImage[page.key]
                ?? page.tiles.first(where: { existing[$0.key] != nil })?.key
            mint(pageKey: page.key,
                 displayName: page.key.replacingOccurrences(of: "_", with: " ").capitalized,
                 imageKey: imageKey,
                 context: context, existing: existing)
        }
    }
}
