// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CloudKitDedupReconcilerTests.swift
//  claudeBlastTests
//
//  Exercises the reconciler through its public `reconcile(context:)` entry point
//  against an in-memory store seeded with CloudKit-style duplicates (same logical
//  key, distinct records/ids). Verifies deterministic winner election, per-model
//  collapse scope, the legacy All-Tiles normalize, single-active invariants, and
//  childID repointing. See docs/cloudkit-dedup.md.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CloudKitDedupReconcilerTests {

    /// Return the CONTAINER (not just its context): the caller must retain it for
    /// the test's duration, or the container deallocates and its mainContext dies.
    /// NB: TileArtVariant is intentionally omitted — its @Attribute(.externalStorage)
    /// isn't supported by an in-memory store. The reconciler fetches it via `try?`,
    /// so it no-ops when the model isn't registered.
    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    private func tile(_ key: String, id: String, isSystem: Bool = true,
                      image: Data = Data()) -> TileModel {
        let t = TileModel(key: key, wordClass: "actions")
        t.id = id
        t.isSystem = isSystem
        t.userImageData = image
        return t
    }

    private func scene(_ name: String, id: String, systemKey: String = "",
                       home: String = "home", active: Bool = false,
                       modified: Date = .init(timeIntervalSinceReferenceDate: 0)) -> BlasterScene {
        let s = BlasterScene(name: name, homePageKey: home, isDefault: false, isActive: active)
        s.id = id
        s.systemSceneKey = systemKey
        s.lastModified = modified
        return s
    }

    private func profile(_ name: String, id: String, isSystem: Bool,
                         active: Bool, modified: Date = .init(timeIntervalSinceReferenceDate: 0)) -> ChildProfile {
        let p = ChildProfile(displayName: name,
                             birthday: ChildProfile.synthesizeBirthday(age: 7),
                             voiceIdentifier: "", maxSelectedTiles: 4, isActive: active)
        p.id = id
        p.isSystem = isSystem
        p.modifiedAt = modified
        return p
    }

    // MARK: - Tiles

    @Test func tiles_duplicateKeysCollapseToLowestId() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ["c", "a", "b"].forEach { ctx.insert(tile("eat", id: $0)) }
        ctx.insert(tile("drink", id: "x"))   // singleton — untouched

        let deleted = CloudKitDedupReconciler.reconcile(context: ctx)

        #expect(deleted == 2)
        let eats = try ctx.fetch(FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == "eat" }))
        #expect(eats.count == 1)
        #expect(eats[0].id == "a")   // deterministic: lowest id survives
        #expect(try ctx.fetch(FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == "drink" })).count == 1)
    }

    @Test func tiles_preferCustomizedCopyOverLowestId() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(tile("eat", id: "a"))                        // bare, lower id
        ctx.insert(tile("eat", id: "z", image: Data([0x1])))    // customized, higher id

        CloudKitDedupReconciler.reconcile(context: ctx)

        let eats = try ctx.fetch(FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == "eat" }))
        #expect(eats.count == 1)
        #expect(eats[0].id == "z")            // customized copy wins despite higher id
        #expect(eats[0].hasUserImage)
    }

    // MARK: - Scenes

    @Test func systemScenes_collapseByKey_userScenesUntouched() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(scene("Core", id: "c1", systemKey: "core_first"))
        ctx.insert(scene("Core", id: "c2", systemKey: "core_first"))
        // Two user scenes with the SAME name but empty key must both survive.
        ctx.insert(scene("MyBoard", id: "u1", systemKey: ""))
        ctx.insert(scene("MyBoard", id: "u2", systemKey: ""))

        CloudKitDedupReconciler.reconcile(context: ctx)

        let core = try ctx.fetch(FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.systemSceneKey == "core_first" }))
        #expect(core.count == 1)
        let userScenes = try ctx.fetch(FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.systemSceneKey == "" }))
        #expect(userScenes.count == 2)   // never collapsed by name
    }

    @Test func legacyAllTiles_normalizedThenCollapsed_userNamedSurvives() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Legacy All-Tiles: right signature, empty key (bootstrapped pre-fix).
        ctx.insert(scene("All Tiles", id: "a1", systemKey: "", home: "all_tiles"))
        ctx.insert(scene("All Tiles", id: "a2", systemKey: "", home: "all_tiles"))
        ctx.insert(scene("All Tiles", id: "a3", systemKey: "", home: "all_tiles"))
        // A user scene coincidentally named "All Tiles" but NOT the signature.
        ctx.insert(scene("All Tiles", id: "u1", systemKey: "", home: "home"))

        CloudKitDedupReconciler.reconcile(context: ctx)

        let allTiles = try ctx.fetch(FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.systemSceneKey == "all_tiles" }))
        #expect(allTiles.count == 1)                 // 3 legacy → 1, key backfilled
        let named = try ctx.fetch(FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.name == "All Tiles" }))
        #expect(named.count == 2)                    // the collapsed all_tiles + the untouched user scene
        #expect(named.contains { $0.id == "u1" && $0.systemSceneKey == "" })
    }

    @Test func enforcesSingleActiveScene_keepsMostRecentlyModified() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(scene("A", id: "s1", systemKey: "k1", active: true,
                         modified: .init(timeIntervalSinceReferenceDate: 100)))
        ctx.insert(scene("B", id: "s2", systemKey: "k2", active: true,
                         modified: .init(timeIntervalSinceReferenceDate: 200)))

        CloudKitDedupReconciler.reconcile(context: ctx)

        let active = try ctx.fetch(FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.isActive }))
        #expect(active.count == 1)
        #expect(active[0].id == "s2")   // newer lastModified wins
    }

    // MARK: - Profiles

    @Test func sandbox_collapses_andRepointsChildID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(profile("Sandbox", id: "s1", isSystem: true, active: false))
        ctx.insert(profile("Sandbox", id: "s2", isSystem: true, active: false))
        let cache = SentenceCache(tiles: [TileSelection(key: "eat", value: "eat", wordClass: "actions")],
                                  grade: 2, sentence: "hi", childID: "s2")  // refs the loser
        ctx.insert(cache)

        CloudKitDedupReconciler.reconcile(context: ctx)

        let sandboxes = try ctx.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem }))
        #expect(sandboxes.count == 1)
        #expect(sandboxes[0].id == "s1")
        let caches = try ctx.fetch(FetchDescriptor<SentenceCache>())
        #expect(caches.count == 1)
        #expect(caches[0].childID == "s1")   // repointed from the deleted s2
    }

    @Test func enforcesSingleActiveProfile_realWinsAndMostRecent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(profile("Kid1", id: "p1", isSystem: false, active: true,
                           modified: .init(timeIntervalSinceReferenceDate: 100)))
        ctx.insert(profile("Kid2", id: "p2", isSystem: false, active: true,
                           modified: .init(timeIntervalSinceReferenceDate: 200)))

        CloudKitDedupReconciler.reconcile(context: ctx)

        let active = try ctx.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isActive }))
        #expect(active.count == 1)
        #expect(active[0].id == "p2")   // resolveActive: most-recent modifiedAt
    }

    @Test func legacySeed_collapses_userNamedProfileSurvives() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        func legacy(_ id: String, active: Bool) -> ChildProfile {
            let p = profile("Legacy", id: id, isSystem: false, active: active)
            p.notes = "Seeded from prior install at 2026-06-01T00:00:00Z"
            return p
        }
        ctx.insert(legacy("l1", active: false))
        ctx.insert(legacy("l2", active: true))   // active seed → survives
        ctx.insert(legacy("l3", active: false))
        // A profile the user adopted + renamed (no seed notes) must NOT be collapsed.
        let emma = profile("Emma", id: "emma", isSystem: false, active: false)
        emma.notes = ""
        ctx.insert(emma)

        CloudKitDedupReconciler.reconcile(context: ctx)

        let reals = try ctx.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { !$0.isSystem }))
        #expect(reals.count == 2)                                   // one Legacy + Emma
        let legacies = reals.filter { $0.displayName == "Legacy" }
        #expect(legacies.count == 1)
        #expect(legacies[0].id == "l2")                             // active seed survived
        #expect(reals.contains { $0.id == "emma" })                // renamed profile untouched
    }

    // MARK: - Cache

    @Test func sentenceCache_collapsesKeepingHighestHitCount() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let eatApple = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "apple", value: "apple", wordClass: "food"),
        ]
        let a = SentenceCache(tiles: eatApple, grade: 2, sentence: "one")
        a.hitCount = 2
        let b = SentenceCache(tiles: eatApple.reversed(), grade: 2, sentence: "two")  // same cacheKey (order-independent)
        b.hitCount = 9
        ctx.insert(a); ctx.insert(b)

        CloudKitDedupReconciler.reconcile(context: ctx)

        let caches = try ctx.fetch(FetchDescriptor<SentenceCache>())
        #expect(caches.count == 1)
        #expect(caches[0].hitCount == 9)   // most-used survives
    }

    // MARK: - Invariants

    @Test func cleanStore_isNoOp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(tile("eat", id: "a"))
        ctx.insert(scene("Core", id: "c1", systemKey: "core_first", active: true))
        ctx.insert(profile("Sandbox", id: "s1", isSystem: true, active: true))

        let deleted = CloudKitDedupReconciler.reconcile(context: ctx)

        #expect(deleted == 0)
        #expect(try ctx.fetch(FetchDescriptor<TileModel>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<BlasterScene>()).count == 1)
    }

    @Test func idempotent_secondRunDeletesNothing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ["a", "b", "c"].forEach { ctx.insert(tile("eat", id: $0)) }
        ctx.insert(scene("Core", id: "c1", systemKey: "core_first"))
        ctx.insert(scene("Core", id: "c2", systemKey: "core_first"))

        let first = CloudKitDedupReconciler.reconcile(context: ctx)
        let second = CloudKitDedupReconciler.reconcile(context: ctx)

        #expect(first == 3)    // 2 tile dupes + 1 scene dupe
        #expect(second == 0)   // already converged
    }
}
}
