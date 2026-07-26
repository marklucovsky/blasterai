// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BootstrapLoader.swift
//  claudeBlast
//

import SwiftData
import Foundation
import CryptoKit

enum BootstrapLoader {
    struct LoadResult {
        let tiles: [TileModel]
        let pages: [PageSpec]
        let scene: BlasterScene
        let duration: TimeInterval
    }

    /// Bundled-content fingerprint: SHA256 of vocabulary.json + every
    /// scenes/*.json in the bundle. Recomputed on each call; cheap (few hundred
    /// KB of input). Used to detect content drift in DEBUG builds.
    static var bundledContentHash: String {
        var hasher = SHA256()
        let names: [(String, String)] = [
            ("vocabulary", "json"),
            ("core_first", "json"),
        ]
        for (name, ext) in names {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Decide whether bootstrap should run. Two modes:
    ///
    /// - **RELEASE**: bootstrap fires only on first install. The
    ///   bootstrapInstalled flag is set once and never re-checked. App updates
    ///   that change bundled JSON files do NOT auto-replace the user's
    ///   scene/vocab. This protects children in the wild — they keep their
    ///   muscle-memory layout across app updates.
    ///
    /// - **DEBUG**: bootstrap fires whenever the bundled content hash changes,
    ///   so developers editing scenes/*.json see updates on next launch.
    ///
    /// Both modes still respect AdminView's "Factory Reset" — that path resets
    /// both flags so the next launch performs a fresh bootstrap regardless.
    static func needsBootstrap() -> Bool {
        let defaults = UserDefaults.standard
        let installed = defaults.bool(forKey: AppSettingsKey.bootstrapInstalled)

        #if DEBUG
        // debug builds automatically re-bootstrap if hashes are not the same,
        // customer builds do not do this auto update, but do allow for manual download
        //
        // Migrate from the old integer-version scheme: if installed-flag is
        // unset but the legacy bootstrap_version key is set, we already
        // bootstrapped at least once. Migrate forward without an extra wipe.
        if !installed && defaults.integer(forKey: AppSettingsKey.bootstrapVersion) > 0 {
            defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
            // Don't store the hash here; let the next bootstrap or the next
            // hash check write it. We deliberately return true on this branch
            // so the developer sees up-to-date content.
            return true
        }
        if !installed { return true }
        let stored = defaults.string(forKey: AppSettingsKey.bootstrapContentHash) ?? ""
        return stored != bundledContentHash
        #else
        return !installed
        #endif
    }

    static func markBootstrapComplete() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        defaults.set(bundledContentHash, forKey: AppSettingsKey.bootstrapContentHash)
    }

    /// True when the synced store already holds bundled (system) vocabulary.
    /// Used to avoid seeding a second full copy on a device that has already
    /// received CloudKit data (the seed-once flag is local-only, so a fresh
    /// second device would otherwise re-seed). Best-effort — a device can still
    /// seed before its initial CloudKit import lands; CloudKitDedupReconciler is
    /// the guarantee that any resulting duplicates get collapsed.
    static func storeAlreadySeeded(context: ModelContext) -> Bool {
        var desc = FetchDescriptor<TileModel>(predicate: #Predicate { $0.isSystem })
        desc.fetchLimit = 1
        return ((try? context.fetch(desc))?.isEmpty == false)
    }

    /// One-time backfill of `TileModel.isSystem` for installs that predate the
    /// flag. Fresh bootstraps already set it; this only matters for RELEASE
    /// users who installed before the field existed (their bundled tiles read
    /// as `false`). Marks every stored tile whose key is in the current bundled
    /// vocabulary as system; caregiver-added / imported tiles (keys not in the
    /// bundle) keep `isSystem == false`. Idempotent and gated by a flag so it
    /// runs at most once. Cheap: one fetch + a Set-membership pass.
    static func backfillTileProvenance(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppSettingsKey.tileProvenanceBackfilled) else { return }

        defer { defaults.set(true, forKey: AppSettingsKey.tileProvenanceBackfilled) }

        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let codable = try? JSONDecoder().decode([TileModelCodable].self, from: data)
        else { return }

        let bundledKeys = Set(codable.map(\.key))
        guard let tiles = try? context.fetch(FetchDescriptor<TileModel>()) else { return }

        var changed = false
        for tile in tiles where !tile.isSystem && bundledKeys.contains(tile.key) {
            tile.isSystem = true
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Wipe all app-owned SwiftData records. Relationship-safe order matches
    /// performFactoryReset in AdminView. Safe to call on a fresh store (no-op).
    ///
    /// Intentionally uses batch `delete(model:)`: these deletions are LOCAL and
    /// are not mirrored to CloudKit. So a factory reset mimics a fresh install —
    /// it clears this device, preserves the user's cloud data, and on a synced
    /// device the records re-hydrate from iCloud. Do NOT switch to per-object
    /// deletes: that WOULD propagate to CloudKit and delete shared records on the
    /// user's other devices (e.g. a therapist's live patient iPad). Deleting a
    /// specific cloud record (e.g. a caregiver word) is a separate, explicit
    /// per-word delete action — not part of reset.
    static func wipeAllData(context: ModelContext) {
        do {
            try context.delete(model: MetricEvent.self)
            try context.delete(model: SentenceCache.self)
            try context.delete(model: BlasterScene.self)
            try context.delete(model: TileModel.self)
            try context.delete(model: ChildProfile.self)
            try context.delete(model: DeviceProfile.self)
            try context.save()
        } catch {
            print("BootstrapLoader.wipeAllData failed: \(error)")
        }
    }

    static func loadDefaultVocabulary(context: ModelContext) -> LoadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let emptyScene = BlasterScene(name: "Empty", isDefault: true, isActive: true)
        // First-party identity without a systemSceneKey (Empty is not bundle-backed,
        // so it must not gain the force-refresh affordance).
        emptyScene.slug = "empty"
        emptyScene.sceneID = SceneIdentity.id(authority: SceneIdentity.firstPartyAuthority, slug: "empty")
        emptyScene.sceneVersion = "1.0.0"
        emptyScene.importedContentHash = emptyScene.contentHash   // pristine baseline

        guard let vocabularyUrl = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            print("Failed to locate vocabulary.json in bundle.")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }

        do {
            // ----- vocabulary -----
            let tilesData = try Data(contentsOf: vocabularyUrl)
            let codableTiles = try JSONDecoder().decode([TileModelCodable].self, from: tilesData)
            // Deduplicate by key at load time (CloudKit does not support @Attribute(.unique))
            var seenTileKeys = Set<String>()
            let allTiles: [TileModel] = codableTiles.compactMap { codable in
                guard seenTileKeys.insert(codable.key).inserted else { return nil }
                let tile = TileModel(from: codable)
                tile.isSystem = true
                return tile
            }
            let tileLookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

            // ----- Core-First scene from Resources/scenes/core_first.json -----
            // The hardcoded Swift scene specs (coreFirstHomeSpecs / foodDrinksSpecs)
            // are gone — the scene now lives in JSON, with DSL commands
            // (selectAll / selectKeys / makeLink / deleteTile) expanded by
            // SceneMaterializer against the vocabulary. The materialized
            // PageSpec list is then converted to PageModel/PageTileModel
            // instances for SwiftData storage; that conversion is a
            // transition step — Step K replaces the PageModel storage with
            // inline [PageSpec] on BlasterScene.
            // The Xcode synchronized group flattens Resources/scenes/*.json into
            // the bundle root, so no subdirectory: parameter. (We'll revisit
            // naming when more than one bundled scene file ships.)
            guard let coreSceneUrl = Bundle.main.url(
                forResource: "core_first", withExtension: "json"
            ) else {
                print("Failed to locate core_first.json in bundle.")
                return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
            }
            let coreSceneData = try Data(contentsOf: coreSceneUrl)
            let coreSceneJSON = try JSONDecoder().decode(SceneJSON.self, from: coreSceneData)
            let materialized = try SceneMaterializer.materialize(
                scene: coreSceneJSON, vocabulary: codableTiles
            )
            let coreFirstScene = buildScene(from: materialized)

            // ----- All Tiles scene (programmatic) -----
            // Single page with every vocab tile, grouped by wordClass in vocab
            // declaration order. Useful for review/admin; not a child-facing
            // scene. Programmatic rather than JSON because the content is just
            // "all of vocabulary" — no curation needed.
            var wcOrder: [String] = []
            var wcGroups: [String: [String]] = [:]
            for tile in allTiles {
                if wcGroups[tile.wordClass] == nil {
                    wcOrder.append(tile.wordClass)
                    wcGroups[tile.wordClass] = []
                }
                wcGroups[tile.wordClass]!.append(tile.key)
            }
            let allTilesEntries: [TileEntry] = wcOrder.flatMap { wc in
                (wcGroups[wc] ?? []).map { TileEntry(key: $0, link: "", isAudible: true) }
            }
            let allTilesPage = PageSpec(key: "all_tiles", tiles: allTilesEntries)
            let allTilesScene = BlasterScene(
                name: "All Tiles",
                descriptionText: "Full vocabulary grouped by word class",
                homePageKey: "all_tiles",
                isDefault: false,
                isActive: false
            )
            // Stable key so CloudKitDedupReconciler can collapse duplicate
            // All-Tiles scenes produced by multi-device bootstrap.
            allTilesScene.systemSceneKey = "all_tiles"
            allTilesScene.markFirstPartyIdentity()
            allTilesScene.pages = [allTilesPage]
            allTilesScene.importedContentHash = allTilesScene.contentHash   // pristine baseline

            // ----- persist -----
            // BlasterScene.pages is now an inline JSON-encoded attribute, so
            // there are no PageModel / PageTileModel children to insert
            // alongside each scene. Just the tiles + scenes.
            try context.transaction {
                for tile in allTiles { context.insert(tile) }
                context.insert(coreFirstScene)
                context.insert(allTilesScene)
                // Every page gets a page-link image tile, reusing the image its
                // existing category link already uses (no new art).
                let lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
                PageLink.ensurePageImages(in: coreFirstScene, context: context, existing: lookup)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(
                tiles: allTiles,
                pages: coreFirstScene.pages,
                scene: coreFirstScene,
                duration: elapsed
            )

        } catch {
            print("Failed to load or decode bootstrap data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }

    // MARK: - Materialized scene → BlasterScene

    /// Convert a SceneMaterializer.MaterializedScene into a BlasterScene whose
    /// `pages` array carries the materialized [PageSpec] directly. The "<home>"
    /// symbolic link is kept LITERAL — TileGridView resolves it to the active
    /// scene's homePageKey at navigation time (Step J), so a runtime change of
    /// homePageKey works without rebuilding pages.
    private static func buildScene(
        from materialized: SceneMaterializer.MaterializedScene
    ) -> BlasterScene {
        let scene = BlasterScene(
            name: materialized.name,
            descriptionText: materialized.description,
            homePageKey: materialized.homePageKey,
            isDefault: materialized.isDefault,
            isActive: materialized.isDefault
        )
        scene.systemSceneKey = materialized.key
        scene.markFirstPartyIdentity()
        scene.pages = materialized.pages
        scene.importedContentHash = scene.contentHash   // pristine baseline
        return scene
    }

    // MARK: - Force-refresh (caregiver-initiated bundle update)

    /// True when the bundled content differs from what was last applied. In
    /// RELEASE this is the only signal a caregiver gets that a newer Core-First
    /// layout shipped with an app update (auto-bootstrap is suppressed there).
    static func isBundleUpdateAvailable() -> Bool {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKey.bootstrapContentHash) ?? ""
        return stored != bundledContentHash
    }

    /// Re-materialize the bundled `core_first.json` and overwrite the existing
    /// system scene's content IN PLACE — same BlasterScene id, isActive, and
    /// isDefault preserved, so navigation and active-scene state aren't
    /// disrupted. Scoped strictly to the system Core-First scene; user-created
    /// and duplicated scenes (systemSceneKey == "") are never touched.
    ///
    /// Caregiver-initiated only (AdminView "Update Available"). After applying,
    /// the stored content hash is advanced so the affordance clears.
    @discardableResult
    static func updateSystemScene(context: ModelContext) -> Bool {
        guard let url = Bundle.main.url(forResource: "core_first", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sceneJSON = try? JSONDecoder().decode(SceneJSON.self, from: data),
              let vocabURL = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let vocabData = try? Data(contentsOf: vocabURL),
              let vocab = try? JSONDecoder().decode([TileModelCodable].self, from: vocabData),
              let materialized = try? SceneMaterializer.materialize(scene: sceneJSON, vocabulary: vocab)
        else {
            print("updateSystemScene: failed to load/materialize core_first.json")
            return false
        }

        do {
            let key = materialized.key
            let scenes = try context.fetch(
                FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.systemSceneKey == key })
            )
            guard let scene = scenes.first else {
                print("updateSystemScene: no scene with systemSceneKey '\(key)'")
                return false
            }
            // Overwrite content in place; preserve id / isActive / isDefault.
            scene.name = materialized.name
            scene.descriptionText = materialized.description
            scene.homePageKey = materialized.homePageKey
            scene.pages = materialized.pages
            try context.save()
            UserDefaults.standard.set(bundledContentHash, forKey: AppSettingsKey.bootstrapContentHash)
            return true
        } catch {
            print("updateSystemScene failed: \(error)")
            return false
        }
    }
}
