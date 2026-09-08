// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PatternsView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// When a child talks, and whether their range is growing.
struct PatternsView: View {
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse)
    private var allEntries: [LoggedUtterance]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage(AppSettingsKey.activityRange) private var rangeRaw = ActivityLogView.Window.week.rawValue

    private var window: ActivityLogView.Window {
        get { ActivityLogView.Window(rawValue: rangeRaw) ?? .week }
        nonmutating set { rangeRaw = newValue.rawValue }
    }

    private var windowedEntries: [LoggedUtterance] {
        guard let earliest = window.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var report: PatternsReport {
        PatternsReport.make(inWindow: windowedEntries,
                            allTime: allEntries,
                            from: window.earliest())
    }

    var body: some View {
        List {
            periodSection
            if report.totalPresses == 0 {
                Section {
                    ContentUnavailableView(
                        "Nothing in this period",
                        systemImage: "calendar",
                        description: Text("There is no shape to show until something is said.")
                    )
                }
            } else {
                heatmapSection
                trendSection
                longestSection
            }
        }
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period

    @ViewBuilder
    private var periodSection: some View {
        let r = report
        Section {
            // In the content rather than the toolbar, for the same reason Reach
            // does it: a toolbar picker here sits directly under the Admin tab
            // bar and the two rows of pills read as one strip.
            Picker("Period", selection: Binding(get: { window }, set: { window = $0 })) {
                ForEach(ActivityLogView.Window.allCases) { w in Text(w.rawValue).tag(w) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            HStack(spacing: 0) {
                statCell("\(r.totalPresses)", "words said",
                         delta: r.previous.map { r.totalPresses - $0.presses })
                Divider()
                statCell("\(r.distinctWords)", "different words",
                         delta: r.previous.map { r.distinctWords - $0.distinctWords })
            }
        } footer: {
            if r.previous != nil {
                Text("Change is against the period immediately before this one. A therapist tracking a term needs a comparison, not just a total.")
            } else {
                Text("No earlier period to compare against yet.")
            }
        }
    }

    @ViewBuilder
    private func statCell(_ value: String, _ label: String, delta: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let delta {
                // Zero is stated, not hidden. "No change" is a finding; a blank
                // space reads as missing data.
                Label(delta == 0 ? "no change" : "\(delta > 0 ? "+" : "")\(delta)",
                      systemImage: delta > 0 ? "arrow.up" : delta < 0 ? "arrow.down" : "equal")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(delta > 0 ? .green : delta < 0 ? .orange : .secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heatmap

    @ViewBuilder
    private var heatmapSection: some View {
        let r = report
        if let hours = r.activeHours {
            let lookup = Dictionary(r.cells.map { ("\($0.weekday)-\($0.hour)", $0.presses) },
                                    uniquingKeysWith: { a, _ in a })
            Section {
                // Fixed cell size plus a horizontal scroll, rather than cells
                // that divide the available width.
                //
                // The columns come from the data: a board used from 7am to 8pm
                // gives fourteen of them. Dividing a phone's ~350pt by fourteen
                // left ~23pt per cell before the weekday gutter, and the hour
                // labels under them became unreadable — a heatmap nobody can
                // read the axes of is decoration.
                //
                // The weekday gutter sits OUTSIDE the scroll. Scrolling the
                // labels away with the cells would leave rows that cannot be
                // told apart, which is the one thing this chart is for.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 2) {
                        VStack(spacing: 3) {
                            Color.clear.frame(width: 30, height: hourLabelHeight)
                            ForEach(r.weekdays, id: \.self) { weekday in
                                Text(weekdayLabel(weekday))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: heatCell, alignment: .trailing)
                            }
                        }
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 2) {
                                    ForEach(Array(hours), id: \.self) { hour in
                                        Text(hourLabel(hour))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: heatCell, height: hourLabelHeight)
                                    }
                                }
                                ForEach(r.weekdays, id: \.self) { weekday in
                                    HStack(spacing: 2) {
                                        ForEach(Array(hours), id: \.self) { hour in
                                            let count = lookup["\(weekday)-\(hour)"] ?? 0
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(heatColor(count, busiest: r.busiestCell))
                                                .frame(width: heatCell, height: heatCell)
                                                .accessibilityLabel("\(weekdayLabel(weekday)) \(hourLabel(hour)): \(count)")
                                        }
                                    }
                                }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    HStack(spacing: 6) {
                        Text("quiet").font(.caption2).foregroundStyle(.secondary)
                        LinearGradient(colors: [heatColor(0, busiest: 1),
                                                heatColor(1, busiest: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(height: 6)
                            .clipShape(Capsule())
                        Text("busiest").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text("When words get used")
            } footer: {
                if r.weekdays.count > 1 {
                    Text("Every week in this period folded onto one, so a habit shows as a column rather than scattered dots. Worth knowing before a session gets booked."
                         + (hours.count > 8 ? " Scroll sideways for the rest of the day." : ""))
                } else {
                    // One row is an hour strip, not a heatmap, and should not be
                    // described as if it says something about weekdays.
                    Text("A single day, so this is when rather than which day. Widen the period to see whether it is a habit.")
                }
            }
        }
    }

    /// Big enough that the hour label under a column stays legible. Cells are
    /// square, so this is the width too.
    private var heatCell: CGFloat { horizontalSizeClass == .compact ? 22 : 28 }

    private var hourLabelHeight: CGFloat { 12 }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case ..<12: return "\(hour)"
        default: return "\(hour - 12)"
        }
    }

    private func heatColor(_ count: Int, busiest: Int) -> Color {
        guard count > 0, busiest > 0 else { return Color(.systemFill) }
        // Floor at 0.15 so a single press is visible rather than indistinguishable
        // from silence — the difference between "once" and "never" is the whole
        // point of a cell.
        return Color.accentColor.opacity(0.15 + 0.85 * (Double(count) / Double(busiest)))
    }

    // MARK: - Trend

    @ViewBuilder
    private var trendSection: some View {
        let days = report.days
        let peak = days.map(\.presses).max() ?? 1
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days) { day in
                        VStack(spacing: 0) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.22))
                                    .frame(height: barHeight(day.presses, peak: peak))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(height: barHeight(day.distinctWords, peak: peak))
                            }
                            .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                        .frame(height: 90, alignment: .bottom)
                        .accessibilityLabel("\(day.date.formatted(.dateTime.month().day())): \(day.presses) said, \(day.distinctWords) different")
                    }
                }
                .frame(height: 90)

                HStack {
                    Text(days.first?.date ?? .now, format: .dateTime.month(.abbreviated).day())
                    Spacer()
                    Text(days.last?.date ?? .now, format: .dateTime.month(.abbreviated).day())
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                HStack(spacing: 14) {
                    legendSwatch(Color.accentColor.opacity(0.22), "words said")
                    legendSwatch(Color.accentColor, "different words")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("How much, and how varied")
        } footer: {
            Text("Two series rather than one: volume can double while the same handful of words does all the work. The gap between the bars is the part worth watching — saying more is not the same as saying more things.")
        }
    }

    private func barHeight(_ value: Int, peak: Int) -> CGFloat {
        guard peak > 0 else { return 0 }
        return max(value > 0 ? 2 : 0, 90 * CGFloat(value) / CGFloat(peak))
    }

    @ViewBuilder
    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Longest

    @ViewBuilder
    private var longestSection: some View {
        if let longest = report.longest, longest.tileKeys.count > 1 {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(longest.sentence.isEmpty ? "—" : longest.sentence)
                    Text("\(longest.createdAt.formatted(.dateTime.weekday(.wide).hour().minute())) · \(longest.tileKeys.count) tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Longest")
            } footer: {
                Text("A high-water mark, not an average. Mean length is dragged down by every one-word answer, so it moves late; the longest thing managed moves the moment it happens.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PatternsView()
    }
    .previewEnvironment()
}
