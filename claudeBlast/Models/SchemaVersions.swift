// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SchemaVersions.swift
//  claudeBlast
//
//  The app's versioned SwiftData schema and its migration plan.
//

import Foundation
import SwiftData

/// Version 1 of the Blaster schema — the shape promoted to the CloudKit
/// **Production** environment. See `docs/schema-audit-2026-08-06.md`.
///
/// ## Why this exists
///
/// Introduced while there was exactly one version and the migration plan was
/// empty. Retrofitting a `VersionedSchema` after real user data exists is
/// materially harder, so it goes in before the pilot rather than after.
///
/// ## The rules that bind every future version
///
/// Once V1 is deployed to Production CloudKit, the synced models are
/// **additive-only, forever**:
///
/// - You may add a record type, or add an optional/defaulted field.
/// - You may never delete a field or record type, change a field's type, or
///   change a field's on-disk name. (`originalName:` renames the *Swift*
///   property; the CloudKit field keeps its original name permanently.)
/// - **No optional stored properties. Use a non-optional with a sentinel default
///   (`""`, `Data()`, `0`) instead.** SwiftData accepts "optional *or* defaulted",
///   but only the defaulted form is safe here. CloudKit stores no nulls: a nil
///   optional is never written to the record, so its **field never materializes
///   in the schema** — and since the Production schema is read-only, a field that
///   never appeared in Development does not exist after promotion. The first user
///   to set it then fails to export. A defaulted property is written on every
///   save, so the field always exists. This bit us pre-promotion: `retiredReason`
///   was absent from the dev schema purely because nothing had been auto-hidden
///   yet.
/// - When converting an optional to a sentinel, audit the readers. `x != nil`
///   against a non-optional is a **warning, not an error**, and silently becomes
///   always-true; `if let y = opt?.field` still compiles and silently binds to the
///   empty sentinel. Both change behavior with a green build.
/// - Every new property must have a default value.
/// - No `@Attribute(.unique)` — CloudKit doesn't support it. Dedup in code
///   (`BootstrapLoader`, `ProfileMigration`, `CloudKitDedupReconciler`).
/// - Relationships, if ever introduced, must be optional with an inverse and
///   must not use `.deny`. V1 has none: `BlasterScene` stores its pages as
///   inline JSON `Data` instead, which is why this schema has no relationship
///   fragility at all.
///
/// `localModels` are exempt from all of the above — they never enter the
/// CloudKit schema and can be reshaped freely.
///
/// ## Adding V2
///
/// 1. Copy this enum to `BlasterSchemaV2`, bump `versionIdentifier`, and edit
///    the model list.
/// 2. Add V2 to `BlasterMigrationPlan.schemas`.
/// 3. Add a `MigrationStage` (`.lightweight` for pure additions; `.custom` when
///    data must be transformed). Old readers stay in the field — a tester on
///    build 3 must not be broken by build 7's schema.
enum BlasterSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// Models mirrored to the user's private CloudKit database when iCloud is
    /// on. **These are the ones bound by the additive-only rules above.**
    static var syncedModels: [any PersistentModel.Type] {
        [
            TileModel.self,
            TileArtVariant.self,
            SentenceCache.self,
            BlasterScene.self,
            RecordedScript.self,
            LoggedUtterance.self,
            ChildProfile.self,
        ]
    }

    /// Models that never leave the device (`cloudKitDatabase: .none`).
    ///
    /// - `DeviceProfile` — per-device identity and posture. A therapist's iPad
    ///   and iPhone legitimately hold different roles.
    /// - `MetricEvent` — the raw analytics stream. Highest write volume in the
    ///   app, disposable, and only ever read as this device's aggregate counts.
    /// - `APIUsageEvent` — what each OpenAI call consumed and cost. Local for the
    ///   same reason as `MetricEvent`, and because the spend is incurred by *this*
    ///   device against *this* device's API key, which is also the more correct
    ///   meaning.
    ///
    /// Free to evolve without migration ceremony, since nothing here is
    /// frozen by a Production CloudKit schema.
    static var localModels: [any PersistentModel.Type] {
        [
            DeviceProfile.self,
            MetricEvent.self,
            APIUsageEvent.self,
        ]
    }

    /// Every model in the version. `SchemaVersionTests` asserts this is exactly
    /// the union of the two partitions, so a model added to a configuration but
    /// not to the version (or vice versa) fails the build's test run rather
    /// than surfacing as a runtime "can't assign object to store" trap.
    static var models: [any PersistentModel.Type] {
        syncedModels + localModels
    }
}

/// Migration plan for the Blaster store.
///
/// Empty by design: V1 is the first version, so there is nothing to migrate
/// *from*. It's wired into the container now so that adding V2 later is a
/// two-line change to a path that already exists and is already exercised,
/// rather than a new mechanism introduced under pressure.
enum BlasterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BlasterSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
