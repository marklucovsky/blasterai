// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AboutStatsView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Read-only "About & Stats" screen: live vocabulary / board / activity counts,
/// plus a CloudKit "sync health" panel. Every number is `@Query`-backed, so the
/// **duplicate count** updates in real time — it spikes when a multi-device sync
/// lands, and `CloudKitDedupReconciler` drives it back to zero. Lets you watch
/// the duplication bug and the self-heal happen live. See `docs/cloudkit-dedup.md`.
struct AboutStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var tiles: [TileModel]
    @Query private var scenes: [BlasterScene]
    @Query private var profiles: [ChildProfile]
    @Query private var caches: [SentenceCache]
    @Query private var utterances: [LoggedUtterance]
    @Query private var artVariants: [TileArtVariant]

    @AppStorage(AppSettingsKey.reconcileLifetimeDeleted) private var lifetimeCleaned = 0
    @AppStorage(AppSettingsKey.reconcileLastDate) private var lastCheckedRaw = 0.0
    @AppStorage(AppSettingsKey.icloudEnabled) private var icloudEnabled = false

    var body: some View {
        List {
            Section("Vocabulary") {
                LabeledContent("Words", value: "\(tiles.count)")
                let custom = tiles.filter { !$0.isSystem }.count
                if custom > 0 { LabeledContent("Added by you", value: "\(custom)") }
            }
            Section("Content") {
                LabeledContent("Boards", value: "\(scenes.count)")
                LabeledContent("Pages", value: "\(pageCount)")
            }
            Section("Profiles & activity") {
                LabeledContent("Profiles", value: "\(profiles.count)")
                LabeledContent("Cached sentences", value: "\(caches.count)")
                LabeledContent("Spoken (logged)", value: "\(utterances.count)")
                if !artVariants.isEmpty { LabeledContent("Custom art", value: "\(artVariants.count)") }
            }
            syncHealthSection
        }
        .navigationTitle("About & Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var syncHealthSection: some View {
        Section {
            LabeledContent("Duplicate records now") {
                Text("\(duplicateTotal)")
                    .monospacedDigit()
                    .foregroundStyle(duplicateTotal > 0 ? .orange : .secondary)
            }
            if lifetimeCleaned > 0 {
                LabeledContent("Duplicates cleaned (lifetime)", value: "\(lifetimeCleaned)")
            }
            if let last = lastChecked {
                LabeledContent("Last checked",
                               value: last.formatted(date: .abbreviated, time: .shortened))
            }
            Button {
                CloudKitDedupReconciler.reconcile(context: modelContext)
            } label: {
                Label("Check & clean now", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Sync health")
        } footer: {
            Text(icloudEnabled
                 ? "iCloud sync is on. Duplicate records from multi-device sync are collapsed automatically at launch and when new data arrives."
                 : "iCloud sync is off, so duplicates should always read 0.")
        }
    }

    // MARK: - Derived

    private var pageCount: Int {
        scenes.reduce(0) { $0 + $1.pages.count }
    }

    private var lastChecked: Date? {
        lastCheckedRaw > 0 ? Date(timeIntervalSinceReferenceDate: lastCheckedRaw) : nil
    }

    /// Count of *excess* records sharing a logical key — the same keys the
    /// reconciler collapses. 0 on a healthy single-device or post-reconcile store.
    private var duplicateTotal: Int {
        dupes(tiles.map(\.key))
        + dupes(scenes.filter { !$0.systemSceneKey.isEmpty }.map(\.systemSceneKey))
        + max(0, profiles.filter(\.isSystem).count - 1)
        + dupes(artVariants.map { "\($0.tileKey)|\($0.imageSetRaw)" })
        + dupes(caches.map { "\($0.cacheKey)|\($0.childID ?? "")" })
    }

    private func dupes(_ keys: [String]) -> Int { keys.count - Set(keys).count }
}
