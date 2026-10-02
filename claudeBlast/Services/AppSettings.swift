// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppSettings.swift
//  claudeBlast
//

import SwiftData
import Foundation

enum AppSettingsKey {
    /// Legacy: integer version stamp. Pre-Step M bootstrap used this; new code
    /// uses bootstrapContentHash + bootstrapInstalled. Kept declared so the
    /// UserDefaults key isn't accidentally reused.
    static let bootstrapVersion  = "bootstrap_version"
    /// SHA256 hex of the bundled content (vocabulary.json + scenes/*.json) at
    /// the most recent bootstrap. Used in DEBUG builds to auto-re-bootstrap
    /// when a developer edits a bundled file. RELEASE builds ignore this.
    static let bootstrapContentHash = "bootstrap_content_hash"
    /// Set to true the first time bootstrap completes. RELEASE builds use
    /// this as the sole bootstrap gate — once true, app updates never
    /// auto-replace the user's scene/vocab.
    static let bootstrapInstalled   = "bootstrap_installed"
    /// Set once after the one-time tile-provenance backfill runs. Existing
    /// installs predate `TileModel.isSystem`, so their bundled tiles default
    /// to `false`; the backfill marks the ones matching bundled vocabulary as
    /// system. See `BootstrapLoader.backfillTileProvenance`.
    static let tileProvenanceBackfilled = "tile_provenance_backfilled"
    /// CloudKitDedupReconciler telemetry (local, per-device). Surfaced on the
    /// About & Stats screen. `reconcileLastDate` is a Double
    /// timeIntervalSinceReferenceDate.
    static let reconcileLastDeleted     = "reconcile_last_deleted"
    static let reconcileLifetimeDeleted = "reconcile_lifetime_deleted"
    static let reconcileLastDate        = "reconcile_last_date"
    // NB: forceRefreshDuplicate / forceRefreshDuplicateRemembered were removed
    // with the manual "Update Available" flow. System scenes are immutable now,
    // so a newer bundled board is applied silently at launch — there is nothing
    // of the caregiver's inside one to save a copy of first.
    static let icloudEnabled     = "icloud_enabled"

    // Activity log view options. Persisted because a caregiver who turns on
    // hour grouping and comes back to find it off will just turn it on again.
    static let activityRange       = "activity_range"
    static let activityClusterByName = "activity_cluster_by_name"
    /// Which band the log is broken into: session, hour, or none.
    ///
    /// Replaces the `activity_group_by_hour` boolean it grew out of. A session
    /// is a band exactly as an hour is — the difference is that its edges come
    /// from behaviour rather than the clock — so the two belong in one choice
    /// rather than as a bool plus a special case.
    static let activityBand          = "activity_band"
    /// `BlasterScene.sceneID` the Reach report is scoped to. Empty falls back to
    /// the active scene, which survives a rename and is what a caregiver opening
    /// the screen almost always means.
    static let coverageSceneID          = "coverage_scene_id"
    /// Whether the never-used breakdown is grouped by part of speech or by page.
    static let coverageBreakdown      = "coverage_breakdown"
    static let openaiApiKey      = "openai_api_key"
    static let providerChoice    = "provider_choice"
    // Provenance for a key that arrived as a .blasterkey file. The secret itself
    // is in the Keychain like any other; these say where it came from, so the
    // Device tab can name it and the refusal banners can be written for someone
    // holding a key they did not buy.
    //
    // Device-local UserDefaults rather than SwiftData on purpose: nothing here
    // touches the synced schema, which is what lets the whole feature land
    // before CloudKit promotion without interacting with gates 8 or 9.
    static let giftedKeyLabel    = "gifted_key_label"
    static let giftedKeyIssuer   = "gifted_key_issuer"
    static let giftedKeyIssued   = "gifted_key_issued"
    static let giftedKeyExpires  = "gifted_key_expires"
    static let giftedKeyLastFour = "gifted_key_last_four"
    // Permission to send anything to OpenAI. See `AIConsent`. Device-local for
    // the same reason as the gifted-key provenance above.
    static let aiConsentVersion         = "ai_consent_version"
    static let aiConsentAcceptedAt      = "ai_consent_accepted_at"
    static let aiConsentPromptedVersion = "ai_consent_prompted_version"

    /// Whether the CloudKit schema probe has written its rows and not yet
    /// cleaned them up. DEBUG only. Persisted rather than held in view state
    /// because the wait between the two halves is a sync round trip and a
    /// console check — minutes, and possibly a relaunch.
    static let schemaProbePopulated = "schema_probe_populated"
    static let audioEnabled          = "audio_enabled"
    static let tileSpeechEnabled     = "tile_speech_enabled"
    static let speechVoiceIdentifier = "speech_voice_identifier"
    // Deprecated: superseded by `tileSizeStep`. Left declared so the
    // UserDefaults key isn't accidentally reused for an unrelated setting.
    static let tileMinSize           = "tile_min_size"
    // Deprecated: the -3…3 density stepper, superseded by `boardLayout`. Still
    // read once, as the fallback for a device that has not chosen a layout —
    // see `BoardLayout.current`.
    static let tileSizeStep          = "tile_size_step"
    /// `BoardLayout.rawValue`: standard, large or largest.
    static let boardLayout           = "board_layout"
    /// Whether a scene's declared grid (`BlasterScene.designedFor`) overrides
    /// `boardLayout` on a matching device. On unless a caregiver opts out.
    static let honorSceneLayouts     = "honor_scene_layouts"
    /// PDF export: break sheets where the screen breaks pages. See
    /// `BoardPrintOptions.matchPageBreaks`. Kept between exports — it is a
    /// therapist's standing preference, not a per-board choice.
    static let printMatchPageBreaks  = "print_match_page_breaks"
    static let compareProviders      = "compare_providers"
    static let imageSet              = "image_set"
    // Deprecated: the "Generate all styles" toggle. Left declared, like
    // `tileMinSize` above, so the UserDefaults key isn't reused.
    //
    // It asked the caregiver to predict, before they could see any counts,
    // whether a word should cost one image or twenty — and it was only
    // defensible while that prediction was unrecoverable. The scene editor's Art
    // Coverage rows now answer the same question afterwards, with the numbers in
    // front of them, so drawing a word simply covers the style they are using.
    static let generateAllStyles     = "generate_all_styles"

