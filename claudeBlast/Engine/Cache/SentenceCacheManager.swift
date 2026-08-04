// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceCacheManager.swift
//  claudeBlast
//

import SwiftData
import Foundation
import os

@MainActor
final class SentenceCacheManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "SentenceCache")

    let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    /// Build a canonical cache key. Folds in the model + prompt version and the
    /// child's grade (both change the generated sentence), then the deduplicated,
    /// sorted tile keys. See `CacheKeyPolicy`.
    static func cacheKey(for tiles: [TileSelection], grade: Int) -> String {
        CacheKeyPolicy.key(for: tiles, grade: grade)
    }

    /// Increment hitCount for an existing cache entry without returning the sentence.
    /// Called on escalation paths that bypass the cache for generation but should still count usage.
    func recordHit(tiles: [TileSelection], grade: Int) {
        let key = Self.cacheKey(for: tiles, grade: grade)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return }
        entry.hitCount += 1
        entry.lastUsed = .now
    }

    /// Look up a cached sentence. Returns nil on miss; increments hitCount on hit.
    func lookup(tiles: [TileSelection], grade: Int) -> SentenceCache? {
        let key = Self.cacheKey(for: tiles, grade: grade)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1

        guard let entry = try? context.fetch(descriptor).first else {
            return nil
        }

        entry.hitCount += 1
        entry.lastUsed = .now
        return entry
    }

    /// Store or update a cached sentence for the given tiles.
    /// `childID` is stamped on new entries so future per-child analytics can
    /// filter on it. Existing entries retain their original `childID`.
    /// Every write (re)stamps `keyVersion` with the current `CacheKeyPolicy`.
    func store(tiles: [TileSelection], grade: Int, sentence: String, audioData: String = "",
               childID: String? = nil) {
        let key = Self.cacheKey(for: tiles, grade: grade)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.sentence = sentence
            existing.audioData = audioData
            existing.lastUsed = .now
            existing.keyVersion = CacheKeyPolicy.versionToken
        } else {
            let entry = SentenceCache(tiles: tiles, grade: grade, sentence: sentence,
                                      audioData: audioData, childID: childID)
            context.insert(entry)
        }
    }

    // MARK: - Durable caregiver overrides (refine / hand-type / suppress)

    static func stableKey(for tiles: [TileSelection], childID: String?) -> String {
        CacheKeyPolicy.stableKey(for: tiles, childID: childID)
    }

    /// The durable caregiver override for this tile combination, if any. Matched
    /// on the version-INDEPENDENT `stableKey`, so it outlives model/prompt/grade/
    /// class changes (unlike `lookup`, which keys on the versioned `cacheKey`).
    /// Returns hand-typed, suppressed, or accepted-refine entries — a hand-edit or
    /// suppress outranks an accepted refine. Checked BEFORE `lookup` in the engine.
    func overrideLookup(tiles: [TileSelection], childID: String?) -> SentenceCache? {
        fetchOverrides(tiles: tiles, childID: childID).sorted {
            $0.overrideRank != $1.overrideRank ? $0.overrideRank > $1.overrideRank
                                               : $0.lastUsed > $1.lastUsed
        }.first
    }

    /// Durable override rows for a combination + child, matched on the version-
    /// independent stableKey. Shared by `overrideLookup` (picks the winner) and
    /// `clearOverride` (clears them all).
    private func fetchOverrides(tiles: [TileSelection], childID: String?) -> [SentenceCache] {
        let sk = Self.stableKey(for: tiles, childID: childID)
        let descriptor = FetchDescriptor<SentenceCache>(predicate: #Predicate { $0.stableKey == sk })
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isOverride)
    }

    /// Find-or-create the entry for this combination (by versioned `cacheKey`),
    /// so an override upserts onto any existing cached sentence rather than
    /// duplicating it.
    private func entry(for tiles: [TileSelection], grade: Int, childID: String?) -> SentenceCache {
        let key = Self.cacheKey(for: tiles, grade: grade)
        var descriptor = FetchDescriptor<SentenceCache>(predicate: #Predicate { $0.cacheKey == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = SentenceCache(tiles: tiles, grade: grade, sentence: "", childID: childID)
        context.insert(created)
        return created
    }

    /// Store a caregiver HAND-TYPED sentence as a durable, version-independent
    /// override — pinned (eviction-exempt) and authoritative. Served for this
    /// combination regardless of what the model would generate.
    func setHandTyped(tiles: [TileSelection], grade: Int, sentence: String, childID: String?) {
        let e = entry(for: tiles, grade: grade, childID: childID)
        e.sentence = sentence
        e.isCaregiverEdited = true
        e.isSuppressed = false
        e.isPinned = true
        e.keyVersion = CacheKeyPolicy.versionToken
        e.lastUsed = .now
    }

    /// SUPPRESS a tile combination: the cached sentence is never served or
    /// re-stored as canonical; the engine regenerates live each time. Durable +
    /// pinned so a bad answer can't come back after eviction. Reversible.
    func setSuppressed(tiles: [TileSelection], grade: Int, childID: String?) {
        let e = entry(for: tiles, grade: grade, childID: childID)
        e.isSuppressed = true
        e.isCaregiverEdited = false
        e.isPinned = true
        e.lastUsed = .now
    }

    /// Record an ACCEPTED refine/try-again result: the fresh sentence becomes a
    /// pinned, TTL-immune, version-independent override. Repeated refines reaffirm
    /// the same entry. `unsuppresses` so a re-refine of a suppressed combo restores
    /// a served sentence.
    func setAcceptedRefine(tiles: [TileSelection], grade: Int, sentence: String, childID: String?) {
        let e = entry(for: tiles, grade: grade, childID: childID)
        e.sentence = sentence
        e.caregiverAccepted = true
        e.isSuppressed = false
        e.isPinned = true
        e.keyVersion = CacheKeyPolicy.versionToken
        e.lastUsed = .now
    }

    /// Clear all override intent for a combination (restore normal AI caching).
    func clearOverride(tiles: [TileSelection], childID: String?) {
        for e in fetchOverrides(tiles: tiles, childID: childID) {
            e.isCaregiverEdited = false
            e.isSuppressed = false
            e.caregiverAccepted = false
            e.isPinned = false
        }
    }

    /// Fetch all cache entries, sorted by most recently used.
    func allEntries() -> [SentenceCache] {
        let descriptor = FetchDescriptor<SentenceCache>(
            sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Delete a single cache entry.
    func delete(_ entry: SentenceCache) {
        context.delete(entry)
    }

    /// Flush all cache entries (admin "clear all").
    func flushAll() {
        let entries = allEntries()
        for entry in entries {
            context.delete(entry)
        }
    }

    // MARK: - Content-safety purge (unconditional)

    /// Purge every cached sentence whose tile combination INCLUDES `tileKey`.
    /// Unlike eviction (`evictStale`/`pruneStaleVersions`), this is UNCONDITIONAL:
    /// it deletes even pinned + caregiver-curated entries. A word pulled for
    /// content-safety (a disallowed term) must stop being spoken regardless of how
    /// it was cached. Uses per-object deletes, so removals propagate through
    /// CloudKit to the child's other devices — the opposite of the local-only
    /// `BootstrapLoader.wipeAllData`. Returns the number deleted.
    ///
    /// This is the companion to `TileModel.isRetired`: retiring a word for safety
    /// wires through here so a later un-retire can't resurrect a stale sentence.
    @discardableResult
    func invalidate(containingTileKey tileKey: String) -> Int {
        let doomed = allEntries().filter { $0.tileKeys.contains(tileKey) }
        for entry in doomed { context.delete(entry) }
        Self.logger.info("""
        invalidate(containingTileKey): key=\(tileKey, privacy: .public) \
        removed=\(doomed.count, privacy: .public)
        """)
        return doomed.count
    }

    /// Purge every cached sentence that used a tile of `wordClass`. The class is
    /// folded into the cache key as `key:class` pairs (see `CacheKeyPolicy`), so we
    /// match on that. Same unconditional semantics as
    /// `invalidate(containingTileKey:)` — deletes pinned/curated entries too, and
    /// propagates through CloudKit. Used when a whole class is retired or a
    /// reclassification should stop serving old-meaning sentences. Returns the
    /// number deleted.
    @discardableResult
    func invalidate(wordClass: String) -> Int {
        let doomed = allEntries().filter { entry in
            Self.classes(in: entry.cacheKey).contains(wordClass)
        }
        for entry in doomed { context.delete(entry) }
        Self.logger.info("""
        invalidate(wordClass): class=\(wordClass, privacy: .public) \
        removed=\(doomed.count, privacy: .public)
        """)
        return doomed.count
    }

    /// Extract the set of word classes encoded in a cache key. Key shape:
    /// `<model>/v<n>/g<grade>#key1:class1,key2:class2` — we take the segment after
    /// `#`, split on `,`, and read the class after each pair's last `:`.
    nonisolated static func classes(in cacheKey: String) -> Set<String> {
        guard let hash = cacheKey.firstIndex(of: "#") else { return [] }
        let pairs = cacheKey[cacheKey.index(after: hash)...]
        var result = Set<String>()
        for pair in pairs.split(separator: ",") {
            if let colon = pair.lastIndex(of: ":") {
                result.insert(String(pair[pair.index(after: colon)...]))
            }
        }
        return result
    }

    /// Launch-time sweep. Deletes unpinned entries that are stale (a mismatched
    /// `keyVersion` from a model/prompt-version change) or expired (unused for
    /// longer than `maxAge`), then LRU-evicts any unpinned overflow above
    /// `maxCount`. Pinned entries are always exempt and never counted. Returns
    /// the number deleted. `now` is injected for testability.
    @discardableResult
    func evictStale(now: Date = .now,
                    maxAge: TimeInterval = CacheKeyPolicy.maxAge,
                    maxCount: Int = CacheKeyPolicy.maxCount) -> Int {
        let entries = allEntries()   // sorted by lastUsed, most-recent first
        let currentVersion = CacheKeyPolicy.versionToken
        var versionStale = 0, expired = 0, overCap = 0, pinned = 0

        var survivors: [SentenceCache] = []
        for entry in entries {
            if entry.isPinned {
                pinned += 1
                continue   // pinned: exempt, and not counted toward maxCount
            }
            if entry.keyVersion != currentVersion {
                context.delete(entry)
                versionStale += 1
            } else if now.timeIntervalSince(entry.lastUsed) > maxAge {
                context.delete(entry)
                expired += 1
            } else {
                survivors.append(entry)
            }
        }

        // Count cap: survivors are already newest-first; drop the LRU overflow.
        if survivors.count > maxCount {
            for entry in survivors[maxCount...] {
                context.delete(entry)
                overCap += 1
            }
        }

        let deleted = versionStale + expired + overCap
        Self.logger.info("""
        evictStale: scanned=\(entries.count, privacy: .public) \
        removed=\(deleted, privacy: .public) \
        (versionStale=\(versionStale, privacy: .public) \
        expired=\(expired, privacy: .public) \
        overCap=\(overCap, privacy: .public)) \
        pinnedKept=\(pinned, privacy: .public) \
        survivors=\(survivors.count - overCap, privacy: .public) \
        version=\(currentVersion, privacy: .public)
        """)
        return deleted
    }

    /// On-demand, TTL-independent stale sweep (admin "clear stale"). Deletes
    /// unpinned entries whose `keyVersion` no longer matches the current
    /// `CacheKeyPolicy` — the reclaim path after a cache-invalidating prompt
    /// change, without waiting for a relaunch or the TTL. Returns the count.
    @discardableResult
    func pruneStaleVersions() -> Int {
        let currentVersion = CacheKeyPolicy.versionToken
        let stale = allEntries().filter { !$0.isPinned && $0.keyVersion != currentVersion }
        for entry in stale {
            context.delete(entry)
        }
        Self.logger.info("""
        pruneStaleVersions: removed=\(stale.count, privacy: .public) \
        version=\(currentVersion, privacy: .public)
        """)
        return stale.count
    }

    /// Fetch promoted entries: hitCount >= threshold or pinned, sorted by hitCount desc.
    func fetchPromoted(threshold: Int = 3, limit: Int = 8) -> [SentenceCache] {
        let entries = allEntries()
        let promoted = entries.filter { $0.hitCount >= threshold || $0.isPinned }
        return Array(promoted.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.hitCount > $1.hitCount
        }.prefix(limit))
    }

    /// Log a MetricEvent.
    func logEvent(subjectType: String, subjectKey: String, eventType: MetricType) {
        let event = MetricEvent(subjectType: subjectType, subjectKey: subjectKey, eventType: eventType)
        context.insert(event)
    }

    /// Persist a finalized utterance for therapist review. Captures the active scene name
    /// at commit time so logs remain meaningful after scene edits. `childID` is stamped
    /// for per-child review filtering.
    func logUtterance(tiles: [TileSelection], sentence: String,
                      repetitionCount: Int, childID: String? = nil) {
        let sceneName = activeSceneName()
        let entry = LoggedUtterance(
            tileKeys: tiles.map(\.key),
            sentence: sentence,
            repetitionCount: repetitionCount,
            sceneName: sceneName,
            childID: childID
        )
        context.insert(entry)
    }

    private func activeSceneName() -> String? {
        var descriptor = FetchDescriptor<BlasterScene>(
            predicate: #Predicate { $0.isActive == true }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.name
    }
}
