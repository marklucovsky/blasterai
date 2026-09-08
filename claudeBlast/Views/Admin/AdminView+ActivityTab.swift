// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ActivityTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    var activityTab: some View {
        NavigationStack {
            List {
                // Activity-first: what the child actually said leads; AI usage,
                // and cache diagnostics are secondary, below it.
                activitySummarySection
                recentActivitySection
                activityLinksSection
                aiUsageSection
                cachePerformanceSection
                sentenceCacheSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Activity")
            .toolbar { adminDoneToolbar }
            .sheet(isPresented: $showUsageReport) { UsageReportSheet() }
        }
        .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.fill") }
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

            if topClusters.isEmpty {
                Text("No activity logged this week yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // A vertical list, not a sideways-scrolling strip of chips.
                //
                // The strip put the most-used words in the one direction a List
                // does not scroll, so reading past the third took a gesture that
                // fights the page — and on a phone only three fitted, which made
                // a ranked list look like a top three. Rows cost nothing here:
                // this section is already a list.
                //
                // It also showed the wrong unit. The chips ranked individual
                // *words* while the rows below ranked repeated *utterances*, and
                // the two sat inches apart looking like the same thing with
                // different numbers. Per-word ranking still exists, on Coverage,
                // where it is the whole point of the screen.
                Text("MOST USED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                ForEach(topClusters) { cluster in
                    clusterSnippetRow(cluster)
                }
            }
        } header: {
            Text("Activity — This Week")
        } footer: {
            Text("Counts of finalized utterances. Escalated = the child repeated the same words to insist harder.")
        }
    }

    /// How many repeated combinations the summary lists. Five rather than the
    /// three it showed when a ten-chip strip sat above it: this list is now the
    /// whole of "most used", and three reads as a podium rather than a ranking.
    private var topClusterCount: Int { 5 }

    /// The week's repeated combinations, from the same function the full log
    /// uses.
    ///
    /// A snippet that computes its own answer is a second implementation that
    /// can disagree with the screen it links to — and a caregiver who notices
    /// the two disagreeing is right to distrust both. This is literally the top
    /// of the list `ActivityLogView` renders.
    var topClusters: [ActivityCluster] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now)) else {
            return Array(ActivityGrouping.clusters(loggedUtterances).clusters.prefix(topClusterCount))
        }
        let recent = loggedUtterances.filter { $0.createdAt >= cutoff }
        return Array(ActivityGrouping.clusters(recent).clusters.prefix(topClusterCount))
    }

    /// Recent now means recent.
    ///
    /// This section was titled "Recent" and led with the week's most-repeated
    /// combinations — its own footer had to explain that it was "what was
    /// repeated this week, then the latest utterances." A header that needs a
    /// footnote to correct it is the wrong header. Repetition moved up into the
    /// summary, where it belongs beside the counts, and this shows the latest
    /// utterances and nothing else.
    @ViewBuilder
    var recentActivitySection: some View {
        Section {
            if loggedUtterances.isEmpty {
                Text("No utterances logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentUtterances.prefix(5)) { utterance in
                    recentUtteranceRow(utterance)
                }
            }
        } header: {
            Text("Recent")
        } footer: {
            Text("The latest utterances, newest first. Read-only review for therapists and partners.")
        }
    }

    /// Where the deeper screens live, in their own section.
    ///
    /// They were the tail of a list of utterances, which read as more log rows
    /// until you noticed the chevrons.
    @ViewBuilder
    var activityLinksSection: some View {
        Section {
            NavigationLink {
                ActivityLogView()
            } label: {
                Label("View full activity log", systemImage: "list.bullet.rectangle")
            }
            NavigationLink {
                CoverageView()
            } label: {
                Label("Coverage", systemImage: "chart.bar.xaxis")
            }
            NavigationLink {
                PatternsView()
            } label: {
                Label("Patterns", systemImage: "calendar.badge.clock")
            }
            Button {
                showUsageReport = true
            } label: {
                Label("Share report", systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text("Coverage asks how much of a scene is actually being used and which kinds of words go untouched; Patterns asks when the board gets reached for, and whether the range is widening.")
        }
    }

    /// Collapsed cluster row. Deliberately the same shape as the full log's, so
    /// the two screens read as one report rather than two.
    func clusterSnippetRow(_ cluster: ActivityCluster) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                LogTileStrip(tiles: tileSelections(forKeys: cluster.tileKeys))
                Spacer(minLength: 8)
                if cluster.escalatedCount > 0 {
                    Label("\(cluster.escalatedCount)", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text("\(cluster.count)×")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.blue)
            }
            Text(cluster.latestSentence.isEmpty ? "—" : cluster.latestSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    // MARK: - AI Usage
    //
    // Named "AI Usage", not "Spending". The subject is what the app DID — calls
    // made, images generated, tokens consumed — with cost as one attribute of
    // that activity. A section headed "Spending" would make a caregiver feel
    // metered for letting their child talk, which is both unpleasant and
    // backwards: talking costs fractions of a cent, and essentially all of the
    // money goes to generating art.
    //
    // Cost figures appear HERE AND NOWHERE ELSE in the app. No badges, running
    // totals, or "this will cost ~$X" hints in the editor, the art batch sheet,
    // or any child-facing surface. Authoring stays about the work, not the meter.

    var usageThisMonth: [APIUsageEvent] { UsageLedger.inMonth(apiUsageEvents) }

    @ViewBuilder
    var aiUsageSection: some View {
        let month = usageThisMonth
        let total = UsageLedger.summarize(month)
        let split = UsageLedger.speechVsAuthoring(month)
        let savings = UsageLedger.estimatedCacheSavingsMicros(events: month, cacheHits: cacheHitCount)

        Section {
            if month.isEmpty {
                Text("No AI calls this month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    StatBox(label: "Cost", value: UsageLedger.formatCost(total), color: .primary)
                    StatBox(label: "Calls", value: "\(total.calls)", color: .blue)
                    StatBox(label: "Images", value: "\(total.imageCount)", color: .purple)
                    StatBox(label: "Tokens", value: UsageLedger.formatTokens(total.totalTokens), color: .secondary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                // The comparison the public cost claim rests on. Shown as two
                // plain lines rather than a chart because the ratio is the point
                // and it's usually stark.
                VStack(alignment: .leading, spacing: 4) {
                    usageSplitRow(label: "Talking", summary: split.speech, color: .green)
                    usageSplitRow(label: "Authoring", summary: split.authoring, color: .orange)
                    if savings > 0 {
                        Text("Cache avoided about \(UsageLedger.formatUSD(micros: savings)) of generation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if total.hasUnpriced {
                        // Says plainly that the total is a floor. These rows keep
                        // zero cost forever — history is never re-priced — so
                        // without this the number silently understates.
                        Text("\(UsageLedger.pluralize(total.unpricedCalls, "call")) couldn't be priced (unknown model at the time) and count as $0. The real total is higher.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

                ForEach(UsageLedger.byCause(month), id: \.cause) { row in
                    usageCauseRow(cause: row.cause, summary: row.summary)
                }

                NavigationLink {
                    UsageDetailView(events: apiUsageEvents)
                } label: {
                    Text("View all \(apiUsageEvents.count) calls")
                        .font(.caption)
                }
            }
        } header: {
            Text("AI Usage — This Month")
        } footer: {
            Text("What this device spent against its own API key. Costs are computed from a price table last verified \(UsageLedger.pluralize(ModelPricing.daysSinceVerified(), "day")) ago; check them against your OpenAI dashboard.")
        }
    }

    func usageSplitRow(label: String, summary: UsageSummary, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.medium))
            Spacer()
            Text(UsageLedger.pluralize(summary.calls, "call"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(UsageLedger.formatCost(summary))
                .font(.caption.monospacedDigit())
        }
    }

    func usageCauseRow(cause: UsageCause, summary: UsageSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cause.label).font(.caption.weight(.medium))
                Text(UsageLedger.pluralize(summary.calls, "call")
                     + " · \(UsageLedger.formatTokens(summary.totalTokens)) tokens"
                     + (summary.imageCount > 0 ? " · " + UsageLedger.pluralize(summary.imageCount, "image") : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(UsageLedger.formatCost(summary, isFreeCause: cause.isFreeEndpoint))
                .font(.caption.monospacedDigit())
                .foregroundStyle(summary.costMicros == 0 ? .secondary : .primary)
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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
            Text("Leaves this device as a fresh install: deletes all scenes, pages, tiles, activity, cache and settings. Vocabulary reloads from the bundle. Your API key is kept, and anything in iCloud is untouched.")
        }
    }

    func performFactoryReset() {
        isResetting = true
        sentenceEngine.clearSelection()
        do {
            // BlasterScene.pages is inline JSON-encoded data (no PageModel
            // relationship), so deleting BlasterScene is sufficient.
            // Every model in the schema. The list used to stop after
            // ChildProfile, which left `LoggedUtterance` rows referencing tile
            // keys that no longer existed — an activity log full of words the
            // vocabulary had forgotten, on the very screen this button sits
            // under. `TileArtVariant` likewise outlived its tiles.
            //
            // Keep this in step with `BlasterSchemaV1`; a model added there and
            // missed here survives a reset silently.
            try modelContext.delete(model: MetricEvent.self)
            try modelContext.delete(model: SentenceCache.self)
            try modelContext.delete(model: BlasterScene.self)
            try modelContext.delete(model: TileArtVariant.self)
            try modelContext.delete(model: TileModel.self)
            try modelContext.delete(model: LoggedUtterance.self)
            try modelContext.delete(model: RecordedScript.self)
            try modelContext.delete(model: ReceivedPack.self)
            try modelContext.delete(model: ChildProfile.self)
            try modelContext.delete(model: DeviceProfile.self)
            // Device-local diagnostics. Both describe data this reset is about to
            // destroy — API spend against utterances that will no longer exist,
            // compaction runs measuring a metric log being emptied — so keeping
            // them leaves the Activity tab reporting on a device that no longer
            // has anything to report on.
            try modelContext.delete(model: APIUsageEvent.self)
            try modelContext.delete(model: CompactionRun.self)
            try modelContext.save()
        } catch {
            print("Factory reset failed: \(error)")
            isResetting = false
            return
        }
        // Every setting, not just the bootstrap flags.
        //
        // A reset is meant to leave the device as a fresh install would, and a
        // fresh install remembers nothing. Clearing only the three bootstrap keys
        // left the image set, the voice, tile size, view options and the
        // compaction budget behind — so a "reset" device came back through
        // onboarding already knowing which tile art you preferred, which is how
        // this whole class of bug got noticed.
        //
        // Wiping the persistent domain wholesale, rather than naming keys to
        // remove, means a setting added later is cleared by default. A named list
        // is a list someone forgets to extend — the same failure the model delete
        // list had.
        //
        // The registration domain is separate and survives, so the defaults
        // registered at launch (notably `icloud_enabled`) still apply.
        //
        // NOT cleared: the OpenAI key. It lives in the Keychain via
        // `OpenAIKeyVault`, and it is a credential the caregiver typed rather
        // than app state — losing it to a data reset is a worse surprise than
        // keeping it. Say so if that should change.
        let defaults = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        } else {
            defaults.removeObject(forKey: AppSettingsKey.bootstrapInstalled)
            defaults.removeObject(forKey: AppSettingsKey.bootstrapContentHash)
            defaults.removeObject(forKey: AppSettingsKey.bootstrapVersion)
        }
        _ = BootstrapLoader.loadDefaultVocabulary(context: modelContext)
        // Match cold-launch behavior: re-seed the DeviceProfile placeholder
        // and the caregiver ChildProfile so the user lands in the same state
        // as a fresh install. Without this, the Admin Profiles list comes
        // back empty after a reset and the resolver has nothing to fall
        // back to until OnboardingCommit creates a real profile.
        ProfileMigration.ensureProfilesAfterBootstrap(context: modelContext)

        // Commit the STORE before claiming in UserDefaults that it was seeded.
        //
        // The order used to be the other way round and relied on autosave for
        // the store while `markBootstrapComplete` wrote to UserDefaults
        // immediately. Two destinations, two durabilities: kill the app before
        // autosave — which is exactly what pressing Stop in Xcode after a reset
        // does — and the flag survives while the scenes do not. Next launch reads
        // "already bootstrapped", declines to seed, and the device comes up with
        // no scenes at all and no way to get any.
        //
        // A failed save leaves the flag unwritten, so the next launch seeds
        // instead of inheriting an empty store.
        do {
            try modelContext.save()
            BootstrapLoader.markBootstrapComplete()
        } catch {
            print("Factory reset: seeding failed to save — \(error). Leaving the bootstrap flag clear so the next launch re-seeds.")
        }

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
                // `TileSelection` carries no `bundleImage` — that type is
                // `Hashable` and feeds the sentence cache key, so an extra field
                // would split cache entries. It does not need one: the resolver
                // follows the alias from the word key.
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: size, height: size)
                    .background(TileColorResolver.color(for: tile).opacity(0.12))
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

