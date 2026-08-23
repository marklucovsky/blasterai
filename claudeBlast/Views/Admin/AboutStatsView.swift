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
    @Query(sort: \CompactionRun.startedAt, order: .reverse)
    private var compactionRuns: [CompactionRun]

    @AppStorage(AppSettingsKey.compactionBudgetMB) private var budgetMB = 0

    @State private var storage: StorageReport?

    @AppStorage(AppSettingsKey.reconcileLifetimeDeleted) private var lifetimeCleaned = 0
    @AppStorage(AppSettingsKey.reconcileLastDate) private var lastCheckedRaw = 0.0
    @AppStorage(AppSettingsKey.icloudEnabled) private var icloudEnabled = false

    var body: some View {
        List {
            Section("Vocabulary") {
                LabeledContent("Words", value: "\(words.count)")
                let custom = words.filter { !$0.isSystem }.count
                if custom > 0 { LabeledContent("Added by you", value: "\(custom)") }
            }
            Section("Content") {
                LabeledContent("Scenes", value: "\(scenes.count)")
                LabeledContent("Pages", value: "\(pageCount)")
            }
            Section("Profiles & activity") {
                LabeledContent("Profiles", value: "\(profiles.count)")
                LabeledContent("Cached sentences", value: "\(caches.count)")
                LabeledContent("Spoken (logged)", value: "\(utterances.count)")
                if !artVariants.isEmpty { LabeledContent("Custom art", value: "\(artVariants.count)") }
            }
            storageSection
            syncHealthSection
        }
        .navigationTitle("About & Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Measured on appear, not per render: it stats a directory tree.
            storage = StorageReporter.report(container: modelContext.container)
        }
    }

    /// What this install occupies, measured from the files themselves.
    ///
    /// Reporting only, no reclaim buttons. Generated art is *synced*, so a
    /// "free up space" action here would delete it from every device the family
    /// owns — and per the app's wipe semantics, cloud deletion is a deliberate,
    /// explicit path (per-word delete), never a convenience one tap from a stats
    /// screen. Space management is `MetricCompactor`, which runs automatically
    /// and only touches this device's own usage history.
    @ViewBuilder
    private var storageSection: some View {
        if let storage {
            Section {
                ForEach(storage.components.filter { $0.bytes > 0 }) { component in
                    LabeledContent(component.label) {
                        Text(StorageReporter.format(component.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Total on this device") {
                    Text(StorageReporter.format(storage.onDeviceBytes))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            } header: {
                Text("Storage")
            } footer: {
                // Grouped by what the space is FOR, not by how the app is
                // packaged — tile art is counted as tile art wherever the build
                // happens to put it. So the total tracks Settings closely but is
                // not derived the same way, and the wording says "about" rather
                // than implying the two must agree to the byte.
                //
                // The synced figure is named separately because it is the
                // family's iCloud quota, which a device total does not imply.
                Text(icloudEnabled
                     ? "\(StorageReporter.format(storage.syncedBytes)) of this is shared with your other devices through iCloud. The total should be about what Settings → General → iPhone Storage reports."
                     : "The total should be about what Settings → General → iPhone Storage reports.")
            }

            budgetSection
            compactionSection
        }
    }

    /// The storage budget, which used to be sealed at 256 MB.
    ///
    /// It is a setting because the reasoning behind 256 is not universal: it
    /// balances "enough headroom" against "not an app anyone rage-deletes when
    /// their phone fills up", and that balance lands differently on a 64 GB
    /// device or in a household where storage pressure is weekly. The retention
    /// floors deliberately do NOT move with it — a smaller budget makes the app
    /// hold the six-month floor and say so, never quietly keep less.
    @ViewBuilder
    private var budgetSection: some View {
        Section {
            Picker("Usage history budget", selection: $budgetMB) {
                Text("Default (256 MB)").tag(0)
                ForEach(MetricCompactor.Policy.offeredMegabytes, id: \.self) { mb in
                    Text("\(mb) MB").tag(mb)
                }
            }
            if let storage {
                let policy = MetricCompactor.Policy.resolved()
                LabeledContent("Trims above",
                               value: StorageReporter.format(policy.highWaterBytes))
                // The honest headline: how close this device is to the mark it
                // reacts at. On any real device this is a fraction of a percent.
                let used = Double(storage.deviceLocalBytes) / Double(policy.highWaterBytes)
                LabeledContent("Used of that", value: used < 0.01 && used > 0
                               ? "under 1%"
                               : "\(Int((used * 100).rounded()))%")
            }
        } header: {
            Text("Usage history budget")
        } footer: {
            Text("Old usage history is folded into monthly totals when it passes this size. \(MetricCompactor.Policy.default.retainMonths) months of history is always kept, whatever the budget says.")
        }
    }

    /// What compaction has actually done, which is the only way to judge whether
    /// the policy earns its keep: a fold that destroys detail and hands back a
    /// rounding error is a bad trade, and it is invisible without this.
    @ViewBuilder
    private var compactionSection: some View {
        Section {
            if compactionRuns.isEmpty {
                Text("Never needed — the store has stayed under the budget.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(compactionRuns) { run in
                    CompactionRunRow(run: run)
                }
            }
            if let data = exportData {
                ShareLink(item: data, preview: SharePreview(StorageExport.filename())) {
                    Label("Export storage report", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Compaction")
        } footer: {
            Text("The export is counts and sizes only — no sentences, words, or names.")
        }
    }

    /// Built on demand rather than held: it fetches the whole metric history to
    /// total it, which is the one thing this screen should not do on every render.
    private var exportData: Data? {
        guard let storage else { return nil }
        return StorageExport.json(container: modelContext.container, report: storage)
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

    /// Vocabulary, excluding the silent navigation tiles pages mint for
    /// themselves (`PageLink.mint`). Those are structural plumbing, not words: a
    /// clean install already carries one per bundled page, and because they are
    /// minted with `isSystem = false` — deliberately, so scene export packages
    /// them — an untouched install otherwise reports a dozen-odd words "Added by
    /// you" before the caregiver has added anything.
    ///
    /// Filtered on `wordClass` rather than by correcting the flag: `isSystem`
    /// answers "does this ship in the bundle" for `SceneExporter`, and page links
    /// genuinely do not.
    private var words: [TileModel] {
        tiles.filter { $0.wordClass != PageLink.wordClass }
    }

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
        + dupes(caches.map { "\($0.cacheKey)|\($0.childID)" })
    }

    private func dupes(_ keys: [String]) -> Int { keys.count - Set(keys).count }
}
