// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CacheKeyPolicy.swift
//  claudeBlast
//
//  Single source of truth for SentenceCache identity + eviction policy.
//
//  The cached sentence for a tile combination depends on more than the tile
//  keys: it depends on the *model* that generated it, the *prompt* version that
//  shaped it, the child's *Brown's Stage* (the system prompt embeds "{stage}"), and each
//  tile's *word class* (the prompt annotates every tile — "pony (animal)" vs
//  "pony (object)" — and the category-honor rule makes that annotation
//  authoritative). The cache key folds in all of them, so a model swap, a prompt
//  change, a stage difference, or a vocabulary *reclassification* stops serving
//  stale outputs instead of returning a sentence built under the old meaning.
//
//  `nonisolated` throughout: this is a pure policy helper (constants + pure
//  functions) and must be callable from any isolation domain — including the
//  `@Model` initializer and the nonisolated default-argument context of
//  `evictStale`.
//

import Foundation

enum CacheKeyPolicy {
    /// The sentence model. `OpenAISentenceProvider` references this same constant
    /// so the request model and the cache version can never silently diverge.
    nonisolated static let modelID = ModelID.sentence

    /// Bump this whenever a prompt/rubric change should invalidate every cached
    /// sentence. Entries stamped with a different `versionToken` are swept:
    /// automatically at launch (`evictStale`) and on demand from Admin
    /// (`pruneStaleVersions`), regardless of TTL.
    // v3: Brown's Stages replace the birthday-derived grade level in the system
    // prompt (2026-08). Every v2 entry was generated under "grammar and vocabulary
    // of a {grade} student" and is stale by construction, so the bump is the point
    // rather than a side effect — see BrownsStage.
    //
    // v4: tile order declared incidental (2026-09). Until then the prompt said
    // nothing about what tap order meant, so the model guessed — and guessed
    // differently per phrasing, putting the name first for "dad, i, thirsty" and
    // last for "hungry, i, dad".
    //
    // The bump matters more than a wording change usually would, because this key
    // is deliberately order-independent: two orders of the same tiles share one
    // entry, so whichever order was generated first won forever and the
    // inconsistency was invisible on every later hit. Every v3 entry was produced
    // under that ambiguity and one of the two readings is now wrong.
    //
    // v5: pronoun, report and negation rules (2026-10, the eval harness's
    // first prompt revision). v4 turned "she, pool" into "She, I want to go to
    // the pool", "dog, bite, me" into "Dog, bite me!" and dropped "not"; those
    // sentences are wrong, and cached they would outlive the fix.
    //
    // v6: school, toilet and bathroom refiled from social to places, and a
    // vehicle with a place made a trip (2026-10-20). As `social`, "school, i,
    // bus" opened like a greeting — "School, I ride the bus." — and "i, park,
    // bus" became "I want the bus to the park"; both are cached under v5.
    nonisolated static let promptVersion = 6

    /// Stamped onto each cache entry (`SentenceCache.keyVersion`) and embedded in
    /// the key. Excludes stage + word class on purpose — those are legitimate
    /// parallel entries, not staleness signals.
    nonisolated static var versionToken: String { "\(modelID)/v\(promptVersion)" }

    // MARK: - Eviction policy

    /// Entries unused (by `lastUsed`) for longer than this are evicted at launch.
    nonisolated static let maxAge: TimeInterval = 180 * 24 * 60 * 60   // 180 days

    /// Hard cap on unpinned entry count; the least-recently-used overflow is
    /// evicted. Pinned entries are always exempt and never counted against it.
    nonisolated static let maxCount = 2_000

    // MARK: - Key construction

    /// Canonical key: `<model>/v<promptVersion>/b<stage>#<sorted key:class pairs>`.
    /// Tiles are deduplicated by key + sorted (selection order doesn't matter),
    /// and each carries its word class so a reclassification — e.g. `pony`
    /// object→animal — changes the key, missing the stale entry and regenerating.
    nonisolated static func key(for tiles: [TileSelection], stage: BrownsStage) -> String {
        let pairs = tiles
            .reduce(into: [String: String]()) { $0[$1.key] = $1.wordClass }   // dedupe by key
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        return "\(versionToken)/b\(stage.rawValue)#\(pairs)"
    }

    /// Version-INDEPENDENT identity for a tile combination + child. Unlike `key`,
    /// this excludes the model, prompt version, stage, and word class — it is just
    /// the sorted, deduplicated tile keys plus the child. Durable caregiver
    /// overrides (hand-typed / suppressed / accepted-refine sentences) are matched
    /// on this so they OUTLIVE a model swap, a `promptVersion` bump, a stage
    /// change, or a reclassification — the things that intentionally rotate `key`
    /// and strand ordinary cache entries. A caregiver's correction is about *the
    /// words the child picked*, not the machinery that generated the sentence.
    nonisolated static func stableKey(for tiles: [TileSelection], childID: String?) -> String {
        let keys = Set(tiles.map(\.key)).sorted().joined(separator: ",")
        return "\(keys)|\(childID ?? "")"
    }
}
