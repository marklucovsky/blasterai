// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PackTransfer.swift
//  claudeBlast
//
//  Export a page as a portable vocabulary pack, and import one back.
//

import Foundation
import SwiftData

enum PackImportError: LocalizedError {
    case invalidType(String)
    case unsupportedVersion(String)
    case decodingFailed(String)
    case noWords

    var errorDescription: String? {
        switch self {
        case .invalidType(let type):
            return "Not a Blaster pack file (type: \(type))"
        case .unsupportedVersion(let version):
            return "Unsupported pack format version: \(version)"
        case .decodingFailed(let detail):
            return "Could not read pack file: \(detail)"
        case .noWords:
            return "Pack has no words"
        }
    }
}

@MainActor
enum PackExporter {

    /// Turn one page into a portable pack.
    ///
    /// ## What is deliberately left behind
    ///
    /// **The links.** A page's `TileEntry.link` names a sibling page inside the
    /// scene it came from. On the far side that page does not exist, and there is
    /// no honest way to guess what it should point at — so a linking tile travels
    /// as an ordinary word and the recipient wires up navigation themselves when
    /// they build a page. This is the pack format's one lossy mapping, and it is
    /// the same *class* of loss that OBF export will have to record.
    ///
    /// **`isAudible`.** It is a property of a tile's placement on a page, not of
    /// the word. A pack has no placements.
    ///
    /// What survives is the words, their art, and their order.
    static func exportPage(_ page: PageSpec,
                           from scene: BlasterScene,
                           tileLookup: [String: TileModel],
                           context: ModelContext) -> ExportablePack {
        let authorID = DeviceProfileStore.ensureAuthorID(context: context)
        let authorName = DeviceProfileStore.authorName(context: context)

        let keys = page.tiles.map(\.key)
        let storedArt = ExportArtResolver.storedArt(for: keys, tileLookup: tileLookup, context: context)

        var seen = Set<String>()
        let words: [ExportablePackWord] = page.tiles.compactMap { entry in
            guard seen.insert(entry.key).inserted else { return nil }
            guard let tile = tileLookup[entry.key] else { return nil }
            let exported = SceneExporter.exportableTile(for: tile, art: storedArt[tile.key])
            return ExportablePackWord(key: exported.key,
                                      wordClass: exported.wordClass,
                                      displayName: exported.displayName,
                                      art: exported.art,
                                      imageData: exported.imageData)
        }

        let slug = SceneIdentity.slug(from: page.key)
        return ExportablePack(
            type: BlasterPackFormat.mediaType,
            version: BlasterPackFormat.currentVersion,
            id: SceneIdentity.id(authority: authorID, slug: slug),
            slug: slug,
            displayName: displayName(for: page, in: scene),
            packVersion: "1.0.0",
            authorName: authorName.isEmpty ? nil : authorName,
            sourceScene: scene.name.isEmpty ? nil : scene.name,
            sourcePage: page.key,
            words: words
        )
    }

    static func exportPageJSON(_ page: PageSpec,
                               from scene: BlasterScene,
                               tileLookup: [String: TileModel],
                               context: ModelContext) throws -> Data {
        try SceneExporter.encode(exportPage(page, from: scene, tileLookup: tileLookup, context: context))
    }

