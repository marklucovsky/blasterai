// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageResolver.swift
//  claudeBlast
//
//  Centralized tile image resolution with support for multiple image sets.
//  Injected as an environment object; all tile image rendering flows through here.

import SwiftUI
import UIKit
import SwiftData
import Observation
// MARK: - Image Set Identifier
//
// `ImageSetID` and the set catalog now live in `ImageSetCatalog.swift`.
//
// It was an enum here, which worked while sets were a fixed list baked into the
// build. It stopped working the moment sets became *content*: a downloadable or
// caregiver-authored set cannot be an enum case, skin-tone variants multiply
// cases combinatorially, and `ImageSetID(rawValue:) ?? .playful3D` answered an
// unknown id by silently rendering a different set's art. Identity, metadata,
// and mutability now follow the same model scenes use — see
// `docs/scene-identity.md`.

// MARK: - Tile Image Resolver



@Observable
@MainActor
final class TileImageResolver {

    /// The currently active image set. Changing this causes all tiles to re-render.
    /// See `ImageSetID.defaultSet` for why this starts on Classic.
    var activeSet: ImageSetID = ImageSetID.defaultSet

    /// Bumped whenever a per-key photo override is added or removed so SwiftUI
    /// views that read it (TileImageView) re-render. NSCache reads/writes are
    /// not observable on their own, so this is the explicit invalidation signal.
    private(set) var revision = 0

    /// In-memory cache for non-asset-catalog images (keyed by "setID:tileKey").
    private var cache = NSCache<NSString, UIImage>()

    /// SwiftData context used to fetch per-tile photo overrides
    /// (`TileModel.userImageData`). Wired via `configure` at launch, mirroring
    /// `ChildProfileResolver`. Nil before configuration → overrides are skipped.
    private var context: ModelContext?

    /// Decoded photo overrides, keyed "override:<tileKey>".
    private var overrideCache = NSCache<NSString, UIImage>()

    /// Keys known to have NO photo override. Without this negative cache every
    /// render of every photo-less tile (the vast majority) would issue a fetch.
    private var overrideMisses = Set<String>()

    /// Decoded custom per-style art (TileArtVariant), keyed "variant:<set>:<key>"
    /// (and "variant:any:<key>" for the cross-style fallback), plus a negative
    /// cache of "<set>:<key>" / "any:<key>" with no variant — so bundled tiles
    /// never fetch.
    private var variantCache = NSCache<NSString, UIImage>()
    private var variantMisses = Set<String>()

    init() {
        cache.countLimit = 600 // ~500 tiles + headroom
        overrideCache.countLimit = 600
        variantCache.countLimit = 600
    }

    /// Wire the SwiftData context so photo overrides can be resolved. Safe to
    /// call multiple times; clears any cached override state so a fresh store
    /// is re-read.
    func configure(modelContext: ModelContext) {
        self.context = modelContext
        overrideCache.removeAllObjects()
        overrideMisses.removeAll()
        variantCache.removeAllObjects()
        variantMisses.removeAll()
    }

    /// Resolve a UIImage for the given tile key, applying the full fallback
    /// chain. A caregiver-supplied photo override (`TileModel.userImageData`)
    /// wins over every image set, so it is consulted first.
    ///
    /// Fallback order:
    ///   1. caregiver photo override
    ///   2. the active set's real art
    ///   3. **Playful-3D backfill** — the master set is the most complete and
    ///      backs up any sparser active set (High Contrast, a future or
    ///      downloaded set). Skipped when the backfill set is already active.
    ///   4. the active set's own missing-art placeholder (currently only High
    ///      Contrast ships one). With full backfill coverage this is rarely
    ///      reached; kept defensively.
    ///   5. nil → TileImageView renders its letter-on-color placeholder.
    func image(for key: String) -> UIImage? {
        if let photo = userPhoto(for: key) { return photo }
        if let img = rawImage(for: key, in: activeSet) { return img }
        if activeSet != ImageSetID.universalBackfill,
           let img = rawImage(for: key, in: ImageSetID.universalBackfill) { return img }
        // A custom word arted in only one style still shows (its variant) in others.
        if let img = anyVariantImage(for: key) { return img }
        return placeholderImage(for: activeSet)
    }

    /// Resolve a tile's real art in a specific image set — no placeholder, no
    /// master-set backfill. Returns nil when that set genuinely lacks the tile.
    func image(for key: String, in imageSet: ImageSetID) -> UIImage? {
        rawImage(for: key, in: imageSet)
    }

