// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImporter.swift
//  claudeBlast
//
//  Imports a scene from the portable JSON exchange format into SwiftData.
//

import SwiftData
import Foundation

enum SceneImportError: LocalizedError {
    case invalidType(String)
    case unsupportedVersion(String)
    case decodingFailed(String)
    case noPages

    var errorDescription: String? {
        switch self {
        case .invalidType(let type):
            return "Not a Blaster scene file (type: \(type))"
        case .unsupportedVersion(let version):
            return "Unsupported scene format version: \(version)"
        case .decodingFailed(let detail):
            return "Could not read scene file: \(detail)"
        case .noPages:
            return "Scene has no pages"
        }
    }
}

@MainActor
enum SceneImporter {

    struct ImportResult {
        let scene: BlasterScene
        let skippedKeys: [String]
        let newTileCount: Int
        let oversizedImages: [String]  // tile keys where imageData exceeded cap
        /// Existing tiles whose image was filled or replaced — the caller should
        /// invalidate the image resolver's cache for these so they re-render.
        let imageUpdatedKeys: [String]
        /// True when the import matched an existing scene by `sceneID` and
        /// updated it in place (rather than inserting a new scene).
        var wasUpdate: Bool = false
        /// True when the imported scene carries no author name — the caller may
        /// offer the receiver a local "from …" tag (`scene.receivedLabel`).
        var needsReceiverLabel: Bool = false
        /// Non-`.none` only from a conflict-detection call (`resolution == nil`
        /// while the local copy is edited): nothing was written, the caller must
        /// prompt and re-call with a resolution.
        var conflict: SceneImportConflict = .none
    }

    /// An incoming update matches a scene the receiver has locally edited.
    enum SceneImportConflict: Equatable {
        case none
        case modifiedExisting(name: String)
    }

    /// How to resolve a `.modifiedExisting` conflict.
    enum SceneImportResolution {
        case keepMine     // discard the incoming update; leave the local copy
        case takeUpdate   // overwrite the local copy in place (edits lost)
        case keepBoth     // import the update as a separate, locally-owned copy
    }

