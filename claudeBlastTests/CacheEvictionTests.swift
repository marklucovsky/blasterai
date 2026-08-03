// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CacheEvictionTests.swift
//  claudeBlastTests
//
//  A3: versioned + grade-aware cache key, TTL/eviction, on-demand stale sweep.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CacheEvictionTests {

    private func makeTestContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    private func tiles(_ keys: String...) -> [TileSelection] {
        keys.map { TileSelection(key: $0, value: $0, wordClass: "actions") }
    }

    // MARK: - Key composition

    @Test func keyFoldsInModelPromptGradeAndClass() {
        let key = CacheKeyPolicy.key(for: tiles("eat", "pizza"), grade: 3)
        // <model>/v<promptVersion>/g<grade>#<sorted key:class pairs>
        #expect(key == "\(CacheKeyPolicy.versionToken)/g3#eat:actions,pizza:actions")
        #expect(key.hasPrefix(CacheKeyPolicy.versionToken))
    }

    @Test func keyIsOrderIndependentButGradeAndClassSensitive() {
        let a = CacheKeyPolicy.key(for: tiles("pizza", "eat"), grade: 2)
        let b = CacheKeyPolicy.key(for: tiles("eat", "pizza"), grade: 2)
        let g = CacheKeyPolicy.key(for: tiles("eat", "pizza"), grade: 5)
        // Same keys, different word class → different cache key (reclassification invalidates).
        let c = CacheKeyPolicy.key(for: [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "object"),
        ], grade: 2)
        #expect(a == b)       // order doesn't matter
        #expect(a != g)       // grade does
        #expect(a != c)       // word class does
    }

    @Test func differentGradesGetSeparateEntries() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let t = tiles("eat", "pizza")

        cache.store(tiles: t, grade: 2, sentence: "I want pizza.")
        cache.store(tiles: t, grade: 5, sentence: "I would like some pizza, please.")

        #expect(cache.allEntries().count == 2)
        #expect(cache.lookup(tiles: t, grade: 2)?.sentence == "I want pizza.")
        #expect(cache.lookup(tiles: t, grade: 5)?.sentence == "I would like some pizza, please.")
    }

    @Test func storeStampsCurrentKeyVersion() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        cache.store(tiles: tiles("eat"), grade: 2, sentence: "Eat.")
        #expect(cache.allEntries().first?.keyVersion == CacheKeyPolicy.versionToken)
    }

    // MARK: - evictStale

    /// Build an entry with controlled staleness fields and insert it.
    @discardableResult
    private func insert(_ ctx: ModelContext, tileKey: String, grade: Int = 2,
                        version: String? = nil, lastUsed: Date = .now,
                        pinned: Bool = false) -> SentenceCache {
        let e = SentenceCache(tiles: tiles(tileKey), grade: grade, sentence: tileKey)
        e.keyVersion = version ?? CacheKeyPolicy.versionToken
        e.lastUsed = lastUsed
        e.isPinned = pinned
        ctx.insert(e)
        return e
    }

    @Test func evictStaleRemovesExpiredAndVersionMismatch() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)
        let now = Date()

        insert(ctx, tileKey: "fresh", lastUsed: now)                                  // keep
        insert(ctx, tileKey: "expired", lastUsed: now.addingTimeInterval(-200 * 86_400)) // drop (age)
        insert(ctx, tileKey: "stale", version: "gpt-old/v0", lastUsed: now)           // drop (version)

        let deleted = cache.evictStale(now: now)
        #expect(deleted == 2)
        #expect(cache.allEntries().count == 1)
        #expect(cache.allEntries().first?.tileKeys == ["fresh"])
    }

    @Test func evictStaleExemptsPinned() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)
        let now = Date()

        // Pinned but both expired AND version-mismatched — must still survive.
        insert(ctx, tileKey: "pinned", version: "gpt-old/v0",
               lastUsed: now.addingTimeInterval(-500 * 86_400), pinned: true)

        let deleted = cache.evictStale(now: now)
        #expect(deleted == 0)
        #expect(cache.allEntries().count == 1)
    }

    @Test func evictStaleEnforcesMaxCountLRU() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)
        let now = Date()

        // 5 current, non-expired entries with increasing recency.
        for i in 0..<5 {
            insert(ctx, tileKey: "t\(i)", lastUsed: now.addingTimeInterval(TimeInterval(-i * 60)))
        }
        // A pinned, old entry that must never count against or fall to the cap.
        insert(ctx, tileKey: "pinned", lastUsed: now.addingTimeInterval(-9_999), pinned: true)

        let deleted = cache.evictStale(now: now, maxCount: 2)
        // 5 unpinned → keep 2 most-recent (t0, t1), drop 3. Pinned untouched.
        #expect(deleted == 3)
        let survivors = Set(cache.allEntries().map { $0.tileKeys.first! })
        #expect(survivors == ["t0", "t1", "pinned"])
    }

    // MARK: - pruneStaleVersions (on-demand)

    @Test func pruneStaleVersionsRemovesOnlyMismatchedUnpinned() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)
        let now = Date()

        insert(ctx, tileKey: "current", lastUsed: now)                        // keep (current)
        insert(ctx, tileKey: "stale", version: "gpt-old/v0", lastUsed: now)   // drop
        insert(ctx, tileKey: "stalePinned", version: "gpt-old/v0",
               lastUsed: now, pinned: true)                                   // keep (pinned)

        let removed = cache.pruneStaleVersions()
        #expect(removed == 1)
        let survivors = Set(cache.allEntries().map { $0.tileKeys.first! })
        #expect(survivors == ["current", "stalePinned"])
    }

    // MARK: - Escalation invariant

    @Test func escalationRecordHitCountsWithoutOverwriting() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let t = tiles("go", "home")

        cache.store(tiles: t, grade: 2, sentence: "I want to go home.")
        // Escalation path in the engine bypasses store and only records a hit.
        cache.recordHit(tiles: t, grade: 2)
        cache.recordHit(tiles: t, grade: 2)

        let entry = cache.lookup(tiles: t, grade: 2)
        #expect(cache.allEntries().count == 1)                 // no escalated variant stored
        #expect(entry?.sentence == "I want to go home.")       // base sentence unchanged
        #expect(entry?.hitCount == 3)                          // 2 recordHits + 1 lookup
    }

    // MARK: - Content-safety purge (unconditional invalidate)

    private func classed(_ pairs: (String, String)...) -> [TileSelection] {
        pairs.map { TileSelection(key: $0.0, value: $0.0, wordClass: $0.1) }
    }

    @Test func classesParsesPairsFromCacheKey() {
        let key = CacheKeyPolicy.key(for: classed(("carrot", "food"), ("pony", "animal")), grade: 3)
        #expect(SentenceCacheManager.classes(in: key) == ["food", "animal"])
        #expect(SentenceCacheManager.classes(in: "no-hash-here").isEmpty)
    }

    @Test func invalidateByTileKeyPurgesEvenPinned() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)

        cache.store(tiles: classed(("carrot", "food")), grade: 2, sentence: "I want a carrot.")
        cache.store(tiles: classed(("carrot", "food"), ("eat", "actions")), grade: 2, sentence: "Eat the carrot.")
        cache.store(tiles: classed(("apple", "food")), grade: 2, sentence: "I want an apple.")
        // Even a pinned/curated entry must be purged for a content-safety pull.
        cache.allEntries().forEach { $0.isPinned = true }

        let removed = cache.invalidate(containingTileKey: "carrot")
        #expect(removed == 2)
        let survivors = Set(cache.allEntries().flatMap { $0.tileKeys })
        #expect(!survivors.contains("carrot"))
        #expect(survivors.contains("apple"))
    }

    @Test func invalidateByWordClassPurgesMatching() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let cache = SentenceCacheManager(modelContext: ctx)

        cache.store(tiles: classed(("carrot", "food")), grade: 2, sentence: "I want a carrot.")
        cache.store(tiles: classed(("pony", "animal")), grade: 2, sentence: "Look, a pony.")
        cache.store(tiles: classed(("run", "actions"), ("pony", "animal")), grade: 2, sentence: "The pony runs.")

        let removed = cache.invalidate(wordClass: "animal")
        #expect(removed == 2)                                   // both entries touching an animal tile
        #expect(cache.allEntries().count == 1)
        #expect(cache.allEntries().first?.tileKeys == ["carrot"])
    }
}
}
