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

    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var filter: Filter = .today

    /// Time-window filters group entries by day (newest first). `mostUsed` flattens entries
    /// into unique tile combinations ordered by frequency across all time.
    enum Filter: String, CaseIterable, Identifiable {
        case today    = "Today"
        case week     = "Past Week"
        case all      = "All Time"
        case mostUsed = "Most Used"
        var id: String { rawValue }

        /// Shorter labels for a compact width. Four segments share about 335pt
        /// on a phone — roughly 84pt each — and "Past Week" / "Most Used" do
        /// not fit, so iOS truncates them to ellipses that read as broken.
        ///
        /// Shortening beats collapsing into a menu here: this is the control a
        /// caregiver changes most often on this screen, and it is worth keeping
        /// one tap away. The words that get dropped ("Past", "Time") are the
        /// ones carrying the least meaning.
        var compactLabel: String {
            switch self {
            case .today:    return "Today"
            case .week:     return "Week"
            case .all:      return "All"
            case .mostUsed: return "Top Words"
            }
        }

        /// Lower bound (inclusive) for time-based filtering; nil = no bound or non-time mode.
        func earliest(now: Date = .now) -> Date? {
            let cal = Calendar.current
            switch self {
            case .today:    return cal.startOfDay(for: now)
            case .week:     return cal.date(byAdding: .day, value: -7, to: now)
            case .all, .mostUsed: return nil
            }
        }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var timeFilteredEntries: [LoggedUtterance] {
        guard let earliest = filter.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var groupedByDay: [(day: Date, entries: [LoggedUtterance])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: timeFilteredEntries) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day] ?? [])
        }
    }

    /// Distinct tile combinations across all entries, ordered by frequency (desc).
    /// Combos are bucketed by sorted-key signature so "eat apple" and "apple eat" merge.
    private var combosByFrequency: [(keys: [String], count: Int, latestSentence: String, latestAt: Date)] {
        var buckets: [String: (keys: [String], count: Int, latest: LoggedUtterance)] = [:]
        for entry in allEntries {
            let sortedKeys = entry.tileKeys.sorted()
            let bucketKey = sortedKeys.joined(separator: "+")
            if let existing = buckets[bucketKey] {
                let latest = entry.createdAt > existing.latest.createdAt ? entry : existing.latest
                buckets[bucketKey] = (existing.keys, existing.count + 1, latest)
            } else {
                buckets[bucketKey] = (sortedKeys, 1, entry)
            }
        }
        return buckets.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.latest.createdAt > rhs.latest.createdAt
            }
            .map { ($0.keys, $0.count, $0.latest.sentence, $0.latest.createdAt) }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { mode in
                        Text(hSizeClass == .compact ? mode.compactLabel : mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            switch filter {
            case .mostUsed:
                mostUsedContent
            case .today, .week, .all:
                timelineContent
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var timelineContent: some View {
        if timeFilteredEntries.isEmpty {
            emptyState
        } else {
            ForEach(groupedByDay, id: \.day) { group in
                Section(dayHeader(for: group.day)) {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mostUsedContent: some View {
        if combosByFrequency.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(Array(combosByFrequency.enumerated()), id: \.offset) { _, combo in
                    comboRow(combo)
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

    @ViewBuilder
    private func comboRow(_ combo: (keys: [String], count: Int, latestSentence: String, latestAt: Date)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                LogTileStrip(tiles: tileSelections(for: combo.keys))
                Spacer(minLength: 8)
                Text("\(combo.count)×")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.blue)
            }
            Text(combo.latestSentence.isEmpty ? "—" : combo.latestSentence)
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