    /// Check whether a tile has bundled art. True when the active set OR the
    /// backfill set ships real art for the key — i.e. it's a known bundled tile,
    /// not a custom user-only one. Deliberately bypasses photo overrides and
    /// placeholders: callers (e.g. export's `defaultTileKeys`) use this to decide
    /// whether a tile relies on bundled art, and a caregiver photo must not make
    /// a custom tile look bundled.
    func hasImage(for key: String) -> Bool {
        if bundledImage(for: key, in: activeSet) != nil { return true }
        return bundledImage(for: key, in: ImageSetID.universalBackfill) != nil
    }

    /// Raw art for a key in a set, with no placeholder or backfill. This is the
    /// single switch over set → asset lookup used by the public resolvers.
    private func rawImage(for key: String, in imageSet: ImageSetID) -> UIImage? {
        if let bundled = bundledImage(for: key, in: imageSet) { return bundled }
        return variantImage(for: key, in: imageSet)
    }

    /// Bundled system art only ({prefix}_{key}.png in TileImageSets/). No custom
    /// variants, no placeholder — the single source of "is this a bundled tile".
    ///
    /// Every set now resolves from `TileImageSets/`. The asset catalog holds no
    /// tile art at all since ARASAAC was removed — only the app icon and accent
    /// colour.
    private func bundledImage(for key: String, in imageSet: ImageSetID) -> UIImage? {
        // Catalog lookup rather than a switch: an installed set has no case to
        // match, and adding a set should not require editing this function.
        prefixedBundleImage(for: key,
                            prefix: ImageSetCatalog.bundlePrefix(for: imageSet))
    }

    // MARK: - Custom per-style art (TileArtVariant, synced)

    /// Decoded custom art for `key` in `imageSet`, or nil. Positive + negative
    /// caches keep bundled tiles from ever fetching.
    private func variantImage(for key: String, in imageSet: ImageSetID) -> UIImage? {
        guard let context else { return nil }
        let pair = "\(imageSet.rawValue):\(key)"
        if variantMisses.contains(pair) { return nil }
        let cacheKey = NSString(string: "variant:\(pair)")
        if let cached = variantCache.object(forKey: cacheKey) { return cached }

        let raw = imageSet.rawValue
        var descriptor = FetchDescriptor<TileArtVariant>(
            predicate: #Predicate { $0.tileKey == key && $0.imageSetRaw == raw }
        )
        descriptor.fetchLimit = 1
        if let variant = try? context.fetch(descriptor).first,
           let img = UIImage(data: variant.imageData) {
            variantCache.setObject(img, forKey: cacheKey)
            return img
        }
        variantMisses.insert(pair)
        return nil
    }