    /// Side-effect-free check: does importing `data` collide with a locally
    /// edited copy of the same scene? Lets the import sheet prompt before it
    /// writes anything.
    static func conflict(for data: Data, context: ModelContext) -> SceneImportConflict {
        guard let exportable = try? JSONDecoder().decode(ExportableScene.self, from: data),
              let incomingID = exportable.id, !incomingID.isEmpty,
              let existing = try? context.fetch(
                FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.sceneID == incomingID })
              ).first
        else { return .none }
        // Empty baseline (legacy import) → can't prove it's unmodified → be safe.
        let modified = existing.importedContentHash.isEmpty
            || existing.contentHash != existing.importedContentHash
        return modified ? .modifiedExisting(name: existing.name) : .none
    }

    /// How the file's custom tiles relate to THIS device's vocabulary — used to
    /// preview the import and to drive per-word image-collision consent.
    struct ImportAnalysis {
        /// Keys not on the device — will be created.
        let newWords: [ExportableTile]
        /// On the device with NO custom image; the file carries one → auto-fill.
        let fillWords: [ExportableTile]
        /// On the device WITH a custom image, and the file carries a (different)
        /// one → needs the importer's consent; never replaced without it.
        let collisions: [ExportableTile]
    }

    /// Categorize the file's custom tiles against the device's tiles. Word
    /// identity (key/displayName/wordClass) is never changed by import; this only
    /// governs images.
    static func analyze(_ exportable: ExportableScene, deviceTiles: [TileModel]) -> ImportAnalysis {
        let lookup = Dictionary(deviceTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var newWords: [ExportableTile] = []
        var fillWords: [ExportableTile] = []
        var collisions: [ExportableTile] = []
        for tile in exportable.tiles ?? [] {
            if let existing = lookup[tile.key] {
                guard tile.imageData != nil else { continue }   // nothing to offer
                if existing.userImageData == nil { fillWords.append(tile) }
                else { collisions.append(tile) }
            } else {
                newWords.append(tile)
            }
        }
        return ImportAnalysis(newWords: newWords, fillWords: fillWords, collisions: collisions)
    }

    /// Import a scene from JSON data.
    /// - Parameters:
    ///   - data: Raw JSON data in the ExportableScene format.
    ///   - context: The ModelContext to insert new objects into.
    /// - Returns: An ImportResult with the new scene and any warnings.
    static func importJSON(_ data: Data,
                           context: ModelContext,
                           sourceURL: String = "",
                           acceptedImageCollisions: Set<String> = [],
                           resolution: SceneImportResolution? = nil) throws -> ImportResult {
        let decoder = JSONDecoder()
        let exportable: ExportableScene
        do {
            exportable = try decoder.decode(ExportableScene.self, from: data)
        } catch {
            throw SceneImportError.decodingFailed(error.localizedDescription)
        }

        // Validate type
        guard exportable.type == BlasterSceneFormat.mediaType else {
            throw SceneImportError.invalidType(exportable.type)
        }

        // Validate version (accept any 1.x.x)
        guard exportable.version.hasPrefix("1.") else {
            throw SceneImportError.unsupportedVersion(exportable.version)
        }

        guard !exportable.pages.isEmpty else {
            throw SceneImportError.noPages
        }

        // Fetch existing tiles + categorize the file's custom tiles.
        let deviceTiles = try context.fetch(FetchDescriptor<TileModel>())
        var tileLookup = Dictionary(deviceTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let analysis = analyze(exportable, deviceTiles: deviceTiles)

        var newTileCount = 0
        var oversizedImages: [String] = []
        var imageUpdatedKeys: [String] = []

        // Decode a tile's image if present and within the size cap.
        func decodedImage(_ tile: ExportableTile) -> Data? {
            guard let base64 = tile.imageData, let decoded = Data(base64Encoded: base64) else { return nil }
            guard decoded.count <= BlasterSceneFormat.maxImageDataSize else {
                oversizedImages.append(tile.key)
                return nil
            }
            return decoded
        }

        // 1. New words → create the tile (with image if carried).
        for incoming in analysis.newWords {
            let tile = TileModel(key: incoming.key, value: incoming.displayName, wordClass: incoming.wordClass)
            if let image = decodedImage(incoming) { tile.userImageData = image }
            context.insert(tile)
            tileLookup[tile.key] = tile
            newTileCount += 1
        }

        // 2. Fill-if-empty → existing tile has no image; apply the shared one.
        for incoming in analysis.fillWords {
            guard let tile = tileLookup[incoming.key], let image = decodedImage(incoming) else { continue }
            tile.userImageData = image
            imageUpdatedKeys.append(incoming.key)
        }

        // 3. Collisions → only replace where the importer consented. Word
        //    identity is never touched.
        for incoming in analysis.collisions where acceptedImageCollisions.contains(incoming.key) {
            guard let tile = tileLookup[incoming.key], let image = decodedImage(incoming) else { continue }
            tile.userImageData = image
            imageUpdatedKeys.append(incoming.key)
        }

        // Build pages as inline PageSpec values. Tiles missing from the import
        // are reported in `skippedKeys` and dropped from their page.
        var skippedKeys: [String] = []
        let pages: [PageSpec] = exportable.pages.map { exportPage in
            let tiles: [TileEntry] = exportPage.tiles.compactMap { exportTile in
                guard tileLookup[exportTile.key] != nil else {
                    if !skippedKeys.contains(exportTile.key) {
                        skippedKeys.append(exportTile.key)
                    }
                    return nil
                }
                return TileEntry(
                    key: exportTile.key,
                    link: exportTile.link,
                    isAudible: exportTile.isAudible
                )
            }
            return PageSpec(key: exportPage.key, tiles: tiles)
        }

        // Decentralized identity carried in the file (absent on legacy exports).
        let incomingID = exportable.id ?? ""
        let incomingSlug = exportable.slug ?? (incomingID.isEmpty ? "" : SceneIdentity.slug(from: exportable.name))
        let incomingVersion = exportable.sceneVersion ?? ""
        let incomingAuthor = exportable.authorName ?? ""

        // Dedupe by sceneID: a scene already present with the same id is the SAME
        // published scene — refresh it in place (upgrade to the incoming version)
        // rather than piling up duplicate imports. Local flags (isActive/isDefault)
        // and the receiver's own `receivedLabel` are preserved.
        let existing: BlasterScene? = incomingID.isEmpty ? nil : (try? context.fetch(
            FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.sceneID == incomingID })
        ))?.first

        // Has the receiver edited their existing copy since importing it?
        let isModified = existing.map {
            $0.importedContentHash.isEmpty || $0.contentHash != $0.importedContentHash
        } ?? false

        // Apply `pages` + file metadata to a scene in place.
        func refresh(_ s: BlasterScene) {
            s.name = exportable.name
            s.descriptionText = exportable.description
            s.homePageKey = exportable.homePageKey
            s.slug = incomingSlug
            s.sceneVersion = incomingVersion
            s.authorName = incomingAuthor
            s.isImported = true
            s.sourceURL = sourceURL
            s.pages = pages
        }

        let scene: BlasterScene
        let wasUpdate: Bool

        if let existing, isModified {
            // The local copy diverged from what was imported. Never silently
            // clobber it — the caller prompts (keep mine / take update / keep both).
            switch resolution {
            case .none, .keepMine:
                // No write. `.none` reports the conflict so the caller can prompt.
                return ImportResult(
                    scene: existing, skippedKeys: skippedKeys, newTileCount: newTileCount,
                    oversizedImages: oversizedImages, imageUpdatedKeys: imageUpdatedKeys,
                    wasUpdate: false, needsReceiverLabel: false,
                    conflict: resolution == nil ? .modifiedExisting(name: existing.name) : .none)
            case .takeUpdate:
                refresh(existing)
                existing.importedContentHash = existing.contentHash
                scene = existing; wasUpdate = true
            case .keepBoth:
                // Fork: a new, locally-owned scene under this device's author id
                // so it doesn't collide with the edited copy (which keeps the id).
                let fork = BlasterScene(name: "\(exportable.name) (update)",
                                        descriptionText: exportable.description,
                                        homePageKey: exportable.homePageKey)
                fork.isImported = true
                fork.sourceURL = sourceURL
                fork.authorName = incomingAuthor
                fork.pages = pages
                fork.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: context),
                                    authorName: incomingAuthor)
                fork.importedContentHash = fork.contentHash
                try context.transaction { context.insert(fork) }
                scene = fork; wasUpdate = false
            }
        } else if let existing {
            // Clean re-import (unmodified) → refresh in place; no duplicate.
            refresh(existing)
            existing.importedContentHash = existing.contentHash
            scene = existing; wasUpdate = true
        } else {
            // Brand-new import.
            let newScene = BlasterScene(
                name: exportable.name,
                descriptionText: exportable.description,
                homePageKey: exportable.homePageKey
            )
            newScene.isImported = true
            newScene.sourceURL = sourceURL
            newScene.sceneID = incomingID
            newScene.slug = incomingSlug
            newScene.sceneVersion = incomingVersion
            newScene.authorName = incomingAuthor
            newScene.pages = pages
            newScene.importedContentHash = newScene.contentHash
            try context.transaction { context.insert(newScene) }
            scene = newScene; wasUpdate = false
        }

        return ImportResult(
            scene: scene,
            skippedKeys: skippedKeys,
            newTileCount: newTileCount,
            oversizedImages: oversizedImages,
            imageUpdatedKeys: imageUpdatedKeys,
            wasUpdate: wasUpdate,
            // Only offer a "from …" tag when we actually created a NEW,
            // non-first-party scene with no author — not on a refresh of a scene
            // already present, and never for BlasterAI content.
            needsReceiverLabel: !wasUpdate && incomingAuthor.isEmpty && !scene.isFirstParty
        )
    }

    /// Parse ExportableScene from JSON data without importing — for preview purposes.
    static func preview(_ data: Data) throws -> ExportableScene {
        let decoder = JSONDecoder()
        let exportable: ExportableScene
        do {
            exportable = try decoder.decode(ExportableScene.self, from: data)
        } catch {
            throw SceneImportError.decodingFailed(error.localizedDescription)
        }
        guard exportable.type == BlasterSceneFormat.mediaType else {
            throw SceneImportError.invalidType(exportable.type)
        }
        guard exportable.version.hasPrefix("1.") else {
            throw SceneImportError.unsupportedVersion(exportable.version)
        }
        return exportable
    }
}
