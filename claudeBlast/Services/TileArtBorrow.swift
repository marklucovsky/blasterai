// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileArtBorrow.swift
//  claudeBlast
//
//  One word showing another word's picture: `pup` drawn with `dog`'s art.
//

import Foundation
import SwiftData

enum TileArtBorrow {
    /// `tile` shows `source`'s picture from now on.
    ///
    /// Set art travels as an alias (`bundleImage`), so every style follows
    /// and nothing is copied. The source's own alias is followed, since the
    /// resolver looks an alias up once and does not chain. A caregiver photo
    /// is a picture too: it comes along as a copy, and one already on `tile`
    /// goes, or it would hide what was chosen.
    static func use(_ source: TileModel, on tile: TileModel) {
        guard source.key != tile.key else { return }
        tile.bundleImage = source.artKey
        tile.userImageData = source.hasUserImage ? source.userImageData : Data()
    }

    /// Back to the word's own art.
    static func restoreOwn(_ tile: TileModel) {
        tile.bundleImage = tile.key
    }

    /// The word's picture is another word's.
    static func isBorrowed(_ tile: TileModel) -> Bool {
        !tile.bundleImage.isEmpty && tile.bundleImage != tile.key
    }

    /// The picture changed under `tile`: save, and drop what the resolver
    /// cached for it (aliases, its photo).
    @MainActor
    static func changed(_ tile: TileModel, context: ModelContext, resolver: TileImageResolver) {
        try? context.save()
        resolver.invalidateAliases()
        resolver.invalidatePhoto(for: tile.key)
    }
}
