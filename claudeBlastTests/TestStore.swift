// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TestStore.swift
//  claudeBlastTests
//
//  ONE shared in-memory ModelContainer for the entire test bundle.
//
//  Why one container (not one per test): under Swift Testing's parallel
//  execution, per-test containers pile up — dozens of live
//  NSPersistentStoreCoordinators over the same schema — until SwiftData's
//  process-global entity registry corrupts and `context.insert` traps
//  (EXC_BREAKPOINT), reproducible on-device. A single store, created once,
//  never hits that.
//
//  `cloudKitDatabase: .none`: the app carries the CloudKit entitlement, so the
//  default (`.automatic`) spins up an NSCloudKitMirroringDelegate against the
//  in-memory store — invalid, and it crashes the process.
//
//  Isolation between tests comes from `reset()`, which FETCHES and deletes every
//  object (the `delete(model:)` batch form is unreliable on in-memory stores and
//  left rows behind, which showed up as cross-test bleed). Every suite is a
//  sub-suite of the `.serialized` `SerialTests` root (see SerialTests.swift) and
//  `@MainActor`, so no two tests touch the shared store at once.
//

import SwiftData
@testable import claudeBlast

enum TestStore {
    /// The single process-wide container. Created once, lazily, on the main actor.
    @MainActor static let container: ModelContainer = {
        // Mirror the app's schema-split (AppSettings.makeModelContainer):
        // DeviceProfile lives in its OWN configuration, everything else in
        // another. Lumping DeviceProfile in with the rest gave it an entity
        // binding that disagreed with the running host app's separate
        // DeviceProfile store, so inserting one (via a scene duplicate/fork)
        // trapped with "Can't assign an object to a store…". Matching the split
        // keeps the binding consistent.
        let localSchema = Schema([DeviceProfile.self])
        let mainSchema = Schema([
            TileModel.self, TileArtVariant.self, SentenceCache.self, BlasterScene.self,
            MetricEvent.self, RecordedScript.self, LoggedUtterance.self, ChildProfile.self,
        ])
        let allSchema = Schema([
            TileModel.self, TileArtVariant.self, SentenceCache.self, BlasterScene.self,
            MetricEvent.self, RecordedScript.self, LoggedUtterance.self,
            ChildProfile.self, DeviceProfile.self,
        ])
        let localConfig = ModelConfiguration("DeviceLocal-Test", schema: localSchema,
                                             isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let mainConfig = ModelConfiguration(schema: mainSchema,
                                            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: allSchema, configurations: [localConfig, mainConfig])
    }()

    /// Delete every row so the next test starts empty. Runs on the shared
    /// `mainContext` — the same context tests use — so it clears that context's
    /// registered objects too (wiping via a throwaway context leaves the
    /// mainContext's rows visible to the next test, i.e. cross-test bleed).
    /// `rollback()` first discards any changes a prior test left unsaved.
    /// Fetch-and-delete because the `delete(model:)` batch form leaves rows
    /// behind on in-memory stores.
    @MainActor static func reset() {
        let ctx = container.mainContext
        ctx.rollback()
        func wipe<T: PersistentModel>(_: T.Type) {
            for obj in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { ctx.delete(obj) }
        }
        wipe(TileModel.self); wipe(TileArtVariant.self); wipe(SentenceCache.self)
        wipe(BlasterScene.self); wipe(MetricEvent.self); wipe(RecordedScript.self)
        wipe(LoggedUtterance.self); wipe(ChildProfile.self); wipe(DeviceProfile.self)
        try? ctx.save()
    }

    /// A clean main context on the shared container.
    @MainActor static func freshContext() -> ModelContext {
        reset()
        return container.mainContext
    }

    /// The shared container, wiped clean. Callers that read `.mainContext` should
    /// prefer `freshContext()`; kept for helpers that need a container.
    @MainActor static func freshContainer() -> ModelContainer {
        reset()
        return container
    }
}
