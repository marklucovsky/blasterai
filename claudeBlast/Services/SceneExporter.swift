// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExporter.swift
//  claudeBlast
//
//  Exports a BlasterScene to the portable JSON exchange format.
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum SceneExporter {

    /// Convert a BlasterScene into an ExportableScene struct.
    ///
    /// - Parameters:
    ///   - scene: the scene to export.
    ///   - defaultTileKeys: keys considered part of the bundled vocabulary
    ///     (any key NOT in this set is treated as a custom vocab entry and
    ///     included in `tiles` on the exportable).
    ///   - tileLookup: maps vocabulary key → TileModel. Needed because the
    ///     scene's pages now store keys only; tile metadata (wordClass,
    ///     displayName, userImageData) lives on the TileModel entities.
    ///   - context: used to collect each custom word's `TileArtVariant` rows. Nil
    ///     exports word identity with no set art — the pre-4A′ behaviour, kept
    ///     for callers that only need the page structure.
    static func export(_ scene: BlasterScene,
                       defaultTileKeys: Set<String> = [],
                       tileLookup: [String: TileModel],
                       context: ModelContext? = nil) -> ExportableScene {
        var exportTiles: [ExportableTile] = []
        var seenTileKeys = Set<String>()

        // Every key the scene references, so art is collected in one pass rather
        // than one fetch per tile.
        // Spacers name no word, so they have no art to collect.
        let allKeys = scene.pages.flatMap { page in
            page.tiles.filter { !$0.isSpacer }.map(\.key)
        }
        let storedArt = context.map {
            ExportArtResolver.storedArt(for: allKeys, tileLookup: tileLookup, context: $0)
        } ?? [:]

        let exportPages: [ExportablePage] = scene.pages.map { page in
            let pageTiles: [ExportablePageTile] = page.tiles.compactMap { entry in
                // A gap travels as itself. It resolves to no TileModel, so the
                // lookup guard below would drop it — and dropping it closes the
                // hole and shifts every tile after it, so the board the
                // recipient opens is not the board that was shared.
                if entry.isSpacer {
                    return ExportablePageTile(key: entry.key, isAudible: false, link: "")
                }
                guard let tile = tileLookup[entry.key] else { return nil }

                // Collect tiles that are not in the default vocabulary or have custom images
                if seenTileKeys.insert(tile.key).inserted {
                    let isCustom = !defaultTileKeys.contains(tile.key)
                    let hasCustomImage = tile.hasUserImage

                    if isCustom || hasCustomImage {
                        exportTiles.append(exportableTile(for: tile, art: storedArt[tile.key]))
                    }
                }

                return ExportablePageTile(
                    key: tile.key,
                    isAudible: entry.isAudible,
                    link: entry.link,
                    // Only when set, so the common case adds nothing to the file.
                    isConcealed: entry.isConcealed ? true : nil
                )
            }
            return ExportablePage(key: page.key, tiles: pageTiles)
        }

        return ExportableScene(
            type: BlasterSceneFormat.mediaType,
            version: BlasterSceneFormat.currentVersion,
            name: scene.name,
            description: scene.descriptionText,
            homePageKey: scene.homePageKey,
            // Decentralized identity rides inside the file. Empty strings become
            // nil so a legacy/unstamped scene exports cleanly (import falls back
            // to name). `receivedLabel` is local-only and deliberately not sent.
            id: scene.sceneID.isEmpty ? nil : scene.sceneID,
            slug: scene.slug.isEmpty ? nil : scene.slug,
            sceneVersion: scene.sceneVersion.isEmpty ? nil : scene.sceneVersion,
            authorName: scene.authorName.isEmpty ? nil : scene.authorName,
            tiles: exportTiles.isEmpty ? nil : exportTiles,
            pages: exportPages
        )
    }

    /// Export a BlasterScene to pretty-printed JSON Data.
    static func exportJSON(_ scene: BlasterScene,
                           defaultTileKeys: Set<String> = [],
                           tileLookup: [String: TileModel],
                           context: ModelContext? = nil) throws -> Data {
        let exportable = export(scene, defaultTileKeys: defaultTileKeys,
                                tileLookup: tileLookup, context: context)
        return try encode(exportable)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    // MARK: - Tile payload

    /// Build one tile's export entry: identity, its per-set art, and any photo
    /// override.
    static func exportableTile(for tile: TileModel, art: StoredTileArt?) -> ExportableTile {
        let variants = (art?.variants ?? []).compactMap { entry -> ExportableTileArt? in
            guard let encoded = encodeArt(entry.data) else { return nil }
            return ExportableTileArt(imageSet: entry.set.rawValue, imageData: encoded)
        }
        return ExportableTile(
            key: tile.key,
            wordClass: tile.wordClass,
            displayName: tile.displayName,
            imageData: encodeArt(art?.photo),
            art: variants.isEmpty ? nil : variants,
            // Only when it points somewhere else. An alias equal to the key is
            // the default and carrying it would be noise in every file.
            bundleImage: tile.bundleImage == tile.key ? nil : tile.bundleImage
        )
    }

    // MARK: - Image encoding

    /// Base64 the stored bytes **verbatim**.
    ///
    /// This used to decode the image, resize it to 512 px, and re-encode as PNG
    /// (falling back to JPEG). Every step of that was cost without benefit: the
    /// art is already 512 px, and PNG-from-HEIC inflates a ~14 KB tile to a few
    /// hundred KB — the difference between a shareable page and one iMessage
    /// refuses. Both ends of a `.blasterscene` are Blaster and read what we
    /// wrote, so the bytes travel as they are.
    ///
    /// Oversized art is dropped rather than recompressed. It can only come from a
    /// caregiver photo (generated art is bounded at authoring time), the importer
    /// already reports dropped images per key, and silently degrading someone's
    /// photograph is worse than telling them it didn't fit.
    private static func encodeArt(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        guard data.count <= BlasterSceneFormat.maxImageDataSize else { return nil }
        return data.base64EncodedString()
    }
}
