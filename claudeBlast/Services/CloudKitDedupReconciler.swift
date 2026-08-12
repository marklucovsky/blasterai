// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CloudKitDedupReconciler.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Collapses duplicate synced records to a single deterministic winner and
/// enforces single-active invariants.
///
/// ## Why this exists
/// There is no `@Attribute(.unique)` under CloudKit, and `BootstrapLoader`
/// seeds the full vocabulary + system scenes + Sandbox profile keyed on a
/// *local* `UserDefaults` flag. So every fresh device seeds its own copy, and
/// when two devices sync, SwiftData assigns each record its own identifier —
/// producing genuine duplicates of every logical key (two "actions" tiles, two
/// "Core-First" scenes, two Sandboxes). See `docs/cloudkit-dedup.md`.
///
/// ## Determinism & convergence
/// Every model carries a stored `id: String` (a UUID that syncs), so duplicates
/// of one logical key have *different* ids that are *identical across devices*.
/// Picking the lowest-`id` (with semantic preferences first) means every device
/// independently elects the SAME winner and deletes the SAME losers. Deletes
/// here are per-object and DO propagate to CloudKit (we want the duplicate gone
/// everywhere) — the opposite of `BootstrapLoader.wipeAllData`'s local-only wipe.
/// Idempotent and safe on a clean store; safe to run repeatedly.
enum CloudKitDedupReconciler {

    /// Run the full reconciliation pass. Returns the number of records deleted
    /// (for logging). Call at launch and on CloudKit remote-change events.
    /// Not actor-isolated so it can run from `App.init` (main thread) as well as
    /// from the main-actor `CloudKitSyncCoordinator`; always call on the main
    /// thread against `container.mainContext`.
    @discardableResult
    static func reconcile(context: ModelContext) -> Int {
        var deleted = 0
        var changed = false

        deleted += dedupeTiles(context)
        deleted += dedupeSystemScenes(context)
        deleted += dedupeSandbox(context)
        deleted += dedupeLegacySeedProfiles(context)
        deleted += dedupeArtVariants(context)
        deleted += dedupeSentenceCache(context)

        changed = enforceSingleActiveScene(context) || changed
        changed = enforceSingleActiveProfile(context) || changed

        if deleted > 0 || changed {
            do { try context.save() }
            catch { print("CloudKitDedupReconciler save failed: \(error)") }
            #if DEBUG
            if deleted > 0 { print("CloudKitDedupReconciler: collapsed \(deleted) duplicate record(s)") }
            #endif
        }
        recordTelemetry(deleted: deleted)
        return deleted
    }

    /// Persist a small per-device record of reconciliation activity for the
    /// About & Stats screen. Local-only (UserDefaults) — deliberately not a
    /// synced model, to avoid schema churn during the pre-Production window.
    private static func recordTelemetry(deleted: Int) {
        let d = UserDefaults.standard
        d.set(deleted, forKey: AppSettingsKey.reconcileLastDeleted)
        d.set(d.integer(forKey: AppSettingsKey.reconcileLifetimeDeleted) + deleted,
              forKey: AppSettingsKey.reconcileLifetimeDeleted)
        d.set(Date.now.timeIntervalSinceReferenceDate, forKey: AppSettingsKey.reconcileLastDate)
    }

    // MARK: - Generic collapse

    /// Group `records` by `keyOf`, elect a winner per group via `betterThan`
    /// (a total order — winner sorts first), delete every loser. Returns the
    /// winners map (for reference repointing) and the deleted records.
    private static func collapse<M: PersistentModel>(
        _ records: [M],
        context: ModelContext,
        keyOf: (M) -> String?,
        betterThan: (M, M) -> Bool
    ) -> (winners: [String: M], deleted: [M]) {
        var groups: [String: [M]] = [:]
        for r in records {
            guard let k = keyOf(r) else { continue }
            groups[k, default: []].append(r)
        }
        var winners: [String: M] = [:]
        var deleted: [M] = []
        for (k, group) in groups {
            guard let winner = group.sorted(by: betterThan).first else { continue }
            winners[k] = winner
            guard group.count > 1 else { continue }
            for loser in group where loser.persistentModelID != winner.persistentModelID {
                context.delete(loser)
                deleted.append(loser)
            }
        }
        return (winners, deleted)
    }