    /// Any variant for `key` (preferring the backfill set), for the cross-style
    /// fallback — a word arted in one style still shows in another.
    private func anyVariantImage(for key: String) -> UIImage? {
        guard let context else { return nil }
        let missKey = "any:\(key)"
        if variantMisses.contains(missKey) { return nil }
        let cacheKey = NSString(string: "variant:any:\(key)")
        if let cached = variantCache.object(forKey: cacheKey) { return cached }

        var descriptor = FetchDescriptor<TileArtVariant>(predicate: #Predicate { $0.tileKey == key })
        descriptor.fetchLimit = 5
        guard let variants = try? context.fetch(descriptor), !variants.isEmpty else {
            variantMisses.insert(missKey); return nil
        }
        let chosen = variants.first { $0.imageSetRaw == ImageSetID.universalBackfill.rawValue } ?? variants[0]
        guard let img = UIImage(data: chosen.imageData) else {
            variantMisses.insert(missKey); return nil
        }
        variantCache.setObject(img, forKey: cacheKey)
        return img
    }

    /// Invalidate cached variants for `key` after art is (re)generated, and bump
    /// `revision` so views re-render.
    func invalidateVariants(for key: String) {
        // Every known set, including installed ones — a variant cached under an
        // installed set's id must invalidate too, or regenerated art keeps
        // showing the old image until relaunch.
        for set in ImageSetCatalog.all.map(\.id) {
            let pair = "\(set.rawValue):\(key)"
            variantCache.removeObject(forKey: NSString(string: "variant:\(pair)"))
            variantMisses.remove(pair)
        }
        variantCache.removeObject(forKey: NSString(string: "variant:any:\(key)"))
        variantMisses.remove("any:\(key)")
        revision &+= 1
    }

    /// Drop every cached answer that CloudKit can change underneath us, and bump
    /// `revision` so views re-render.
    ///
    /// ## The negative caches are the reason this exists
    ///
    /// `variantMisses` and `overrideMisses` record "this key has no art", and
    /// they have to: without them every render of every bundled tile — the vast
    /// majority — issues a SwiftData fetch. But a miss is only true until another
    /// device says otherwise.
    ///
    /// The bug: a phone showing the letter placeholder for a word has cached a
    /// miss for it. Art made for that word on another device syncs down
    /// correctly, and the phone keeps rendering the placeholder until it is
    /// relaunched, because nothing ever retracts the miss. The data was there the
    /// whole time — opening the tile's style strip showed it, since that asks
    /// about sets the grid had never queried and so never poisoned.
    ///
    /// Everything is dropped rather than diffed against the import: the notice
    /// says only that *something* changed, coalescing a burst of records. Bundled
    /// art (`cache`) is deliberately kept — it ships in the binary and no sync can
    /// alter it. What is dropped refills lazily on the next render.
    func invalidateSyncedArt() {
        variantCache.removeAllObjects()
        variantMisses.removeAll()
        overrideCache.removeAllObjects()
        overrideMisses.removeAll()
        revision &+= 1
    }

    /// The active set's shared missing-art placeholder, if it ships one.
    /// Only High Contrast does today (`hc_missing.png`). This is now a defensive
    /// last resort: the Playful-3D backfill (step 3 of `image(for:)`) runs first
    /// and, with full master coverage, supplies art for every known tile — so a
    /// sparse High Contrast tile shows the master art, and this placeholder is
    /// only reached for a key even P3D lacks. Cached on first load.
    private func placeholderImage(for imageSet: ImageSetID) -> UIImage? {
        // Any set may ship a `{prefix}_missing` placeholder; only High Contrast
        // does today. Driven by what is actually in the bundle rather than a
        // hardcoded list, so an installed set can supply one too.
        let prefix = ImageSetCatalog.bundlePrefix(for: imageSet)
        guard let placeholderName = Self.missingPlaceholderName(for: prefix) else { return nil }
        let cacheKey = NSString(string: placeholderName)
        if let cached = cache.object(forKey: cacheKey) { return cached }
        // Same extension order as real art — the placeholder is re-encoded by the
        // same pipeline, so hardcoding .png here would break it silently.
        for ext in Self.bundledExtensions {
            if let url = Bundle.main.url(forResource: placeholderName, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                cache.setObject(img, forKey: cacheKey)
                return img
            }
        }
        return nil
    }

    // MARK: - Photo overrides

    /// Resolve a caregiver-supplied photo override for `key`, or nil. Uses a
    /// positive cache + a negative (`overrideMisses`) cache so photo-less tiles
    /// — almost all of them — cost at most one fetch ever.
    private func userPhoto(for key: String) -> UIImage? {
        guard context != nil else { return nil }
        if overrideMisses.contains(key) { return nil }
        let cacheKey = NSString(string: "override:\(key)")
        if let cached = overrideCache.object(forKey: cacheKey) { return cached }

        var descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let tile = try? context?.fetch(descriptor).first,
           tile.hasUserImage,
           let img = UIImage(data: tile.userImageData) {
            overrideCache.setObject(img, forKey: cacheKey)
            return img
        }
        overrideMisses.insert(key)
        return nil
    }

    /// Invalidate the cached override for `key` after its photo is added or
    /// removed, and bump `revision` so views showing that tile re-render.
    func invalidatePhoto(for key: String) {
        overrideCache.removeObject(forKey: NSString(string: "override:\(key)"))
        overrideMisses.remove(key)
        revision &+= 1
    }

    // MARK: - Private

    /// Extensions tried, in order, for bundled tile art.
    ///
    /// **HEIC is what ships** — 512×512 at quality 65, which took the three sets
    /// from 273 MB to 22 MB with no visible loss on screen or in a 2-inch print
    /// proof (reviewed 2026-08-15). PNG stays in the list because a set built
    /// before the re-encode, or one an open-source user generates themselves,
    /// should still resolve rather than silently render a placeholder.
    private static let bundledExtensions = ["heic", "png"]

    /// Load a prefixed image's real art from the bundle root
    /// ({prefix}_{key}.heic). Non-asset-catalog images land at the bundle root
    /// with the synchronized group build system. Uses NSCache to avoid repeated
    /// disk reads. Returns nil on a miss — the backfill and placeholder fallback
    /// are handled by `image(for:)` / `placeholderImage(for:)`, not here.
    private func prefixedBundleImage(for key: String, prefix: String) -> UIImage? {
        let resourceName = "\(prefix)_\(key)"
        let cacheKey = NSString(string: resourceName)

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        for ext in Self.bundledExtensions {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                cache.setObject(img, forKey: cacheKey)
                return img
            }
        }

        return nil
    }

    /// Per-prefix missing-image placeholder name (without `.png`).
    /// Currently only the high-contrast set has a shared placeholder; the
    /// other sets fall through to TileImageView's letter-on-color rendering.
    private static func missingPlaceholderName(for prefix: String) -> String? {
        // By convention any set may ship `{prefix}_missing`; the lookup below
        // returns nil when it doesn't, so this needs no per-set list.
        switch prefix {
        case "": return nil
        default: return "\(prefix)_missing"
        }
    }
}
