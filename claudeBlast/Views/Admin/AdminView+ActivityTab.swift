// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ActivityTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    /// Settings › Activity: what was said. AI usage, the cache and
    /// authoring history are diagnostics, and live under Advanced.
    /// Settings › Activity: the week in three numbers, then the screens that
    /// say more. What was said, and how often, is the log one row down — the
    /// page used to show a page of it before you could see what else was here.
    var activityPage: some View {
        List {
            Section("This Week") {
                LabeledContent("Messages Today", value: "\(utterancesTodayCount)")
                LabeledContent("Messages This Week", value: "\(utterancesThisWeek)")
                LabeledContent("Repeated to Insist", value: "\(escalatedThisWeekCount)")
            }
            Section {
                NavigationLink("Activity Log") { ActivityLogView() }
                NavigationLink("Coverage") { CoverageView() }
                NavigationLink("Patterns") { PatternsView() }
                NavigationLink("How Boards Were Made") {
                    List { authoringSection }
                        .textSelection(.enabled)
                        .navigationTitle("How Boards Were Made")
                }
            }
            Section {
                Button("Share Report") { showUsageReport = true }
            }
        }
        .navigationTitle("Activity")
    }

    // MARK: - Authoring history

    /// How the boards on this device came to exist, newest first — and, when AI
    /// wrote one, the words that asked for it.
    ///
    /// The text is selectable on purpose. A brief that worked is worth reusing,
    /// and a prompt you can read but not copy makes you retype it. This is the
    /// only place the wording is kept: it is deliberately **not** on the scene,
    /// because a prompt is the likeliest place a child's name or diagnosis lands
    /// and a scene syncs and gets shared. See `MetricEvent.detail`.
    private var authoringEvents: [MetricEvent] {
        allMetricEvents
            .filter { $0.subjectType == AuthoringLog.Subject.scene.rawValue
                   || $0.subjectType == AuthoringLog.Subject.page.rawValue }
            .sorted { $0.timestamp > $1.timestamp }
    }

    @ViewBuilder
    var authoringSection: some View {
        let events = Array(authoringEvents.prefix(authoringRowLimit))
        if !events.isEmpty {
            Section {
                ForEach(events, id: \.id) { event in
                    authoringRow(event)
                }
            } header: {
                Text("How these boards were made")
            } footer: {
                Text("Stays on this device — prompts are never synced and never travel inside a shared board. Select the text to reuse it, or tap the copy button.")
            }
        }
    }

    /// Enough to cover a working session without turning the tab into a log.
    private var authoringRowLimit: Int { 12 }

    @ViewBuilder
    private func authoringRow(_ event: MetricEvent) -> some View {
        let isScene = event.subjectType == AuthoringLog.Subject.scene.rawValue
        let verb = event.eventType == .refined
            ? "Refined"
            : (event.isAuthoringRecord ? "Generated" : "Created")
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isScene ? "square.grid.2x2.fill" : "doc.text.fill")
                    .font(.caption2)
                    .foregroundStyle(event.eventType == .refined ? Color.purple : Color.accentColor)
                Text("\(verb) \(isScene ? "scene" : "page")")
                    .font(.caption.weight(.semibold))
                Text(authoringName(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(event.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if event.isAuthoringRecord {
                    // A button rather than a context menu: a `contextMenu` on the
                    // row claims the long press, which is the gesture that starts
                    // a text selection — so the menu and the selectable text
                    // cancelled each other out. `.borderless` keeps the tap on the
                    // button instead of the whole row.
                    Button {
                        UIPasteboard.general.string = event.detail
                        copiedEventID = event.id
                    } label: {
                        Image(systemName: copiedEventID == event.id
                              ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy prompt")
                }
            }
            if event.isAuthoringRecord {
                Text(event.detail)
                    .font(.callout)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    /// The scene's current name, or the key if it has been deleted since — the
    /// log outlives what it describes.
    private func authoringName(for event: MetricEvent) -> String {
        if event.subjectType == AuthoringLog.Subject.scene.rawValue,
           let scene = scenes.first(where: { $0.sceneID == event.subjectKey }) {
            return scene.name
        }
        return PageNaming.displayName(event.subjectKey)
    }

    // MARK: - Activity (this week)

    private var oneWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    var utterancesThisWeek: Int {
        loggedUtterances.count { $0.createdAt >= oneWeekAgo }
    }
    var utterancesTodayCount: Int {
        let start = Calendar.current.startOfDay(for: .now)
        return loggedUtterances.count { $0.createdAt >= start }
    }
    /// Utterances this week where the child repeated the same words to insist
    /// harder.
    var escalatedThisWeekCount: Int {
        loggedUtterances.count { $0.createdAt >= oneWeekAgo && $0.repetitionCount > 0 }
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
            try modelContext.delete(model: LoggedNavigation.self)
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

