// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImageBatch.swift
//  claudeBlast
//
//  Helpers for batch-generating tile art for the caregiver-created words a
//  scene introduces. AI scene generation/refinement proposes new words that
//  start with no image (a letter-on-color placeholder); this finds those words
//  so the editor can offer to illustrate them in one pass. The generation loop
//  itself lives in SceneImageBatchSheet (it owns the progress + cancel state).
//

import Foundation
import UIKit

enum SceneImageBatch {
    /// Distinct tiles referenced by `scene` that have NO real art — nothing
    /// resolves for them (no user photo, no set art, no master-set backfill), so
    /// they'd render the letter placeholder. These are the words to illustrate.
    ///
    /// Asking the resolver (not just `userImageData == nil`) is what makes the
    /// count correct for pack words: a pack word carries no userImageData but has
    /// bundled p3d_/cls_ art, so it resolves and is correctly excluded.
    @MainActor
    static func tilesNeedingArt(in scene: BlasterScene, tileLookup: [String: TileModel],
                                resolver: TileImageResolver) -> [TileModel] {
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                guard let tile = tileLookup[entry.key] else { continue }
                if resolver.image(for: tile.bundleImage) == nil {
                    result.append(tile)
                }
            }
        }
        return result
    }

    // MARK: - Words a style could complete

    // These use `image(for:in:)`, the raw lookup — bundled art or a stored
    // variant, with no backfill. That distinction is the whole point: on a Dark
    // board a word with only Classic art *renders* via the backfill, so going
    // through `image(for:)` would report the style complete when the Dark art
    // does not exist. The bundled vocabulary has real art in all three Classic
    // sets and is correctly seen as complete.

    /// Art `tile` already has in each of the style's variants.
    @MainActor
    static func existingArt(of style: TileStyle, for tile: TileModel,
                            resolver: TileImageResolver) -> [ImageSetID: UIImage] {
        var out: [ImageSetID: UIImage] = [:]
        for variant in style.variants {
            if let img = resolver.image(for: tile.bundleImage, in: variant.id) {
                out[variant.id] = img
            }
        }
        return out
    }

    @MainActor
    static func missingVariants(of style: TileStyle, for tile: TileModel,
                                resolver: TileImageResolver) -> [ImageSetID] {
        let have = existingArt(of: style, for: tile, resolver: resolver)
        return style.setIDs.filter { have[$0] == nil }
    }

    /// Distinct tiles in `scene` that this style could complete: they have art
    /// somewhere in the style but not in every variant.
    ///
    /// This is the catch-up case. A caregiver on Medium adds twenty-five words
    /// and each gets Light and Medium art, because generation stops at the
    /// variant she actually uses. If she later wants the whole style, this is the
    /// list, and each word needs only the variants below the ones it has.
    ///
    /// A word with no art at all in the style is deliberately excluded — there is
    /// nothing to transform, and drawing a fresh base would produce a different
    /// picture from the rest of its style. Those belong to `tilesNeedingArt`.
    @MainActor
    static func tilesMissingVariants(in scene: BlasterScene, tileLookup: [String: TileModel],
                                     style: TileStyle,
                                     resolver: TileImageResolver) -> [TileModel] {
        guard style.variants.count > 1 else { return [] }
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                guard let tile = tileLookup[entry.key] else { continue }
                let have = existingArt(of: style, for: tile, resolver: resolver)
                if !have.isEmpty && have.count < style.variants.count {
                    result.append(tile)
                }
            }
        }
        return result
    }
}
