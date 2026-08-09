// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileArtVariant.swift
//  claudeBlast
//
//  Canonical per-style art for a CUSTOM tile (AI-generated or pack-delivered).
//  System vocabulary uses bundled p3d_/cls_ art; a custom word stores one
//  variant per style here — so it's a full vocabulary member whose art syncs via
//  CloudKit (externalStorage → CKAsset) and follows the child across devices.
//
//  This is the word's *canonical* art. The removable camera-photo override lives
//  separately on `TileModel.userImageData` and sits on top (nil → revert here).
//

import Foundation
import SwiftData

@Model
final class TileArtVariant {
    var tileKey: String = ""
    var imageSetRaw: String = ""
    @Attribute(.externalStorage) var imageData: Data = Data()
    /// Last write, not first — `upsert` re-stamps this on an existing variant
    /// when art is regenerated or refined. Named `modified` because that's what
    /// it means; it was `created` before the pre-promotion schema audit.
    var modified: Date = Date.now

    var imageSet: ImageSetID { ImageSetID(rawValue: imageSetRaw) ?? .playful3D }

    init(tileKey: String, imageSet: ImageSetID, imageData: Data) {
        self.tileKey = tileKey
        self.imageSetRaw = imageSet.rawValue
        self.imageData = imageData
        self.modified = .now
    }
}

extension TileArtVariant {
    /// Replace (or create) the variant for `tileKey` + `imageSet`. Idempotent —
    /// one variant per (key, set). Caller saves + invalidates the resolver.
    @discardableResult
    static func upsert(tileKey: String, imageSet: ImageSetID,
                       imageData: Data, context: ModelContext) -> TileArtVariant {
        let raw = imageSet.rawValue
        let descriptor = FetchDescriptor<TileArtVariant>(
            predicate: #Predicate { $0.tileKey == tileKey && $0.imageSetRaw == raw }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.imageData = imageData
            existing.modified = .now
            return existing
        }
        let variant = TileArtVariant(tileKey: tileKey, imageSet: imageSet, imageData: imageData)
        context.insert(variant)
        return variant
    }
}
