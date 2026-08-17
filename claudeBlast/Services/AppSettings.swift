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
    static let openaiApiKey      = "openai_api_key"
    static let providerChoice    = "provider_choice"
    static let audioEnabled          = "audio_enabled"
    static let tileSpeechEnabled     = "tile_speech_enabled"
    static let speechVoiceIdentifier = "speech_voice_identifier"
    // Deprecated: superseded by `tileSizeStep`. Left declared so the
    // UserDefaults key isn't accidentally reused for an unrelated setting.
    static let tileMinSize           = "tile_min_size"
    static let tileSizeStep          = "tile_size_step"
    static let compareProviders      = "compare_providers"
    static let imageSet              = "image_set"
    /// When ON, AI art generation covers every generatable style rather than just
    /// the active one (see `ImageSetCatalog.generationTargets`).
    ///
    /// Either way a *whole style* is generated, all of its variants: the variants
    /// are one image plus transforms of it, so generating some of them is not a
    /// meaningful request. This toggle picks how many styles, never how many
    /// variants within one.
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