    // MARK: - Per-model dedup

    /// Collapse duplicate tiles by `key`. Prefer a caregiver-customized copy
    /// (has `userImageData`) so a photo added on one device isn't dropped in
    /// favor of a bare bundled dup; then lowest `id` for determinism.
    private static func dedupeTiles(_ context: ModelContext) -> Int {
        guard let tiles = try? context.fetch(FetchDescriptor<TileModel>()) else { return 0 }
        return collapse(tiles, context: context,
                        keyOf: { $0.key.isEmpty ? nil : $0.key }) { a, b in
            if a.hasUserImage != b.hasUserImage {
                return a.hasUserImage
            }
            return a.id < b.id
        }.deleted.count
    }

    /// Collapse duplicate SYSTEM scenes by `systemSceneKey`. User/imported/
    /// duplicated scenes have an empty key and are never touched. Preserve the
    /// active/most-recently-edited copy.
    private static func dedupeSystemScenes(_ context: ModelContext) -> Int {
        guard let scenes = try? context.fetch(FetchDescriptor<BlasterScene>()) else { return 0 }
        return collapse(scenes, context: context,
                        keyOf: { $0.systemSceneKey.isEmpty ? nil : $0.systemSceneKey }) { a, b in
            if a.isActive != b.isActive { return a.isActive }
            if a.lastModified != b.lastModified { return a.lastModified > b.lastModified }
            return a.id < b.id
        }.deleted.count
    }

    /// Collapse duplicate Sandbox (`isSystem`) profiles to one, and repoint any
    /// `childID` references from the deleted Sandboxes to the survivor so cached
    /// sentences / logs don't orphan. Real (non-system) profiles are never
    /// deleted here — the single-active invariant handles their races instead.
    private static func dedupeSandbox(_ context: ModelContext) -> Int {
        guard let sandboxes = try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
        ), sandboxes.count > 1 else { return 0 }

