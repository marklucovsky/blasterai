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
            "ChildProfile",
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
        // V1 is the first version — nothing to migrate from yet.
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
}
