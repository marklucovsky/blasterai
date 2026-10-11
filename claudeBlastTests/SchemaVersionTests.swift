// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SchemaVersionTests.swift
//  claudeBlastTests
//
//  Guards on the versioned schema that gets promoted to Production CloudKit.
//  See docs/schema-audit-2026-08-06.md.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@Suite("Schema version")
struct SchemaVersionTests {

    private func names(_ models: [any PersistentModel.Type]) -> Set<String> {
        Set(models.map { String(describing: $0) })
    }

    /// Every synced model must be exercised by `CloudKitSchemaExerciser`.
    ///
    /// A record type CloudKit has never been asked to write does not exist in
    /// the Development schema, and `SchemaVersions` says what that costs after
    /// promotion: Production is read-only, so the first device to write an
    /// unmaterialized type fails to sync forever. We shipped four of eight for
    /// a while without noticing.
    ///
    /// So adding a synced model and forgetting to exercise it fails here, not
    /// at the promotion ceremony.
    @Test func everySyncedModelIsExercised() {
        #expect(Set(CloudKitSchemaExerciser.exercised) == names(BlasterSchemaV1.syncedModels))
    }

    /// `probeOnly` is what the Device tab tells a human to look for in the
    /// CloudKit console, so a name that is not actually exercised would send
    /// someone hunting for a type that was never going to appear.
    @Test func probeOnlyTypesAreActuallyExercised() {
        #expect(Set(CloudKitSchemaExerciser.probeOnly)
                    .isSubset(of: Set(CloudKitSchemaExerciser.exercised)))
    }

    /// The three are the ones nothing else creates: bootstrap seeds tiles,
    /// scenes and a profile, and one generated sentence produces a cache entry
    /// and a logged utterance. If a future change makes one of these arrive on
    /// its own, it stops being evidence the probe reached the server and this
    /// list needs rethinking rather than quietly extending.
    @Test func probeOnlyExcludesWhatOrdinaryUseCreates() {
        let arrivesOnItsOwn = ["TileModel", "BlasterScene", "ChildProfile",
                               "SentenceCache", "LoggedUtterance", "LoggedNavigation"]
        for name in arrivesOnItsOwn {
            #expect(!CloudKitSchemaExerciser.probeOnly.contains(name),
                    "\(name) arrives without the probe, so its presence proves nothing")
        }
    }

    @Test func versionIdentifierIsV1() {
        #expect(BlasterSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    /// The synced set is what gets frozen by promotion. Spelled out literally
    /// so that adding a model to it is a deliberate, reviewed act — this test
    /// failing is the intended prompt to ask "does this really need to sync,
    /// and is it shaped for a schema it can never remove a field from?"
    @Test func syncedModelsAreExactlyTheExpectedSet() {
        #expect(names(BlasterSchemaV1.syncedModels) == [
            "TileModel",
            "TileArtVariant",
            "SentenceCache",
            "BlasterScene",
            "RecordedScript",
            "LoggedUtterance",
            "LoggedNavigation",
            "ChildProfile",
            "ReceivedPack",
        ])
    }

    /// Device-local models never enter the CloudKit schema and stay freely
    /// mutable. `MetricEvent` moved here in the pre-promotion audit (D3).
    /// Inventory tripwire: changing the device-local set must be a deliberate
    /// edit here, never a side effect. `APIUsageEvent` was added in 2A (token/
    /// cost accounting) — device-local because spend is incurred by *this* device
    /// against *this* device's API key.
    ///
    /// Worth noting what did NOT change: `syncedModels` above is untouched, which
    /// is the evidence that cost accounting added nothing to the partition bound
    /// by the additive-only CloudKit rules.
    @Test func localModelsAreExactlyTheExpectedSet() {
        #expect(names(BlasterSchemaV1.localModels) == [
            "DeviceProfile",
            "MetricEvent",
            "APIUsageEvent",
            "CompactionRun",
        ])
    }

    /// Drift guard. The container is built from these two partitions, so a
    /// model registered in one place but not the other shows up at runtime as
    /// a "can't assign an object to a store" trap — which is exactly the class
    /// of bug that made scene duplication untestable before. Fail here instead.
    @Test func modelsIsExactlyTheUnionOfThePartitions() {
        let union = names(BlasterSchemaV1.syncedModels)
            .union(names(BlasterSchemaV1.localModels))
        #expect(names(BlasterSchemaV1.models) == union)
        #expect(BlasterSchemaV1.models.count
                == BlasterSchemaV1.syncedModels.count + BlasterSchemaV1.localModels.count)
    }

    /// The two partitions must be disjoint — a model in both configurations
    /// would be ambiguous at insert time.
    @Test func partitionsAreDisjoint() {
        let overlap = names(BlasterSchemaV1.syncedModels)
            .intersection(names(BlasterSchemaV1.localModels))
        #expect(overlap.isEmpty)
    }

    @Test func migrationPlanDeclaresOnlyV1() {
        #expect(BlasterMigrationPlan.schemas.count == 1)
        #expect(String(describing: BlasterMigrationPlan.schemas[0])
                == String(describing: BlasterSchemaV1.self))
        // Empty on purpose, and not only because V1 is the first version: a
        // stage makes Core Data demand an exact fingerprint match, which the
        // stores already on devices do not have. See `BlasterSchemaV1`.
        #expect(BlasterMigrationPlan.stages.isEmpty)
    }

    /// A container opens at V1 through the migration plan, with the same
    /// synced/local configuration split the app uses, and round-trips a model
    /// from each partition.
    @MainActor
    @Test func containerOpensAtV1AndRoundTripsBothPartitions() throws {
        let localConfig = ModelConfiguration(
            "SchemaVersionTest-Local",
            schema: Schema(BlasterSchemaV1.localModels),
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let syncedConfig = ModelConfiguration(
            "SchemaVersionTest-Synced",
            schema: Schema(BlasterSchemaV1.syncedModels),
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)

        let container = try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            migrationPlan: BlasterMigrationPlan.self,
            configurations: [localConfig, syncedConfig])
        let ctx = container.mainContext

        // Synced partition.
        ctx.insert(TileModel(key: "pizza", wordClass: "food"))
        // Local partition.
        ctx.insert(MetricEvent(subjectType: "cache", subjectKey: "pizza", eventType: .hit))
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<TileModel>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<MetricEvent>()).count == 1)
    }

    /// A store written before `LoggedNavigation` existed opens through the
    /// app's real migration plan, keeps its rows, and takes the new type.
    ///
    /// Every installed device holds such a store. The first attempt at this
    /// change used a V2 with a migration stage and trapped at launch on exactly
    /// this — so it is tested on disk, with the app's two-configuration split.
    @MainActor
    @Test func aStoreWrittenBeforeLoggedNavigationOpensAndKeepsItsRows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let syncedURL = dir.appendingPathComponent("synced.store")
        let localURL = dir.appendingPathComponent("local.store")
        let before = BlasterSchemaV1.syncedModels.filter { $0 != LoggedNavigation.self }

        do {
            let old = try ModelContainer(
                for: Schema(before + BlasterSchemaV1.localModels),
                configurations: [
                    ModelConfiguration("Local", schema: Schema(BlasterSchemaV1.localModels),
                                       url: localURL, cloudKitDatabase: .none),
                    ModelConfiguration("Synced", schema: Schema(before),
                                       url: syncedURL, cloudKitDatabase: .none),
                ])
            let ctx = old.mainContext
            ctx.insert(LoggedUtterance(tileKeys: ["eat", "pizza"], sentence: "I want pizza",
                                       repetitionCount: 0, pageKeys: ["home", "food"]))
            ctx.insert(MetricEvent(subjectType: "cache", subjectKey: "pizza", eventType: .hit))
            try ctx.save()
        }

        let current = try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            migrationPlan: BlasterMigrationPlan.self,
            configurations: [
                ModelConfiguration("Local", schema: Schema(BlasterSchemaV1.localModels),
                                   url: localURL, cloudKitDatabase: .none),
                ModelConfiguration("Synced", schema: Schema(BlasterSchemaV1.syncedModels),
                                   url: syncedURL, cloudKitDatabase: .none),
            ])
        let ctx = current.mainContext
        let utterances = try ctx.fetch(FetchDescriptor<LoggedUtterance>())
        #expect(utterances.map(\.sentence) == ["I want pizza"])
        #expect(utterances.first?.pageKeys == ["home", "food"])
        #expect(try ctx.fetch(FetchDescriptor<MetricEvent>()).count == 1)

        ctx.insert(LoggedNavigation(fromPageKey: "home", toPageKey: "food", linkKey: "food"))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<LoggedNavigation>()).count == 1)
    }
}
