// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ExportArtResolver.swift
//  claudeBlast
//
//  The single place export asks "what art travels with this tile?".
//

import Foundation
import SwiftData
import UIKit

/// What art an export carries for each tile, chosen by where the file is going.
///
/// The two cases are genuinely different questions, which is why this is a
/// policy and not a boolean:
///
/// - `.storedBytes` answers *"what does the recipient not already have?"*. It is
///   for Blaster→Blaster transfer, where the recipient ships the same bundled art
///   in the same five sets. Embedding a system word's picture would add ~14 KB to
///   deliver a byte-identical file the recipient already has — a full scene grows
///   ~9 MB to say nothing. So system words carry nothing, and a custom word
///   carries **every** variant its author holds.
///
/// - `.rendered` answers *"what does this tile look like?"*, for artifacts that
///   leave the app entirely — a PDF, a PNG, an OBZ. There is no shared
///   vocabulary on the far side, so every tile resolves to a picture.
enum ExportArtPolicy: Equatable {
    /// Stored bytes, verbatim, only for tiles the recipient cannot resolve.
    case storedBytes
    /// Every tile resolved to a picture, in the given sets.
    case rendered(sets: [ImageSetID])
}

/// The stored art a single tile would contribute to a Blaster→Blaster export.
struct StoredTileArt {
    /// Canonical per-style art, one entry per set the author has art for.
    var variants: [(set: ImageSetID, data: Data)] = []
    /// The removable camera-photo override, which is set-independent.
    var photo: Data?

    var isEmpty: Bool { variants.isEmpty && photo == nil }
}

@MainActor
enum ExportArtResolver {

    // MARK: - Blaster → Blaster

    /// Stored art for the given keys, for the `.storedBytes` policy.
    ///
    /// A key appears in the result only if it contributes something. Whether a
    /// word is "custom" is decided by `TileModel.isSystem`, not by whether art
    /// happens to resolve: provenance is stable, while art coverage varies per
    /// set and would make an export's contents depend on the sender's current
    /// style.
    static func storedArt(for keys: [String],
                          tileLookup: [String: TileModel],
                          context: ModelContext) -> [String: StoredTileArt] {
        let wanted = Set(keys)
        guard !wanted.isEmpty else { return [:] }

        var result: [String: StoredTileArt] = [:]

        // Photo overrides ride along for any tile that has one, system or not —
        // a caregiver who photographed their own kitchen table means it.
        for key in wanted {
            guard let tile = tileLookup[key] else { continue }
            var art = StoredTileArt()
            if tile.hasUserImage { art.photo = tile.userImageData }
            if !tile.isSystem { result[key] = art }
            else if art.photo != nil { result[key] = art }
        }

        // One fetch for all variants, filtered in memory: #Predicate cannot test
        // membership of a captured Set, and a per-key fetch would be N round
        // trips for a page that can hold 100+ tiles.
        let variants = (try? context.fetch(FetchDescriptor<TileArtVariant>())) ?? []
        for variant in variants where wanted.contains(variant.tileKey) {
            guard let tile = tileLookup[variant.tileKey], !tile.isSystem else { continue }
            guard !variant.imageData.isEmpty else { continue }
            result[variant.tileKey, default: StoredTileArt()]
                .variants.append((set: variant.imageSet, data: variant.imageData))
        }

        // Deterministic order so the same scene exports byte-identically twice —
        // otherwise `importedContentHash` comparisons see phantom edits.
        for key in result.keys {
            result[key]?.variants.sort { $0.set.rawValue < $1.set.rawValue }
        }

        return result.filter { !$0.value.isEmpty }
    }

    // MARK: - Leaving the app

    /// Every installed set, for a "render all styles" export.
    static var allInstalledSets: [ImageSetID] {
        ImageSetCatalog.all.map(\.id)
    }

    /// A tile's picture in a specific set, with the same fallback chain the
    /// child's board uses. Nil only when the tile has no art anywhere.
    static func rendered(_ key: String,
                         in set: ImageSetID,
                         resolver: TileImageResolver) -> UIImage? {
        resolver.resolved(key, in: set)
    }

    /// PNG bytes for a tile in a set. **The one place export produces PNG** —
    /// every Blaster→Blaster path ships the stored HEIC verbatim instead, and
    /// re-encoding there would inflate a scene roughly tenfold to deliver art the
    /// recipient already has.
    static func renderedPNG(_ key: String,
                            in set: ImageSetID,
                            resolver: TileImageResolver) -> Data? {
        rendered(key, in: set, resolver: resolver)?.pngData()
    }
}
