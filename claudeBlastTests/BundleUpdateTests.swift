// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BundleUpdateTests.swift
//  claudeBlastTests
//
//  The content-hash stamp must mean "this device holds this bundle's content".
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct BundleUpdateTests {

    /// Save/restore the two defaults these tests move, so a failure here can't
    /// leave the rest of the suite bootstrapping from a bogus state.
    private func withCleanDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let installed = defaults.bool(forKey: AppSettingsKey.bootstrapInstalled)
        let hash = defaults.string(forKey: AppSettingsKey.bootstrapContentHash)
        defer {
            defaults.set(installed, forKey: AppSettingsKey.bootstrapInstalled)
            if let hash {
                defaults.set(hash, forKey: AppSettingsKey.bootstrapContentHash)
            } else {
                defaults.removeObject(forKey: AppSettingsKey.bootstrapContentHash)
            }
        }
        try body()
    }

    /// The bug this guards: a device that **skips** seeding must not claim the
    /// bundle's content hash.
    ///
    /// `storeAlreadySeeded` exists so a second device under CloudKit doesn't
    /// seed a duplicate copy of synced data. It used to call
    /// `markBootstrapComplete()` unconditionally, which stamped the hash — and
    /// the stamp is what `isBundleUpdateAvailable()` reads. So the launch
    /// sequence would decide "no update available" moments after deliberately
    /// applying nothing, and `updateSystemScene` never ran.
    ///
    /// Observed as: edits to `core_first.json` never appearing in a DEBUG build
    /// until the app was deleted and reinstalled.
    @Test func skippingTheSeedLeavesTheBundleUpdatePending() throws {
        try withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set("a-stale-hash-from-an-older-bundle",
                         forKey: AppSettingsKey.bootstrapContentHash)

            BootstrapLoader.markBootstrapComplete(appliedBundledContent: false)

            #expect(defaults.bool(forKey: AppSettingsKey.bootstrapInstalled))
            // The stale hash survives, so the update is still on the table.
            #expect(BootstrapLoader.isBundleUpdateAvailable())
        }
    }

    /// The other half: a device that DID seed has, by definition, applied the
    /// bundle, so it stamps and reports no pending update.
    @Test func seedingStampsTheHashAndClearsThePendingUpdate() throws {
        try withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set("a-stale-hash-from-an-older-bundle",
                         forKey: AppSettingsKey.bootstrapContentHash)

            BootstrapLoader.markBootstrapComplete(appliedBundledContent: true)

            #expect(defaults.bool(forKey: AppSettingsKey.bootstrapInstalled))
            #expect(!BootstrapLoader.isBundleUpdateAvailable())
        }
    }

    /// `updateSystemScene` is the path that actually carries a board change to
    /// an existing install, so it must both rewrite the scene and settle the
    /// pending-update flag.
    @Test func updateSystemSceneAppliesBundleAndClearsPending() throws {
        try withCleanDefaults {
            let container = TestStore.freshContainer()
            let ctx = container.mainContext
            let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)

            UserDefaults.standard.set("a-stale-hash-from-an-older-bundle",
                                      forKey: AppSettingsKey.bootstrapContentHash)
            #expect(BootstrapLoader.isBundleUpdateAvailable())

            let applied = BootstrapLoader.updateSystemScene(context: ctx)
            #expect(applied)
            #expect(!BootstrapLoader.isBundleUpdateAvailable())

            // And the applied board is the current bundle: no back-to-home tiles.
            let scenes = try ctx.fetch(FetchDescriptor<BlasterScene>())
            let system = try #require(scenes.first { $0.systemSceneKey == "core_first" })
            let homeLinks = system.pages.flatMap { page in
                page.tiles.filter { $0.link == SceneNavigation.homeLinkToken }
            }
            #expect(homeLinks.isEmpty)

            withExtendedLifetime(result) {}
        }
    }

    /// A board is a list of tile KEYS; the words are separate `TileModel`
    /// records seeded at first install. `updateSystemScene` is the *only* path
    /// that carries bundled content to an existing install — RELEASE bootstraps
    /// exactly once — so if it updates the board without the vocabulary, a build
    /// that adds a word and places it on the core board renders a hole: the cell
    /// looks up a key that isn't in the store and draws nothing.
    ///
    /// Simulated by deleting a word the bundled board references, the way an
    /// older install would simply never have had it.
    @Test func updateSystemSceneInsertsVocabularyMissingFromAnOlderInstall() throws {
        try withCleanDefaults {
            let container = TestStore.freshContainer()
            let ctx = container.mainContext
            let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)

            // Pick a word the bundled board actually places, so its absence is
            // the exact failure this guards.
            let scenesBefore = try ctx.fetch(FetchDescriptor<BlasterScene>())
            let system = try #require(scenesBefore.first { $0.systemSceneKey == "core_first" })
            let boardKeys = Set(system.pages.flatMap { $0.tiles.map(\.key) })
            let victimKey = try #require(boardKeys.sorted().first)

            let tiles = try ctx.fetch(FetchDescriptor<TileModel>())
            let victim = try #require(tiles.first { $0.key == victimKey })
            ctx.delete(victim)
            try ctx.save()

            let afterDelete = try ctx.fetch(FetchDescriptor<TileModel>())
            #expect(!afterDelete.contains { $0.key == victimKey })

            UserDefaults.standard.set("a-stale-hash-from-an-older-bundle",
                                      forKey: AppSettingsKey.bootstrapContentHash)
            #expect(BootstrapLoader.updateSystemScene(context: ctx))

            // The word is back, flagged as bundled content.
            let restored = try ctx.fetch(FetchDescriptor<TileModel>())
            let recovered = try #require(restored.first { $0.key == victimKey })
            #expect(recovered.isSystem)

            withExtendedLifetime(result) {}
        }
    }

    /// The update must not clobber words the store already has: a tile can carry
    /// caregiver state — custom art, retirement, review flags — and this is an
    /// update, not a reset.
    @Test func updateSystemSceneLeavesExistingTilesAlone() throws {
        try withCleanDefaults {
            let container = TestStore.freshContainer()
            let ctx = container.mainContext
            let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)

            let tiles = try ctx.fetch(FetchDescriptor<TileModel>())
            let subject = try #require(tiles.first { $0.key == "pizza" })
            subject.isRetired = true
            let countBefore = tiles.count
            try ctx.save()

            #expect(BootstrapLoader.updateSystemScene(context: ctx))

            let after = try ctx.fetch(FetchDescriptor<TileModel>())
            #expect(after.count == countBefore)          // no duplicate inserted
            let still = try #require(after.first { $0.key == "pizza" })
            #expect(still.isRetired)                     // caregiver state intact

            withExtendedLifetime(result) {}
        }
    }
}
}
