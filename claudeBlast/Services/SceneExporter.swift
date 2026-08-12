// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExporter.swift
//  claudeBlast
//
//  Exports a BlasterScene to the portable JSON exchange format.
//

import Foundation
import UIKit

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
    static func export(_ scene: BlasterScene,
                       defaultTileKeys: Set<String> = [],
                       tileLookup: [String: TileModel]) -> ExportableScene {
        var exportTiles: [ExportableTile] = []
        var seenTileKeys = Set<String>()

        let exportPages: [ExportablePage] = scene.pages.map { page in
            let pageTiles: [ExportablePageTile] = page.tiles.compactMap { entry in
                guard let tile = tileLookup[entry.key] else { return nil }

                // Collect tiles that are not in the default vocabulary or have custom images
                if seenTileKeys.insert(tile.key).inserted {
                    let isCustom = !defaultTileKeys.contains(tile.key)
                    let hasCustomImage = tile.hasUserImage

                    if isCustom || hasCustomImage {
                        let imageBase64 = encodeImage(tile.userImageData)
                        exportTiles.append(ExportableTile(
                            key: tile.key,
                            wordClass: tile.wordClass,
                            displayName: tile.displayName,
                            imageData: imageBase64
                        ))
                    }
                }

                return ExportablePageTile(
                    key: tile.key,
                    isAudible: entry.isAudible,
                    link: entry.link
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
                           tileLookup: [String: TileModel]) throws -> Data {
        let exportable = export(scene, defaultTileKeys: defaultTileKeys, tileLookup: tileLookup)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(exportable)
    }

    // MARK: - Image encoding

    /// Resize and base64-encode image data. Returns nil if no data or encoding fails.
    private static func encodeImage(_ imageData: Data?) -> String? {
        guard let imageData, let image = UIImage(data: imageData) else { return nil }

        let maxDim = BlasterSceneFormat.maxImageDimension
        let resized: UIImage
        if image.size.width > maxDim || image.size.height > maxDim {
            let scale = min(maxDim / image.size.width, maxDim / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            resized = image
        }

        guard let pngData = resized.pngData(),
              pngData.count <= BlasterSceneFormat.maxImageDataSize else {
            // Fall back to JPEG if PNG is too large
            guard let jpegData = resized.jpegData(compressionQuality: 0.8),
                  jpegData.count <= BlasterSceneFormat.maxImageDataSize else {
                return nil
            }
            return jpegData.base64EncodedString()
        }
        return pngData.base64EncodedString()
    }
}
