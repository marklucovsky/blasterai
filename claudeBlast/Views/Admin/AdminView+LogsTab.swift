// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+LogsTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    var logsTab: some View {
        NavigationStack {
            List {
                // Activity-first: what the child actually said leads; cache and
                // promoted-tile diagnostics are secondary, further down.
                activitySummarySection
                recentActivitySection
                cachePerformanceSection
                promotedTilesSection
                sentenceCacheSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Logs")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Logs", systemImage: "list.bullet.rectangle.fill") }
    }

    // MARK: - Activity summary (this week)

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
    private var oneWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    var utterancesThisWeek: [LoggedUtterance] {
        loggedUtterances.filter { $0.createdAt >= oneWeekAgo }
    }
    var utterancesTodayCount: Int {
        loggedUtterances.count { $0.createdAt >= startOfToday }
    }
    /// Utterances this week where the child repeated the same combo to insist
    /// harder — the volume-knob signal, now that escalation works.
    var escalatedThisWeekCount: Int {
        utterancesThisWeek.count { $0.repetitionCount > 0 }
    }
    /// Most-tapped tiles this week, highest first. Carries the key + wordClass
    /// so the chip can render the real tile image.
    var topTilesThisWeek: [(key: String, value: String, wordClass: String, count: Int)] {
        var counts: [String: Int] = [:]
        for u in utterancesThisWeek {
            for key in u.tileKeys { counts[key, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (key: $0.key,
                    value: tileLookup[$0.key]?.value ?? $0.key,
                    wordClass: tileLookup[$0.key]?.wordClass ?? "",
                    count: $0.value) }
    }
    var recentUtterances: [LoggedUtterance] { Array(loggedUtterances.prefix(5)) }

    func tileSelections(forKeys keys: [String]) -> [TileSelection] {
        keys.compactMap { tileLookup[$0].map(TileSelection.init(from:)) }
    }

    @ViewBuilder
    var activitySummarySection: some View {
        let week = utterancesThisWeek
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("UTTERANCES — WHAT THE CHILD SAID")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    StatBox(label: "Today", value: "\(utterancesTodayCount)", color: .primary)
                    StatBox(label: "This Week", value: "\(week.count)", color: .blue)
                    StatBox(label: "Escalated", value: "\(escalatedThisWeekCount)", color: .orange)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if topTilesThisWeek.isEmpty {
                Text("No activity logged this week yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MOST USED")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(topTilesThisWeek.enumerated()), id: \.offset) { _, item in
                                MostUsedTileChip(key: item.key, value: item.value,
                                                 wordClass: item.wordClass, count: item.count)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            Text("Activity — This Week")
        } footer: {
            Text("Counts of finalized utterances. Escalated = the child repeated the same words to insist harder.")
        }
    }

    @ViewBuilder
    var recentActivitySection: some View {
        Section {
            if recentUtterances.isEmpty {
                Text("No utterances logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentUtterances) { utterance in
                    recentUtteranceRow(utterance)
                }
            }
            NavigationLink {
                ActivityLogView()
            } label: {
                Label("View full activity log", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text("Recent")
        } footer: {
            Text("Finalized utterances from the sentence tray. Read-only review for therapists and partners.")
        }
    }

    /// Dense two-row record: row 1 the tapped tiles (horizontal chips) + time,
    /// row 2 the generated sentence (single line).
    func recentUtteranceRow(_ utterance: LoggedUtterance) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                LogTileStrip(tiles: tileSelections(forKeys: utterance.tileKeys))
                Spacer(minLength: 8)
                if utterance.repetitionCount > 0 {
                    Label("\(utterance.repetitionCount)", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(utterance.createdAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(utterance.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // MARK: - Promoted tiles helpers

    func promotedTileRow(_ entry: SentenceCache) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                LogTileStrip(tiles: tileSelections(for: entry))
                Spacer(minLength: 8)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text("\(entry.hitCount) hits")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // MARK: - Cache Stats

    var cacheStatsView: some View {
        let hits = cacheHitCount
        let misses = cacheMissCount
        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) * 100 : 0
        let missRate = total > 0 ? Double(misses) / Double(total) * 100 : 0

        return Group {
            HStack {
                StatBox(label: "Lookups", value: "\(total)", color: .primary)
                StatBox(label: "Hits", value: "\(hits)", color: .green)
                StatBox(label: "Misses", value: "\(misses)", color: .orange)
            }

            HStack {
                StatBox(label: "Hit Rate", value: String(format: "%.1f%%", hitRate), color: .green)
                StatBox(label: "Miss Rate", value: String(format: "%.1f%%", missRate), color: .orange)
                StatBox(label: "Entries", value: "\(cacheEntries.count)", color: .blue)
            }

            if total == 0 {
                Text("No lookups recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func deleteCacheEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cacheEntries[index])
        }
        try? modelContext.save()
    }

    func flushAllCache() {
        for entry in cacheEntries {
            modelContext.delete(entry)
        }
        // Clear cache-related metric events so stats reset with the cache
        for event in allMetricEvents where
            (event.subjectType == "cache" && event.eventType == .hit) ||
            (event.subjectType == "sentence" && event.eventType == .used) {
            modelContext.delete(event)
        }
        try? modelContext.save()
    }

    /// Unpinned entries whose `keyVersion` no longer matches the current
    /// `CacheKeyPolicy` — i.e. sentences left stale by a model/prompt-version
    /// bump. Surfaces the "Clear Stale" affordance only when there's work to do.
    var staleCacheCount: Int {
        cacheEntries.filter { !$0.isPinned && $0.keyVersion != CacheKeyPolicy.versionToken }.count
    }

    /// On-demand stale sweep: reclaim version-mismatched entries without waiting
    /// for a relaunch or TTL. Delegates to the manager so the staleness rule
    /// lives in one place.
    func pruneStaleCache() {
        let removed = SentenceCacheManager(modelContext: modelContext).pruneStaleVersions()
        if removed > 0 {
            try? modelContext.save()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    var cachePerformanceSection: some View {
        Section {
            cacheStatsView
        } header: {
            Text("Cache Performance")
        }
    }

    @ViewBuilder
    var promotedTilesSection: some View {
        Section {
            if promotedCandidates.isEmpty {
                Text("No promoted tiles yet — use the same tile combo 3+ times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(promotedCandidates.prefix(5)) { entry in
                    promotedTileRow(entry)
                }
                if promotedCandidates.count > 5 {
                    NavigationLink {
                        PromotedTilesDetailView(entries: promotedCandidates, tileLookup: tileLookup)
                    } label: {
                        Text("View All (\(promotedCandidates.count))")
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Promoted Tiles (\(promotedCandidates.count))")
        }
    }

    @ViewBuilder
    var sentenceCacheSection: some View {
        Section {
            NavigationLink {
                CacheDetailView(entries: cacheEntries, onDelete: deleteCacheEntries, onFlush: flushAllCache)
            } label: {
                Text("View \(cacheEntries.count) entries")
            }
            .disabled(cacheEntries.isEmpty)
        } header: {
            HStack {
                Text("Sentence Cache (\(cacheEntries.count))")
                Spacer()
                if staleCacheCount > 0 {
                    Button("Clear Stale (\(staleCacheCount))") {
                        pruneStaleCache()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
                if !cacheEntries.isEmpty {
                    Button("Flush All", role: .destructive) {
                        flushAllCache()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    var developerSection: some View {
        Section("Developer") {
            if isResetting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Resetting…").foregroundStyle(.secondary)
                }
            } else {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Factory Reset", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .confirmationDialog("Factory Reset", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset All Data", role: .destructive) { performFactoryReset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes all scenes, pages, tiles, and cache. Vocabulary reloads from the bundle.")
        }
    }

    func performFactoryReset() {
        isResetting = true
        sentenceEngine.clearSelection()
        do {
            // BlasterScene.pages is inline JSON-encoded data (no PageModel
            // relationship), so deleting BlasterScene is sufficient.
            try modelContext.delete(model: MetricEvent.self)
            try modelContext.delete(model: SentenceCache.self)
            try modelContext.delete(model: BlasterScene.self)
            try modelContext.delete(model: TileModel.self)
            try modelContext.delete(model: ChildProfile.self)
            try modelContext.delete(model: DeviceProfile.self)
            try modelContext.save()
        } catch {
            print("Factory reset failed: \(error)")
            isResetting = false
            return
        }
        // Clear all bootstrap-state flags so the next loadDefaultVocabulary
        // call writes fresh hash + installed flag via markBootstrapComplete.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettingsKey.bootstrapInstalled)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapContentHash)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapVersion)
        _ = BootstrapLoader.loadDefaultVocabulary(context: modelContext)
        BootstrapLoader.markBootstrapComplete()
        // Match cold-launch behavior: re-seed the DeviceProfile placeholder
        // and the Sandbox ChildProfile so the user lands in the same state
        // as a fresh install. Without this, the Admin Profiles list comes
        // back empty after a reset and the resolver has nothing to fall
        // back to until OnboardingCommit creates a real profile.
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: modelContext,
            seedLegacy: false
        )
        profileResolver.refresh()
        isResetting = false
    }
    #endif
}

// MARK: - Log tile chips

/// A horizontal strip of small tile images — the dense, scannable replacement
/// for the 2×2 `TileGridIcon` cube in the Logs list. Matches the horizontal
/// tile format used in the trays.
struct LogTileStrip: View {
    let tiles: [TileSelection]
    var maxCount: Int = 6
    private let size: CGFloat = 26

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tiles.prefix(maxCount).enumerated()), id: \.offset) { _, tile in
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: size, height: size)
                    .background(wordClassColor(tile.wordClass).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if tiles.count > maxCount {
                Text("+\(tiles.count - maxCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A "most used" chip: the real tile image + its word + a ×N usage count.
struct MostUsedTileChip: View {
    let key: String
    let value: String
    let wordClass: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            TileImageView(key: key, wordClass: wordClass)
                .frame(width: 26, height: 26)
                .background(wordClassColor(wordClass).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(value)
                .font(.caption)
                .lineLimit(1)
            Text("×\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}
