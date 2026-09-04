// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageReportSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Build and share the usage report.
///
/// Sits behind `AdminGate` because Admin does — this file can contain a child's
/// speech, and the plan for 4E is explicit that it must be a deliberate
/// caregiver action, plainly labelled, never automatic and never in the
/// background.
struct UsageReportSheet: View {
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse)
    private var allEntries: [LoggedUtterance]
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @Environment(ChildProfileResolver.self) private var profileResolver
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKey.activityRange) private var rangeRaw = ActivityLogView.Window.week.rawValue

    @State private var options = UsageReportOptions()
    @State private var rendered: URL?
    @State private var isRendering = false
    @State private var error: String?

    private var window: ActivityLogView.Window {
        get { ActivityLogView.Window(rawValue: rangeRaw) ?? .week }
        nonmutating set { rangeRaw = newValue.rawValue }
    }

    private var windowedEntries: [LoggedUtterance] {
        guard let earliest = window.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var activeScene: BlasterScene? {
        scenes.first { $0.isActive } ?? scenes.first
    }

    private var report: UsageReport {
        UsageReport.make(
            childName: profileResolver.active?.displayName ?? "",
            scene: activeScene,
            periodLabel: window.rawValue,
            inWindow: windowedEntries,
            allTime: allEntries,
            tileLookup: Dictionary(allTiles.map { ($0.key, $0) },
                                   uniquingKeysWith: { first, _ in first }),
            from: window.earliest(),
            includesUtterances: options.includeUtterances)
    }

    var body: some View {
        NavigationStack {
            Form {
                periodSection
                contentSection
                sensitivitySection
                shareSection
            }
            .navigationTitle("Share report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn’t build the report", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    @ViewBuilder
    private var periodSection: some View {
        Section {
            Picker("Period", selection: Binding(get: { window }, set: { window = $0 })) {
                ForEach(ActivityLogView.Window.allCases) { w in Text(w.rawValue).tag(w) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } footer: {
            Text("The same period the Activity screens are showing.")
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        Section("Include") {
            Toggle("When words get used", isOn: $options.includePatterns)
            Toggle("How much of the board is used", isOn: $options.includeCoverage)
            Picker("Paper", selection: $options.paper) {
                ForEach(PaperSize.all) { Text($0.displayName).tag($0) }
            }
        }
    }

    /// The one toggle that changes what the file *is*, kept apart from the ones
    /// that change what it shows.
    @ViewBuilder
    private var sensitivitySection: some View {
        Section {
            Toggle(isOn: $options.includeUtterances) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include what was said")
                    Text("Every sentence, with its time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if options.includeUtterances {
                Label {
                    Text("This file will contain \(childName)’s own words. Send it only to someone who should read them — a therapist, or a partner in \(childName)’s care.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("The child’s speech")
        } footer: {
            Text(options.includeUtterances
                 ? "Without this the report still shows how often, when, which words and how much of the board — everything except the sentences."
                 : "Off. The report shows how often, when, which words and how much of the board, but not what was said.")
        }
    }

    private var childName: String {
        let name = profileResolver.active?.displayName ?? ""
        return name.isEmpty ? "the child" : name
    }

    @ViewBuilder
    private var shareSection: some View {
        Section {
            if let rendered {
                ShareLink(item: rendered) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    build()
                } label: {
                    HStack {
                        Label(isRendering ? "Building…" : "Build report",
                              systemImage: "doc.richtext")
                        Spacer()
                        if isRendering { ProgressView() }
                    }
                }
                .disabled(isRendering || allEntries.isEmpty)
            }
        } footer: {
            if allEntries.isEmpty {
                Text("There is no activity to report yet.")
            } else if rendered != nil {
                Text("Rebuilt whenever you change an option above.")
            }
        }
        .onChange(of: options) { _, _ in rendered = nil }
        .onChange(of: rangeRaw) { _, _ in rendered = nil }
    }

    private func build() {
        isRendering = true
        let snapshot = report
        let opts = options
        Task {
            // Off the main actor: a long window renders every session, and the
            // sheet should not freeze while it does. This is the lesson from tile
            // export, where a synchronous build read as a hang.
            let data = await Task.detached(priority: .userInitiated) {
                await UsageReportRenderer.render(snapshot, options: opts)
            }.value
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(snapshot.suggestedFileName)
                try data.write(to: url, options: .atomic)
                rendered = url
            } catch {
                self.error = error.localizedDescription
            }
            isRendering = false
        }
    }
}