    /// A caregiver-facing name for the pack. Page keys are lowercase identifiers
    /// ("play_activities"); a shared file gets a name a person would type.
    static func displayName(for page: PageSpec, in scene: BlasterScene) -> String {
        page.key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

@MainActor
enum PackImporter {

    struct ImportResult {
        let pack: ReceivedPack
        /// Words created on this device that were not here before.
        let newWordCount: Int
        /// Words already present; their identity was left untouched.
        let existingWordCount: Int
        /// Keys that gained art for at least one set.
        let artUpdatedKeys: [String]
        /// Keys whose art was dropped for exceeding the size cap.
        let oversizedImages: [String]
        var wasUpdate: Bool = false
    }

    /// Side-effect-free decode, for previewing a pack before it lands.
    static func preview(_ data: Data) throws -> ExportablePack {
        let pack: ExportablePack
        do {
            pack = try JSONDecoder().decode(ExportablePack.self, from: data)
        } catch {
            throw PackImportError.decodingFailed(error.localizedDescription)
        }
        guard pack.type == BlasterPackFormat.mediaType else {
            throw PackImportError.invalidType(pack.type)
        }
        guard pack.version.hasPrefix("1.") else {
            throw PackImportError.unsupportedVersion(pack.version)
        }
        guard !pack.words.isEmpty else { throw PackImportError.noWords }
        return pack
    }

    /// Install a pack: its words join the vocabulary, its art joins
    /// `TileArtVariant`, and the pack itself is recorded so it stays a *named
    /// set* the caregiver can build a page from.
    ///
    /// **No page and no scene is created.** That is the whole difference between
    /// receiving a pack and receiving a scene, and it is deliberate: the sender's
    /// arrangement suited the sender's child. The recipient decides where these
    /// words go, using the same pickers that already offer the bundled packs.
    @discardableResult
    static func importJSON(_ data: Data, context: ModelContext) throws -> ImportResult {
        let pack = try preview(data)

        let deviceTiles = try context.fetch(FetchDescriptor<TileModel>())
        var lookup = Dictionary(deviceTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        let existingRow = try? context.fetch(
            FetchDescriptor<ReceivedPack>(predicate: #Predicate { $0.packID == pack.id })
        ).first

        let existingVariants = (try? context.fetch(FetchDescriptor<TileArtVariant>())) ?? []
        var heldVariants = Set(existingVariants.map { "\($0.tileKey)|\($0.imageSetRaw)" })

        var newWordCount = 0
        var existingWordCount = 0
        var artUpdatedKeys: [String] = []
        var oversizedImages: [String] = []

        for word in pack.words {
            let tile: TileModel
            if let existing = lookup[word.key] {
                // Word identity is never rewritten by an import. A pack that
                // disagrees about a word's class or display name does not get to
                // relabel vocabulary the caregiver is already using.
                tile = existing
                existingWordCount += 1
            } else {
                tile = TileModel(key: word.key, value: word.displayName, wordClass: word.wordClass)
                context.insert(tile)
                lookup[word.key] = tile
                newWordCount += 1
            }

            // The photo override, only where there is nothing to overwrite.
            if let base64 = word.imageData,
               let decoded = Data(base64Encoded: base64), !decoded.isEmpty {
                if decoded.count > BlasterSceneFormat.maxImageDataSize {
                    oversizedImages.append(word.key)
                } else if !tile.hasUserImage {
                    tile.userImageData = decoded
                    artUpdatedKeys.append(word.key)
                }
            }

            // Canonical per-set art → TileArtVariant, never userImageData. See
            // the note in SceneImporter.applyArt: the override outranks every
            // image set, so art filed there would pin the word to the sender's
            // style on all of the recipient's devices.
            for entry in word.art ?? [] {
                guard let decoded = Data(base64Encoded: entry.imageData), !decoded.isEmpty else { continue }
                guard decoded.count <= BlasterSceneFormat.maxImageDataSize else {
                    if !oversizedImages.contains(word.key) { oversizedImages.append(word.key) }
                    continue
                }
                let slot = "\(word.key)|\(entry.imageSet)"
                guard !heldVariants.contains(slot) else { continue }
                TileArtVariant.upsert(tileKey: word.key,
                                      imageSet: ImageSetID(entry.imageSet),
                                      imageData: decoded,
                                      context: context)
                heldVariants.insert(slot)
                if !artUpdatedKeys.contains(word.key) { artUpdatedKeys.append(word.key) }
            }
        }

        let row = ReceivedPack.upsert(pack, context: context)
        try? context.save()

        return ImportResult(pack: row,
                            newWordCount: newWordCount,
                            existingWordCount: existingWordCount,
                            artUpdatedKeys: artUpdatedKeys,
                            oversizedImages: oversizedImages,
                            wasUpdate: existingRow != nil)
    }
}
