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

    /// Bootstrap fires **only on first install**, in every configuration.
    ///
    /// A child's board is muscle memory. An app update must not rearrange it,
    /// so bundled JSON changes never wipe and re-seed; they arrive through
    /// `updateSystemScene`, which rewrites the immutable system board in place
    /// and inserts any new bundled words alongside it.
    ///
    /// ## Why DEBUG no longer differs
    ///
    /// DEBUG used to re-bootstrap whenever the bundled content hash changed, so
    /// a developer editing `scenes/*.json` saw it on next launch. That was
    /// convenient and it cost us: DEBUG exercised a launch path that no shipped
    /// build ever runs, which is how two real bugs stayed hidden —
    ///
    /// - the seeded-store branch stamping a content hash it had not applied,
    ///   swallowing the update it was about to trigger; and
    /// - `updateSystemScene` never inserting new bundled vocabulary, so a board
    ///   referencing a new word rendered a hole.
    ///
    /// Both only bit an *existing* install, which in DEBUG the wipe kept papering
    /// over. Running the shipping path in development is worth more than the
    /// convenience, especially with a pilot in sight.
    ///
    /// To reseed from the bundle deliberately, use AdminView's **Factory Reset**,
    /// which clears both flags so the next launch bootstraps fresh.
    static func needsBootstrap() -> Bool {
        let defaults = UserDefaults.standard
        let installed = defaults.bool(forKey: AppSettingsKey.bootstrapInstalled)

        // Migrate from the old integer-version scheme: an install that predates
        // the flag but has a legacy bootstrap_version has already been seeded.
        // Move it forward rather than wiping a board someone is using.
        if !installed && defaults.integer(forKey: AppSettingsKey.bootstrapVersion) > 0 {
            defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
            return false
        }
        return !installed
    }

    /// `needsBootstrap`, plus a check that the flag is telling the truth.
    ///
    /// The flag lives in UserDefaults and the data it describes lives in the
    /// store. They commit separately, so a process that dies between the two
    /// leaves a device claiming to be seeded with nothing in it — no scenes, no
    /// board, and no route to make one. Believing the flag over the store means
    /// that state is permanent.
    ///
    /// **Only when iCloud is off.** With sync on, an empty store is the ordinary
    /// condition of a second device whose initial import has not landed yet, and
    /// re-seeding there would mint a duplicate copy of a dataset already on its
    /// way — the case `storeAlreadySeeded` exists to avoid. Sync off removes that
    /// ambiguity: nothing is coming, so empty means lost.
    ///
    /// Zero scenes rather than zero tiles: the default scene is system-owned and
    /// cannot be deleted, so having none is never something a caregiver did.
    static func needsBootstrap(context: ModelContext) -> Bool {
        if needsBootstrap() { return true }
        guard !UserDefaults.standard.bool(forKey: AppSettingsKey.icloudEnabled) else {
            return false
        }
        var descriptor = FetchDescriptor<BlasterScene>()
        descriptor.fetchLimit = 1
        let sceneCount = (try? context.fetchCount(descriptor)) ?? 1
        if sceneCount == 0 {
            print("bootstrap: flagged as seeded but the store has no scenes — re-seeding")
            return true
        }
        return false
    }

    /// Record that this device has been seeded.
    ///
    /// - Parameter appliedBundledContent: whether bundled JSON was actually
    ///   loaded. Stamping the content hash is a claim that *this device now
    ///   holds this bundle's content* — so a caller that skipped seeding must
    ///   pass `false`, or the stamp lies.
    ///
    ///   That lie had teeth: the `storeAlreadySeeded` branch skips seeding and
    ///   used to stamp anyway, which left `isBundleUpdateAvailable()` false and
    ///   silently swallowed the very board update the launch sequence runs next.
    ///   In DEBUG the symptom was that edits to `core_first.json` never appeared
    ///   until the app was deleted and reinstalled.
    static func markBootstrapComplete(appliedBundledContent: Bool = true) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        if appliedBundledContent {
            defaults.set(bundledContentHash, forKey: AppSettingsKey.bootstrapContentHash)
        }
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

            // NB: the "All Tiles (Review)" scene was removed — a flat 492-tile
            // board was the old way to review the vocabulary, and VocabManagerView
            // (Scenes tab → Manage Vocabulary) does that job properly now with
            // search, class filter, scope, and hide/restore. It was also a second
            // system scene to keep pristine for no benefit.

            // ----- persist -----
            // BlasterScene.pages is now an inline JSON-encoded attribute, so
            // there are no PageModel / PageTileModel children to insert
            // alongside each scene. Just the tiles + scenes.
            try context.transaction {
                for tile in allTiles { context.insert(tile) }
                context.insert(coreFirstScene)
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

    // MARK: - System-scene refresh (automatic, on app update)

    /// True when the bundled content differs from what was last applied — i.e. an
    /// app update shipped a newer Core-First layout. Checked at launch, since
    /// auto-bootstrap is suppressed in RELEASE once installed.
    static func isBundleUpdateAvailable() -> Bool {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKey.bootstrapContentHash) ?? ""
        return stored != bundledContentHash
    }

    /// Bring an existing install up to the current bundle: insert any new
    /// bundled vocabulary, then re-materialize `core_first.json` and overwrite
    /// the system scene's content IN PLACE — same BlasterScene id, isActive, and
    /// isDefault preserved, so navigation and active-scene state aren't
    /// disrupted. Scoped strictly to the system Core-First scene; user-created
    /// and duplicated scenes (systemSceneKey == "") are never touched.
    ///
    /// Applied automatically at launch. Safe to do silently because system scenes
    /// are immutable (`BlasterScene.isSystemOwned`) — caregiver edits live in a
    /// clone, so there is nothing of theirs here to overwrite. After applying,
    /// the stored content hash is advanced so it runs once per bundle change.
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
            // Insert any bundled word this store has never seen.
            //
            // A board is a list of tile KEYS; the words themselves are separate
            // `TileModel` records seeded at first install. So a build that adds a
            // word *and* places it on the core board used to update the board and
            // leave the word missing — `tileLookup[key]` returns nil and the cell
            // silently renders nothing. A hole where a word should be.
            //
            // This is the only path that carries bundled content to an existing
            // install (RELEASE bootstraps exactly once), so the vocabulary has to
            // travel with the board. Keys already present are left alone: they may
            // carry caregiver state — custom art, retirement, review flags — and
            // this is an update, not a reset.
            let existingKeys = Set(
                (try? context.fetch(FetchDescriptor<TileModel>()))?.map(\.key) ?? []
            )
            var addedTiles = 0
            var seen = Set<String>()
            for codable in vocab where !existingKeys.contains(codable.key) {
                guard seen.insert(codable.key).inserted else { continue }
                let tile = TileModel(from: codable)
                tile.isSystem = true
                context.insert(tile)
                addedTiles += 1
            }
            if addedTiles > 0 {
                print("updateSystemScene: inserted \(addedTiles) new bundled tile(s)")
            }

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
            // Re-baseline: the freshly-applied bundle content IS the new pristine
            // state. Without this the scene would compare against the OLD baseline
            // and start reporting isLocallyModified — labelling our own board
            // "modified locally" in the scenes list.
            scene.importedContentHash = scene.contentHash
            try context.save()
            UserDefaults.standard.set(bundledContentHash, forKey: AppSettingsKey.bootstrapContentHash)
            return true
        } catch {
            print("updateSystemScene failed: \(error)")
            return false
        }
    }
}