        let result = collapse(sandboxes, context: context, keyOf: { _ in "sandbox" }) { a, b in
            if a.isActive != b.isActive { return a.isActive }
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
            return a.id < b.id
        }
        if let winner = result.winners["sandbox"], !result.deleted.isEmpty {
            let deadIDs = Set(result.deleted.map { $0.id })
            repointChildID(context, from: deadIDs, to: winner.id)
        }
        return result.deleted.count
    }

    /// Collapse the migration-seeded **"Legacy"** profile. Like the Sandbox, it's
    /// re-seeded per device by `ProfileMigration` (returning-user path), so it
    /// duplicates under CloudKit — but it's `isSystem == false`, so the sandbox
    /// pass doesn't catch it. Match ONLY the untouched seed by its exact signature
    /// (name "Legacy" + the seed `notes` prefix); a user who renamed or edited it
    /// no longer matches and is never deleted. Keeps the active/most-recent copy
    /// and repoints childID references to it.
    private static func dedupeLegacySeedProfiles(_ context: ModelContext) -> Int {
        guard let profiles = try? context.fetch(FetchDescriptor<ChildProfile>()) else { return 0 }
        let seeds = profiles.filter {
            !$0.isSystem && $0.displayName == "Legacy"
                && $0.notes.hasPrefix("Seeded from prior install")
        }
        guard seeds.count > 1 else { return 0 }
        let result = collapse(seeds, context: context, keyOf: { _ in "legacy-seed" }) { a, b in
            if a.isActive != b.isActive { return a.isActive }
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
            return a.id < b.id
        }
        if let winner = result.winners["legacy-seed"], !result.deleted.isEmpty {
            repointChildID(context, from: Set(result.deleted.map { $0.id }), to: winner.id)
        }
        return result.deleted.count
    }

    /// Collapse duplicate art variants by (tileKey, imageSet). Keep the freshest.
    private static func dedupeArtVariants(_ context: ModelContext) -> Int {
        guard let variants = try? context.fetch(FetchDescriptor<TileArtVariant>()) else { return 0 }
        return collapse(variants, context: context,
                        keyOf: { "\($0.tileKey)\u{1}\($0.imageSetRaw)" }) { a, b in
            if a.modified != b.modified { return a.modified > b.modified }
            return String(describing: a.persistentModelID) < String(describing: b.persistentModelID)
        }.deleted.count
    }

    /// Collapse duplicate cache entries by (cacheKey, childID). Keep the most-used.
    private static func dedupeSentenceCache(_ context: ModelContext) -> Int {
        guard let caches = try? context.fetch(FetchDescriptor<SentenceCache>()) else { return 0 }
        return collapse(caches, context: context,
                        keyOf: { "\($0.cacheKey)\u{1}\($0.childID)" }) { a, b in
            if a.hitCount != b.hitCount { return a.hitCount > b.hitCount }
            if a.created != b.created { return a.created > b.created }
            return a.id < b.id
        }.deleted.count
    }

    // MARK: - Single-active invariants

    /// Ensure at most one active scene. Keep the most-recently-modified active
    /// scene, but a USER scene always beats a SYSTEM one first. Mirrors
    /// `enforceSingleActiveProfile`, where a real profile beats the Sandbox:
    /// category before timestamp.
    ///
    /// Why the category test has to come first: a freshly-installed device
    /// bootstraps the system scene and marks it active, so its `lastModified` is
    /// necessarily newer than the user's board, which was chosen earlier. On a
    /// pure most-recently-modified rule, adding a second device would silently
    /// switch the family back to the built-in board — the same "a fresh bootstrap
    /// always looks newer than real work" flaw that was destroying scene edits.
    /// Timestamps are only comparable between peers of the same kind.
    private static func enforceSingleActiveScene(_ context: ModelContext) -> Bool {
        guard let active = try? context.fetch(
            FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.isActive })
        ), active.count > 1 else { return false }
        let winner = active.sorted {
            if $0.isSystemOwned != $1.isSystemOwned { return !$0.isSystemOwned }
            if $0.lastModified != $1.lastModified { return $0.lastModified > $1.lastModified }
            return $0.id < $1.id
        }.first
        var changed = false
        for scene in active where scene.persistentModelID != winner?.persistentModelID {
            scene.isActive = false
            changed = true
        }
        return changed
    }

    /// Ensure exactly one active profile: a real active profile (resolved via
    /// the existing CloudKit-race tiebreaker) wins over the Sandbox; the Sandbox
    /// is the fallback. Everything else is deactivated.
    private static func enforceSingleActiveProfile(_ context: ModelContext) -> Bool {
        guard let all = try? context.fetch(FetchDescriptor<ChildProfile>()) else { return false }
        let realActive = all.filter { $0.isActive && !$0.isSystem }
        let winner = ChildProfile.resolveActive(from: realActive)
            ?? all.first(where: { $0.isSystem && $0.isActive })
            ?? all.first(where: { $0.isSystem })
        guard let winner else { return false }

        var changed = false
        if !winner.isActive {
            winner.isActive = true
            winner.modifiedAt = .now
            changed = true
        }
        for p in all where p.persistentModelID != winner.persistentModelID && p.isActive {
            p.isActive = false
            p.modifiedAt = .now
            changed = true
        }
        return changed
    }

    // MARK: - Helpers

    private static func repointChildID(_ context: ModelContext, from dead: Set<String>, to newID: String) {
        if let caches = try? context.fetch(FetchDescriptor<SentenceCache>()) {
            for c in caches where dead.contains(c.childID) { c.childID = newID }
        }
        if let logs = try? context.fetch(FetchDescriptor<LoggedUtterance>()) {
            for l in logs where dead.contains(l.childID) { l.childID = newID }
        }
    }
}
