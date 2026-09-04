// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoverageView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// How much of a scene a child reaches, by part of speech.
///
/// The grammatical axis made visible. `wordClass` colours the tiles and steers
/// the sentence generator; this answers a therapist's question instead — which
/// pronouns does this scene have, has she ever pressed a question word, what
/// should be modelled next.
///
/// The unit is a SCENE, across all its pages. Never "board": in OBF and
/// CoughDrop a board is one page, and borrowing the word here would undo the
/// naming that settled it.
struct CoverageView: View {
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse)
    private var allEntries: [LoggedUtterance]
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @AppStorage(AppSettingsKey.activityRange) private var rangeRaw = ActivityLogView.Window.week.rawValue
    /// Which scene is being reported. Empty means "the active one", which is
    /// what a caregiver opening this almost always wants and survives a rename.
    @AppStorage(AppSettingsKey.coverageSceneID) private var selectedSceneID = ""

    @State private var showAll = false
    @AppStorage(AppSettingsKey.coverageBreakdown) private var breakdownRaw = Breakdown.kind.rawValue

    private var breakdown: Breakdown {
        get { Breakdown(rawValue: breakdownRaw) ?? .kind }
        nonmutating set { breakdownRaw = newValue.rawValue }
    }

    /// Two readings of the same unused words, answering different questions.
    ///
    /// By kind is the language target — what to model next. By page is the
    /// layout question — a page where almost nothing is pressed is usually
    /// buried behind a link nobody uses, not full of wrong words. Neither
    /// derives from the other, so this is a switch rather than a default.
    enum Breakdown: String, CaseIterable, Identifiable {
        case kind = "By kind"
        case page = "By page"
        var id: String { rawValue }
    }

    private var window: ActivityLogView.Window {
        get { ActivityLogView.Window(rawValue: rangeRaw) ?? .week }
        nonmutating set { rangeRaw = newValue.rawValue }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedScene: BlasterScene? {
        scenes.first { $0.sceneID == selectedSceneID && !selectedSceneID.isEmpty }
            ?? scenes.first { $0.isActive }
            ?? scenes.first
    }

    private var windowedEntries: [LoggedUtterance] {
        guard let earliest = window.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var report: CoverageReport? {
        guard let scene = selectedScene else { return nil }
        return CoverageReport.make(
            sceneName: scene.name,
            pages: scene.pages,
            inWindow: windowedEntries,
            allTime: allEntries
        )
    }

    var body: some View {
        List {
            if let report {
                scenePicker
                coverageSection(report)
                mostUsedSection(report)
                wentQuietSection(report)
                usageSection(report)
                otherScenesSection
            } else {
                ContentUnavailableView(
                    "No scene yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Coverage is measured against a scene's words.")
                )
            }
        }
        .navigationTitle("Coverage")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Scene

    @ViewBuilder
    private var scenePicker: some View {
        Section {
            Picker("Scene", selection: $selectedSceneID) {
                ForEach(scenes) { scene in
                    Text(scene.name).tag(scene.sceneID)
                }
            }
            // In the content, not the toolbar. A toolbar picker here sits
            // directly under the Admin tab bar, and in portrait the two rows of
            // pill-shaped controls read as one confusing strip — the range looks
            // like another tab.
            Picker("Period", selection: Binding(get: { window }, set: { window = $0 })) {
                ForEach(ActivityLogView.Window.allCases) { w in Text(w.rawValue).tag(w) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } footer: {
            Text("Everything below covers one scene — all of its pages together. A single figure across every scene would climb whenever you add a good one, which is the wrong direction for a coverage number.")
        }
    }

    // MARK: - Coverage

    @ViewBuilder
    private func coverageSection(_ report: CoverageReport) -> some View {
        Section {
            ForEach(report.coverage) { row in
                NavigationLink {
                    CoverageGridView(title: row.label, keys: row.keys,
                                     usedKeys: row.usedKeys, isPositional: false)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text("\(row.used) of \(row.available)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: row.usedFraction)
                            .tint(row.used == 0 ? .orange : .blue)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Kinds of words used")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distinct words reached in \(window.rawValue.lowercased()), out of what \(report.sceneName) carries. A kind the scene has none of is left out rather than shown as nought of nought.")
                // Both reconciliation notes. Without them the rows quietly fail
                // to add up to the scene and there is no way to see why.
                if report.unclassifiedCount > 0 {
                    Text("\(report.unclassifiedCount) word\(report.unclassifiedCount == 1 ? "" : "s") in this scene are not in the part-of-speech index — words added here rather than shipped — so they appear in no row above.")
                }
                if report.offSceneWordCount > 0 {
                    Text("\(report.offSceneWordCount) word\(report.offSceneWordCount == 1 ? "" : "s") said in this period are not in this scene.")
                }
            }
        }
    }

    // MARK: - Most used

    @ViewBuilder
    private func mostUsedSection(_ report: CoverageReport) -> some View {
        if !report.mostUsed.isEmpty {
            let top = report.mostUsed.first?.count ?? 1
            Section {
                ForEach(report.mostUsed) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(display(word.key))
                            Spacer()
                            Text("\(word.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(word.count) / Double(max(top, 1)))
                            .tint(.blue)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Most used")
            } footer: {
                Text("Ranked, with the count. A word cloud looks better and says less.")
            }
        }
    }

    // MARK: - Went quiet

    @ViewBuilder
    private func wentQuietSection(_ report: CoverageReport) -> some View {
        if !report.wentQuiet.isEmpty {
            Section {
                WrappingWords(words: report.wentQuiet.map(display))
            } header: {
                Text("Went quiet")
            } footer: {
                Text("Used before and not in \(window.rawValue.lowercased()). Short, and the half worth acting on — a word that was working and stopped is a different finding from one never taken up.")
            }
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private func usageSection(_ report: CoverageReport) -> some View {
        Section {
            HStack(spacing: 16) {
                CoverageRing(fraction: report.usedFraction, tint: .blue)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int((report.usedFraction * 100).rounded()))%")
                            .font(.title.monospacedDigit().weight(.bold))
                        Text("of \(report.sceneName) used")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(report.allTimeUsedCount) of \(report.sceneWordCount) words pressed at least once")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Picker("Break down", selection: Binding(get: { breakdown }, set: { breakdown = $0 })) {
                ForEach(Breakdown.allCases) { by in Text(by.rawValue).tag(by) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            switch breakdown {
            case .kind:
                ForEach(visibleKinds(report)) { row in
                    NavigationLink {
                        CoverageGridView(title: row.label, keys: row.keys,
                                         usedKeys: row.usedKeys, isPositional: false)
                    } label: {
                        usageRow(label: row.label, used: row.used,
                                 available: row.available, fraction: row.usedFraction)
                    }
                }
                if report.usageByKind.count > breakdownPreview {
                    Button(showAll ? "Show fewer" : "Show all \(report.usageByKind.count) kinds") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.subheadline)
                }
            case .page:
                ForEach(visiblePages(report)) { row in
                    NavigationLink {
                        CoverageGridView(title: pageLabel(row.pageKey), keys: row.keys,
                                         usedKeys: row.usedKeys)
                    } label: {
                        usageRow(label: pageLabel(row.pageKey), used: row.used,
                                 available: row.available, fraction: row.usedFraction)
                    }
                }
                if report.usageByPage.count > breakdownPreview {
                    Button(showAll ? "Show fewer" : "Show all \(report.usageByPage.count) pages") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Scene and page usage")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ever pressed, not just in this period — a word used last month has been used. Ranked by how much is reached, so anything at nought collects at the bottom.")
                switch breakdown {
                case .kind:
                    Text("By kind is the language question: what to model next.")
                case .page:
                    Text("By page is the layout question — a page at nought is usually buried rather than wrong. Each press counts towards the page it was made on, recorded at the press.")
                    if report.unattributedPresses > 0 {
                        Text("\(report.unattributedPresses) earlier press\(report.unattributedPresses == 1 ? "" : "es") predate page recording and count towards no page, so these figures understate use until newer history builds up.")
                    }
                }
            }
        }
    }

    private let breakdownPreview = 5

    private func visibleKinds(_ report: CoverageReport) -> [CoverageReport.CategoryCoverage] {
        showAll ? report.usageByKind : Array(report.usageByKind.prefix(breakdownPreview))
    }

    private func visiblePages(_ report: CoverageReport) -> [CoverageReport.PageCoverage] {
        showAll ? report.usageByPage : Array(report.usageByPage.prefix(breakdownPreview))
    }

    /// Page keys are lowercase identifiers (`body_health`); a caregiver reading
    /// a report should see the page, not its key.
    private func pageLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @ViewBuilder
    private func usageRow(label: String, used: Int,
                          available: Int, fraction: Double) -> some View {
        HStack(spacing: 12) {
            // Orange at nought: an untouched page or kind is the row worth
            // stopping on, and colour finds it faster than reading down a column
            // of percentages.
            CoverageRing(fraction: fraction, tint: used == 0 ? .orange : .blue)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                Text("\(used) of \(available) used")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(used == 0 ? .orange : .primary)
        }
    }

    // MARK: - Other scenes

    @ViewBuilder
    private var otherScenesSection: some View {
        let others = scenes.filter { $0.sceneID != selectedScene?.sceneID }
        if !others.isEmpty {
            Section {
                ForEach(others) { scene in
                    otherSceneRow(scene)
                }
            } header: {
                Text("Other scenes")
            } footer: {
                Text("Listed separately and never added together. A topic scene built for one outing shows low usage because the outing happened once — folding it into the everyday scene's figure would only drag that down. A scene at nought is the finding worth having.")
            }
        }
    }

    /// One collapsed scene, expandable in place.
    ///
    /// A `DisclosureGroup` rather than a link, because the question here is
    /// comparative — how does this scene compare with the one above it — and
    /// pushing a screen to answer it loses the comparison. Expanding keeps every
    /// other scene on screen.
    ///
    /// The report is built lazily, inside the expanded branch: it walks every
    /// utterance for a scene nobody has asked about yet, and a caregiver with
    /// several topic scenes would pay for all of them on every render.
    @ViewBuilder
    private func otherSceneRow(_ scene: BlasterScene) -> some View {
        DisclosureGroup {
            let report = CoverageReport.make(
                sceneName: scene.name,
                pages: scene.pages,
                inWindow: windowedEntries,
                allTime: allEntries
            )
            if report.sceneWordCount == 0 {
                Text("No vocabulary on this scene yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.usageByPage.prefix(breakdownPreview)) { row in
                    NavigationLink {
                        CoverageGridView(title: pageLabel(row.pageKey), keys: row.keys,
                                         usedKeys: row.usedKeys)
                    } label: {
                        usageRow(label: pageLabel(row.pageKey), used: row.used,
                                 available: row.available, fraction: row.usedFraction)
                    }
                }
                if report.usageByPage.count > breakdownPreview {
                    Text("+\(report.usageByPage.count - breakdownPreview) more page\(report.usageByPage.count - breakdownPreview == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            let keys = Set(CoverageReport.vocabularyKeys(of: scene.pages))
            let used = Set(allEntries.flatMap(\.tileKeys)).intersection(keys)
            let fraction = keys.isEmpty ? 0 : Double(used.count) / Double(keys.count)
            HStack(spacing: 12) {
                CoverageRing(fraction: fraction, tint: used.isEmpty ? .orange : .blue)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scene.name)
                    Text("\(used.count) of \(keys.count) used")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(used.isEmpty ? .orange : .primary)
            }
        }
    }

    private func display(_ key: String) -> String {
        tileLookup[key]?.value ?? key
    }
}

/// A ring showing one fraction. Deliberately not a `Gauge`: this needs to read
/// at 28pt beside a row as clearly as at 56pt above one.
private struct CoverageRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }

    private var lineWidth: CGFloat { 6 }
}

/// Words that wrap, for the short lists. `LazyVGrid` would column-align them,
/// which reads as a table and invites comparison down the columns that isn't
/// there.
private struct WrappingWords: View {
    let words: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(words, id: \.self) { word in
                Text(word)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

/// Minimal flow layout — place each item after the last, wrapping at the width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        CoverageView()
    }
    .previewEnvironment()
}
