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

/// The tile art styles the app knows about.
///
/// **ARASAAC was removed 2026-08-14.** It was the app's original art source and
/// the reason `classic` exists — building a clean-room set meant first learning
/// what good AAC pictograms look like, and ARASAAC taught that. Its job is done:
/// `classic` covers the full vocabulary, is ours, and carries no licence
/// encumbrance, where ARASAAC is CC BY-NC-SA (non-commercial). It also never
/// left the bundle — `isShippable: false` hid it from the picker while 15 MB of
/// it shipped in every build from `Assets.xcassets`.
enum ImageSetID: String, CaseIterable, Identifiable {
    case playful3D = "playful_3d"
    case classic = "classic"
    case highContrast = "high_contrast"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playful3D: return "Playful 3D"
        case .classic: return "Classic"
        case .highContrast: return "High Contrast"
        }
    }

    /// Compact label for tight UI (e.g. the per-style review strip).
    var shortName: String {
        switch self {
        case .playful3D: return "Playful 3D"
        case .classic: return "Classic"
        case .highContrast: return "Contrast"
        }
    }

    var description: String {
        switch self {
        case .playful3D: return "Modern clay/plasticine 3D style"
        case .classic: return "Flat pictogram style"
        case .highContrast: return "Bold white-on-black accessibility style"
        }
    }

    /// Whether this set is **complete** — ships reviewed, real art for every
    /// vocabulary key — and is therefore offered to end users as a first-class
    /// choice.
    ///
    /// Norm: anything we ship must be complete and reviewed, and we hold any
    /// community-contributed set we bless as shippable to the same bar. The
    /// Playful-3D master backfill (`TileImageResolver.image(for:)`) removes the
    /// *absolute* need for completeness so you can prototype an alternate style
    /// without first generating the whole world — but an incomplete set stays a
    /// development-only affordance, hidden from the release picker until it has
    /// been reviewed and regenerated to full coverage.
    ///
    /// High Contrast is currently incomplete (~20 vocabulary gaps) and is
    /// pending a full review + regen pass before it can ship.
    ///
    /// **`isShippable` controls the picker, not the bundle.** It hides a set
    /// from users; it removes nothing from the binary. ARASAAC sat at `false`
    /// for months while 15 MB of it shipped in every build, and High Contrast
    /// does the same today from `TileImageSets/`. Keeping art out of the app is
    /// a build-phase question, not an enum question.
    var isShippable: Bool {
        switch self {
        case .playful3D:    return true   // master set — full coverage, reviewed
        case .classic:      return true   // complete clean-room set
        case .highContrast: return false  // pending full review + regen
        }
    }

    /// Sets offered to end users. In release builds only complete sets appear;
    /// debug builds expose every set (incomplete ones flagged) so alternate
    /// tile sets can be developed against the live app.
    static var selectable: [ImageSetID] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter(\.isShippable)
        #endif
    }

    /// The set a new install starts on, and what the onboarding style question
    /// preselects.
    ///
    /// **Classic, not Playful 3D** (changed 2026-08-14). Flat pictograms are the
    /// visual language the field already speaks — ARASAAC, CBoard, CoughDrop,
    /// and most laminated paper boards. A child arriving from any of those keeps
    /// the vocabulary they already learned, and the relearning cost of a
    /// different style is paid by the person least able to absorb it. Two
    /// supporting reasons: flat art is what survives being printed at 2 inches
    /// (photographic renders go soft), and abstract words — *is*, *are*, *that* —
    /// lean on symbol convention rather than realism.
    ///
    /// Playful 3D isn't demoted so much as reassigned: it's the proof the
    /// generator can produce any style, which is the actual claim.
    static let defaultSet: ImageSetID = .classic

    /// Fills a gap when the active set lacks a key, so an incomplete or
    /// in-progress set still renders something correct rather than a placeholder.
    ///
    /// Separate constant from `defaultSet` even though both are Classic today —
    /// they answer different questions ("what do we start on" vs "what covers a
    /// hole"), and the backfill must always be a set with **full vocabulary
    /// coverage**. Classic and Playful 3D both qualify; High Contrast v1 does not
    /// (23 gaps), v2 does.
    static let universalBackfill: ImageSetID = .classic

    /// Styles AI art is generated for — the authored, first-class sets, default
    /// first. High Contrast is excluded while it is unshipped.
    static var generationTargets: [ImageSetID] { [.classic, .playful3D] }

    /// Generation targets ordered so `preferred` (usually the active set) comes
    /// first. A newly-generated tile then shows the right style as soon as its
    /// first variant lands — the other styles fill in behind it — instead of
    /// briefly showing whichever style happened to finish first (e.g. a p3d flash
    /// while in Classic mode).
    static func generationTargets(preferring preferred: ImageSetID) -> [ImageSetID] {
        guard generationTargets.contains(preferred) else { return generationTargets }
        return [preferred] + generationTargets.filter { $0 != preferred }
    }
}

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
        switch imageSet {
        case .playful3D:
            return prefixedBundleImage(for: key, prefix: "p3d")

        case .classic:
            return prefixedBundleImage(for: key, prefix: "cls")

        case .highContrast:
            return prefixedBundleImage(for: key, prefix: "hc")
        }
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
        for set in ImageSetID.allCases {
            let pair = "\(set.rawValue):\(key)"
            variantCache.removeObject(forKey: NSString(string: "variant:\(pair)"))
            variantMisses.remove(pair)
        }
        variantCache.removeObject(forKey: NSString(string: "variant:any:\(key)"))
        variantMisses.remove("any:\(key)")
        revision &+= 1
    }

    /// The active set's shared missing-art placeholder, if it ships one.
    /// Only High Contrast does today (`hc_missing.png`). This is now a defensive
    /// last resort: the Playful-3D backfill (step 3 of `image(for:)`) runs first
    /// and, with full master coverage, supplies art for every known tile — so a
    /// sparse High Contrast tile shows the master art, and this placeholder is
    /// only reached for a key even P3D lacks. Cached on first load.
    private func placeholderImage(for imageSet: ImageSetID) -> UIImage? {
        let prefix: String
        switch imageSet {
        case .highContrast: prefix = "hc"
        case .playful3D, .classic: return nil
        }
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
        switch prefix {
        case "hc": return "hc_missing"
        default:   return nil
        }
    }
}