    // Sentence tray timeline settings (PR cb-tray-timeline)
    static let tileCapPerGroup       = "tile_cap_per_group"
    static let idleDebounceMs        = "idle_debounce_ms"
    static let trayBufferSize        = "tray_buffer_size"
    /// Long idle timeout (ms) after which the active group is auto-committed to history (the
    /// equivalent of the Done button firing on its own). 0 disables auto-Done.
    static let autoDoneMs            = "auto_done_ms"

    /// Demo mode: cleans up the app for screen recording — hides the TileScript
    /// playback pill on a straight Run, and always shows the "Generating…" beat
    /// even when a result comes from cache, so demos read as live AI.
    static let demoMode              = "demo_mode"

    // Compaction hand-off between launches. Freed SQLite pages can only be
    // returned to the filesystem while nothing has the store open, which in this
    // app's life is the moment before the ModelContainer is built — so the launch
    // that folds rows leaves a note here for the next one to act on.
    // See MetricCompactor.reclaimPendingSpace.
    static let compactionReclaimPending = "compaction_reclaim_pending"
    /// Written by SwiftData's own configuration rather than reconstructed, so a
    /// guessed path can never silently reclaim nothing.
    static let compactionStorePath      = "compaction_store_path"
    /// Storage budget for the device-local metric store, in megabytes.
    /// Zero means "use the shipping default". See `MetricCompactor.Policy`.
    static let compactionBudgetMB       = "compaction_budget_mb"
    /// The `CompactionRun` awaiting its reclaim numbers, and what the reclaim
    /// freed. Reclamation happens before the app has a `ModelContainer`, so the
    /// result is parked here and attached to the row once there is a store to
    /// write to. See `MetricCompactor.attachPendingReclaim`.
    static let compactionLastRunID      = "compaction_last_run_id"
    static let compactionReclaimedBytes = "compaction_reclaimed_bytes"
}

/// Convenience accessor for the demo-mode flag from non-view code (engine, runner).
enum DemoMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: AppSettingsKey.demoMode) }
}

// Bootstrap version stamp removed in Step M. needsBootstrap now derives from
// a content hash of the bundled resource files (DEBUG) or the bootstrapInstalled
// flag (RELEASE). See BootstrapLoader.needsBootstrap().

func setModelContainer(icloudEnabled: Bool) -> ModelContainer {
    // Two-config split: DeviceProfile is per-device and must never sync
    // (role differs between an iPad-in-clinic and the therapist's iPhone).
    // Everything else (including ChildProfile, BlasterScene, caches) can
    // sync via CloudKit when opt-in is on.
    //
    // The "synced" configuration keeps the default name/URL so existing
    // installs continue to read the same store file — only the new local
    // configuration gets a distinct on-disk location.
    // The synced/local partition is defined once, on the versioned schema, so
    // the configurations here and the schema version can't drift apart.
    // See BlasterSchemaV1 and docs/schema-audit-2026-08-06.md.
    let syncedSchema = Schema(BlasterSchemaV1.syncedModels)
    let localSchema = Schema(BlasterSchemaV1.localModels)
    let allSchema = Schema(versionedSchema: BlasterSchemaV1.self)

    let localConfig = ModelConfiguration("DeviceLocal",
                                         schema: localSchema,
                                         isStoredInMemoryOnly: false,
                                         cloudKitDatabase: .none)
    let syncedLocalConfig = ModelConfiguration(schema: syncedSchema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
    // Pinned to an EXPLICIT, brand-aligned container decoupled from the bundle id,
    // so a future bundle-id change can't orphan the data. Register it once via the
    // iCloud (CloudKit) capability. Inert until the entitlement exists — the `try?`
    // below falls back to local-only.
    let syncedCloudConfig = ModelConfiguration(schema: syncedSchema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .private("iCloud.app.blasterai"))
    // iCloud defaults OFF. Toggle available on debug builds so CloudKit sync
    // can be tested on real devices without a special build. try? falls back
    // gracefully if the CloudKit entitlement is absent.
    if icloudEnabled,
       let container = try? ModelContainer(for: allSchema,
                                           migrationPlan: BlasterMigrationPlan.self,
                                           configurations: [localConfig, syncedCloudConfig]) {
        return container
    }
    do {
        return try ModelContainer(for: allSchema,
                                  migrationPlan: BlasterMigrationPlan.self,
                                  configurations: [localConfig, syncedLocalConfig])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}
