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
    ///
    /// Asked without decoding (`hasResolvedArt`): this runs from the scene
    /// editor's body on every render.
    @MainActor
    static func tilesNeedingArt(in scene: BlasterScene, tileLookup: [String: TileModel],
                                resolver: TileImageResolver) -> [TileModel] {
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                guard let tile = tileLookup[entry.key] else { continue }
                if !resolver.hasResolvedArt(for: tile.bundleImage) {
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
    /// Which sets this style still lacks art for. Existence only — `existingArt`
    /// above is for the generation path, which genuinely needs the pictures.
    static func missingVariants(of style: TileStyle, for tile: TileModel,
                                resolver: TileImageResolver) -> [ImageSetID] {
        style.setIDs.filter { !resolver.hasArt(for: tile.bundleImage, in: $0) }
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
                // Counts, not pictures. This runs from a computed property on
                // every render of the scene editor, so decoding each tile to ask
                // whether it exists cost gigabytes on a full board and got the
                // app killed. `hasArt` answers the same question off the file
                // system and a fetch count.
                let have = style.variants.count { resolver.hasArt(for: tile.bundleImage, in: $0.id) }
                if have > 0 && have < style.variants.count {
                    result.append(tile)
                }
            }
        }
        return result
    }

    // MARK: - Coverage across every style

    /// What one style still owes a scene.
    ///
    /// The two lists are separated because they are different jobs at different
    /// prices. `needsVariants` is a recolour of a picture that already exists, so
    /// the figure stays the same and one call produces one variant.
    /// `needsBase` has nothing to transform — the style must be *drawn* from
    /// scratch, which is a new picture that will not match the others tile for
    /// tile. Collapsing them into one number would let a caregiver ask for
    /// twenty fresh drawings believing they had asked for twenty recolours.
    struct StyleCoverage: Identifiable {
        let style: TileStyle
        /// Words with no art at all in this style.
        let needsBase: [TileModel]
        /// Words with art in some of its variants but not all.
        let needsVariants: [TileModel]

        var id: String { style.id }
        var isComplete: Bool { needsBase.isEmpty && needsVariants.isEmpty }
        /// Distinct words this style is missing something for.
        var wordCount: Int { needsBase.count + needsVariants.count }
    }

    /// Per-style coverage for every style a caregiver can generate into, active
    /// style first.
    ///
    /// ## Why this asks about styles the caregiver is not using
    ///
    /// The scene editor used to ask only about the active style, defended as "a
    /// style they don't use isn't a gap they can see". That is right about the
    /// common case and wrong about the one that bites: a word added on Classic
    /// gets Classic art, resolves, and vanishes from `tilesNeedingArt` — while
    /// Playful 3D and High Contrast, which are separate styles rather than
    /// variants of Classic, are never asked about by any scene-level surface. The
    /// word is then unfinishable in bulk forever, and the caregiver *can* see the
    /// gap: Tile Settings draws a dashed slot per missing style.
    ///
    /// So coverage is reported for every generatable style, and the surface that
    /// shows it stays put rather than disappearing when one style completes.
    @MainActor
    static func coverage(in scene: BlasterScene, tileLookup: [String: TileModel],
                         resolver: TileImageResolver) -> [StyleCoverage] {
        let tiles = distinctTiles(in: scene, tileLookup: tileLookup)
        guard !tiles.isEmpty else { return [] }
        return ImageSetCatalog.generationTargets(preferring: resolver.activeSet)
            .map { style in
                var needsBase: [TileModel] = []
                var needsVariants: [TileModel] = []
                for tile in tiles {
                    // Counts, not pictures — see the note on `tilesMissingVariants`:
                    // this runs from a computed property on every render, and
                    // decoding each image to ask whether it exists got the app
                    // killed on a full board.
                    let have = style.variants.count {
                        resolver.hasArt(for: tile.bundleImage, in: $0.id)
                    }
                    if have == 0 {
                        needsBase.append(tile)
                    } else if have < style.variants.count {
                        needsVariants.append(tile)
                    }
                }
                return StyleCoverage(style: style, needsBase: needsBase,
                                     needsVariants: needsVariants)
            }
    }

    /// Every distinct tile placed anywhere in the scene, in board order.
    @MainActor
    private static func distinctTiles(in scene: BlasterScene,
                                      tileLookup: [String: TileModel]) -> [TileModel] {
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                if let tile = tileLookup[entry.key] { result.append(tile) }
            }
        }
        return result
    }
}
