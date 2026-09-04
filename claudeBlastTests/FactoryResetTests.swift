// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  FactoryResetTests.swift
//  claudeBlastTests
//
//  A reset must leave nothing behind, and must never claim to have seeded a
//  store it did not.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct FactoryResetTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Every model in the schema is something a reset has to clear.
    ///
    /// The delete list was hand-maintained and had fallen four models behind:
    /// `LoggedUtterance`, `TileArtVariant`, `RecordedScript` and `ReceivedPack`
    /// all survived. The first is the sharp one — an activity log referencing
    /// tile keys the reset had just deleted, sitting on the very screen the
    /// reset button is under.
    ///
    /// This asserts the *intent* rather than the call list: if a model joins
    /// `BlasterSchemaV1` and nobody updates the reset, this is the failure.
    @Test func theResetListCoversEverySyncedModel() {
        let cleared: Set<String> = [
            "MetricEvent", "SentenceCache", "BlasterScene", "TileArtVariant",
            "TileModel", "LoggedUtterance", "RecordedScript", "ReceivedPack",
            "ChildProfile", "DeviceProfile", "APIUsageEvent", "CompactionRun",
        ]
        let inSchema = (BlasterSchemaV1.syncedModels + BlasterSchemaV1.localModels)
            .map { String(describing: $0) }
        let missed = inSchema.filter { !cleared.contains($0) }
        #expect(missed.isEmpty, "not cleared by performFactoryReset: \(missed)")
    }

    // MARK: - The flag must not outlive the store

    /// A store that says "seeded" but holds no scenes gets seeded again.
    ///
    /// The flag lives in UserDefaults and the scenes live in the store; they
    /// commit separately. Kill the app in between — pressing Stop in Xcode right
    /// after a factory reset does exactly this — and the flag survives while the
    /// scenes do not. Believing the flag over the store makes that permanent: no
    /// scenes, no board, and no way to make one.
    @Test func anEmptyStoreReSeedsEvenWhenFlaggedAsInstalled() throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let priorInstalled = defaults.object(forKey: AppSettingsKey.bootstrapInstalled)
        let priorCloud = defaults.object(forKey: AppSettingsKey.icloudEnabled)
        defer {
            defaults.set(priorInstalled, forKey: AppSettingsKey.bootstrapInstalled)
            defaults.set(priorCloud, forKey: AppSettingsKey.icloudEnabled)
        }

        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        defaults.set(false, forKey: AppSettingsKey.icloudEnabled)

        #expect(BootstrapLoader.needsBootstrap() == false)          // the flag alone
        #expect(BootstrapLoader.needsBootstrap(context: container.mainContext))

        withExtendedLifetime(container) {}
    }

    /// With a scene present the flag is believed, so an ordinary launch does not
    /// re-seed over a working board.
    @Test func aPopulatedStoreDoesNotReSeed() throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let priorInstalled = defaults.object(forKey: AppSettingsKey.bootstrapInstalled)
        let priorCloud = defaults.object(forKey: AppSettingsKey.icloudEnabled)
        defer {
            defaults.set(priorInstalled, forKey: AppSettingsKey.bootstrapInstalled)
            defaults.set(priorCloud, forKey: AppSettingsKey.icloudEnabled)
        }

        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        defaults.set(false, forKey: AppSettingsKey.icloudEnabled)
        container.mainContext.insert(BlasterScene(name: "Core", homePageKey: "home"))
        try container.mainContext.save()

        #expect(BootstrapLoader.needsBootstrap(context: container.mainContext) == false)

        withExtendedLifetime(container) {}
    }

    /// With iCloud ON an empty store is the ordinary condition of a second
    /// device whose initial import has not landed. Re-seeding there would mint a
    /// duplicate of a dataset already on its way — the case `storeAlreadySeeded`
    /// exists to avoid — so the guard deliberately stands down.
    @Test func anEmptyStoreWithCloudOnDoesNotReSeed() throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let priorInstalled = defaults.object(forKey: AppSettingsKey.bootstrapInstalled)
        let priorCloud = defaults.object(forKey: AppSettingsKey.icloudEnabled)
        defer {
            defaults.set(priorInstalled, forKey: AppSettingsKey.bootstrapInstalled)
            defaults.set(priorCloud, forKey: AppSettingsKey.icloudEnabled)
        }

        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        defaults.set(true, forKey: AppSettingsKey.icloudEnabled)

        #expect(BootstrapLoader.needsBootstrap(context: container.mainContext) == false)

        withExtendedLifetime(container) {}
    }
}
}
