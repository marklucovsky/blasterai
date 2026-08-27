// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ActivityLogView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Therapist/partner-facing review log of finalized utterances. Read-only by design —
/// each row is what the child "said," when, plus an escalation badge when the same combo
/// was repeated. Logged at flush time in `SentenceEngine.flushActiveToHistory`.
struct ActivityLogView: View {
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse)
    private var allEntries: [LoggedUtterance]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]


    /// View options live in a toolbar menu rather than as controls in the list.
    ///
    /// They are set rarely — a caregiver picks a way of reading this and leaves
    /// it — so spending two rows of a phone screen on segmented pickers taxes
    /// every viewing for the sake of the occasional change. Persisted for the
    /// same reason.
    @AppStorage(AppSettingsKey.activityRange) private var rangeRaw = Window.today.rawValue
    @AppStorage(AppSettingsKey.activityClusterByName) private var clusterByName = true
    @AppStorage(AppSettingsKey.activityGroupByHour) private var groupByHour = false

    @State private var expanded: Set<String> = []
    @State private var showInfrequent = false

    private var window: Window {
        get { Window(rawValue: rangeRaw) ?? .today }
        nonmutating set { rangeRaw = newValue.rawValue }
    }

    /// Time-window filters group entries by day (newest first). `mostUsed` flattens entries
    /// into unique tile combinations ordered by frequency across all time.
    /// The time window. **Only** the window — this used to also carry a
    /// `.mostUsed` case, which is a *grouping*, not a span. That conflation had
    /// teeth: picking "Most Used" silently showed all-time counts no matter
    /// which window was selected, because the frequency code read every entry
    /// rather than the filtered ones. "Most used today" was not expressible.
    enum Window: String, CaseIterable, Identifiable {
        case today = "Today"
        case week  = "Past Week"
        case all   = "All Time"
        var id: String { rawValue }

        /// Lower bound (inclusive); nil = unbounded.
        func earliest(now: Date = .now) -> Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: now)
            case .week:  return cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))
            case .all:   return nil
            }
        }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var windowedEntries: [LoggedUtterance] {
        guard let earliest = window.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var groupedByDay: [(day: Date, entries: [LoggedUtterance])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: windowedEntries) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    /// Both views read the same pure functions the Admin snippet uses, so the
    /// snippet is literally the top of this list rather than a second
    /// implementation that can disagree with it.
    private var clusterResult: ActivityGrouping.ClusterResult {
        ActivityGrouping.clusters(windowedEntries)
    }

    private var hourBands: [ActivityHourBand] {
        ActivityGrouping.hourBands(windowedEntries)
    }

    var body: some View {
        List {
            if windowedEntries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Range", selection: Binding(
                        get: { window }, set: { window = $0 }
                    )) {
                        ForEach(Window.allCases) { w in
                            Text(w.rawValue).tag(w)
                        }
                    }
                    Divider()
                    Toggle("Cluster by name", isOn: $clusterByName)
                    Toggle("Group by hour", isOn: $groupByHour)
                } label: {
                    Label("View options", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    /// The two toggles compose rather than exclude, which is the whole point of
    /// having them as toggles: clustering *within* an hour band is a different
    /// and useful reading, not a third mode to pick between.
    ///
    ///     cluster off, hour off  →  plain timeline by day
    ///     cluster on,  hour off  →  what kept happening this window
    ///     cluster off, hour on   →  when did they talk
    ///     cluster on,  hour on   →  what kept happening, hour by hour
    @ViewBuilder
    private var content: some View {
        if groupByHour {
            ForEach(hourBands) { band in
                Section {
                    if clusterByName {
                        bandClusters(band)
                    } else {
                        ForEach(band.entries) { entryRow($0) }
                    }
                } header: {
                    HStack {
                        Text(band.start, format: .dateTime.weekday(.abbreviated).hour())
                        Spacer()
                        Text("\(band.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if clusterByName {
            clustersContent
        } else {
            timelineContent
        }
    }

    /// Within one hour, singletons render inline rather than behind a collapsed
    /// row. A band is already short — hiding two entries behind a disclosure
    /// costs a tap to reveal what would have fitted anyway. The collapse earns
    /// its place only at window scale, where the tail is long.
    @ViewBuilder
    private func bandClusters(_ band: ActivityHourBand) -> some View {
        let result = ActivityGrouping.clusters(band.entries)
        ForEach(result.clusters) { clusterRow($0) }
        ForEach(result.infrequent) { entryRow($0) }
    }

    // MARK: - Clusters

    @ViewBuilder
    private var clustersContent: some View {
        let result = clusterResult
        if !result.clusters.isEmpty {
            Section {
                ForEach(result.clusters) { cluster in
                    clusterRow(cluster)
                }
            } header: {
                Text("Repeated (\(result.clusters.count))")
            } footer: {
                Text("How often a combination was said, and over how long. A tally means little without its span: fifteen times in two hours is a need going unmet; fifteen times in a month is a common word.")
            }
        }

        if !result.infrequent.isEmpty {
            Section {
                Button {
                    withAnimation { showInfrequent.toggle() }
                } label: {
                    HStack {
                        Label("Said once", systemImage: "text.append")
                        Spacer()
                        Text("\(result.infrequent.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: showInfrequent ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)

                if showInfrequent {
                    ForEach(result.infrequent) { entry in
                        entryRow(entry)
                    }
                }
            } footer: {
                if result.clusters.isEmpty {
                    Text("Nothing was said more than once in this window.")
                }
            }
        }
    }

    @ViewBuilder
    private func clusterRow(_ cluster: ActivityCluster) -> some View {
        let isOpen = expanded.contains(cluster.id)
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation {
                    if isOpen { expanded.remove(cluster.id) } else { expanded.insert(cluster.id) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        LogTileStrip(tiles: tileSelections(for: cluster.tileKeys))
                        Spacer(minLength: 8)
                        Text("\(cluster.count)×")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.blue)
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        Text(spanDescription(cluster))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if cluster.escalatedCount > 0 {
                            // Escalation is a different event from recurrence —
                            // "said it louder", not "said it again" — so it gets
                            // its own count rather than being folded into the ×N.
                            Label("\(cluster.escalatedCount) escalated", systemImage: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(cluster.latestSentence.isEmpty ? "—" : cluster.latestSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(cluster.entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.createdAt, format: .dateTime.hour().minute())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if entry.repetitionCount > 0 {
                            Label("\(entry.repetitionCount)", systemImage: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(entry.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// "over 2h", "over 3 days", "at once" — the qualifier that turns a tally
    /// into a reading.
    private func spanDescription(_ cluster: ActivityCluster) -> String {
        let span = cluster.span
        if span < 60 { return "within a minute" }
        if span < 3600 { return "over \(Int(span / 60))m" }
        if span < 86_400 { return "over \(Int(span / 3600))h" }
        return "over \(Int(span / 86_400))d"
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineContent: some View {
        ForEach(groupedByDay, id: \.day) { group in
            Section(dayHeader(for: group.day)) {
                ForEach(group.entries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "No utterances yet",
                systemImage: "text.bubble",
                description: Text("Finalized sentence tray groups will appear here for review.")
            )
        }
    }

    /// Dense two-row record (matches the Admin Logs tab): tiles + time on row 1,
    /// generated sentence on row 2.
    @ViewBuilder
    private func entryRow(_ entry: LoggedUtterance) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                LogTileStrip(tiles: tileSelections(for: entry.tileKeys))
                Spacer(minLength: 8)
                if entry.repetitionCount > 0 {
                    Label("\(entry.repetitionCount)", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.sentence.isEmpty ? "(no sentence)" : entry.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func tileSelections(for keys: [String]) -> [TileSelection] {
        keys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }

    private func dayHeader(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

#Preview {
    NavigationStack {
        ActivityLogView()
    }
    .previewEnvironment()
}
