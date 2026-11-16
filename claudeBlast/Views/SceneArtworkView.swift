// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneArtworkView.swift
//  claudeBlast
//
//  A board's Artwork page: how complete its pictures are, style by style, and
//  the one place a run is started — always behind a confirmation that says
//  how many pictures, roughly what they cost and how long they take, and what
//  happens to the run if you leave.
//
//  It used to be a button at the top of the editor ("Finish art in Classic,
//  Playful 3D") that started a paid run on one tap with none of that said
//  (Mark 2026-11-15).
//

import SwiftUI
import SwiftData

/// What a run of pictures is likely to cost and take, from this device's own
/// recent art. Only an estimate: prices change and a recolor costs less than a
/// fresh drawing, so the two are kept apart.
struct ArtEstimate {
    /// Micro-dollars per picture, by kind, when there is history to go on.
    var drawMicros: Int?
    var recolorMicros: Int?
    /// Seconds per picture while a run is going.
    var secondsPerPicture: Double?

    /// Pictures closer together than this are taken to be one run; a longer
    /// gap is someone coming back later, not how long a picture took.
    static let sameRunGap: TimeInterval = 180

    static func from(_ events: [APIUsageEvent]) -> ArtEstimate {
        let art = events.filter { $0.cause == .tileImageGenerate && !$0.isAggregate && $0.imageCount > 0 }
        func perPicture(_ endpoint: String) -> Int? {
            let rows = art.filter { $0.endpoint.hasSuffix(endpoint) }
            let pictures = rows.reduce(0) { $0 + $1.imageCount }
            guard pictures > 0 else { return nil }
            return rows.reduce(0) { $0 + $1.costMicros } / pictures
        }
        let times = art.map(\.timestamp).sorted()
        let gaps = zip(times, times.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .filter { $0 > 0 && $0 < sameRunGap }
            .sorted()
        return ArtEstimate(drawMicros: perPicture("/images/generations"),
                           recolorMicros: perPicture("/images/edits"),
                           secondsPerPicture: gaps.isEmpty ? nil : gaps[gaps.count / 2])
    }

    /// "About 24 pictures, about $1.10, about 8 minutes." Says plainly when
    /// there is nothing on this device to estimate from yet.
    func line(draws: Int, recolors: Int) -> String {
        let pictures = draws + recolors
        var parts = ["Up to \(pictures) picture\(pictures == 1 ? "" : "s")"]
        let draw = drawMicros ?? recolorMicros
        let recolor = recolorMicros ?? drawMicros
        if let draw, let recolor {
            let dollars = Double(draw * draws + recolor * recolors) / 1_000_000
            parts.append(dollars < 0.01 ? "under a cent" : "about \(dollars.formatted(.currency(code: "USD")))")
        }
        if let secondsPerPicture {
            let minutes = Int((Double(pictures) * secondsPerPicture / 60).rounded(.up))
            parts.append(minutes <= 1 ? "about a minute" : "about \(minutes) minutes")
        }
        var text = parts.joined(separator: ", ") + "."
        if draw == nil {
            text += " Cost and time will be estimated once this device has made some pictures."
        }
        return text
    }
}

struct SceneArtworkView: View {
    let scene: BlasterScene

    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var imageResolver
    @Environment(SceneArtCoordinator.self) private var sceneArtCoordinator
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Query(sort: \APIUsageEvent.timestamp, order: .reverse) private var usage: [APIUsageEvent]

    @State private var pending: Job?
    @State private var isShowingRun = false
    @State private var isAddingKey = false

    /// A run waiting on its confirmation.
    private enum Job: Identifiable {
        case newWords([TileModel])
        case style(SceneImageBatch.StyleCoverage)
        case all([SceneImageBatch.StyleCoverage])

        var id: String {
            switch self {
            case .newWords: "new"
            case .style(let c): "style-" + c.id
            case .all: "all"
            }
        }
    }

    private var controller: SceneImageBatchController { sceneArtCoordinator.controller(for: scene.id) }
    private var apiKey: String { OpenAIKeyVault.currentKey() ?? "" }
    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var estimate: ArtEstimate { .from(Array(usage.prefix(400))) }

    var body: some View {
        _ = imageResolver.revision
        let lookup = tileLookup
        let coverage = SceneImageBatch.coverage(in: scene, tileLookup: lookup, resolver: imageResolver)
        let newWords = SceneImageBatch.tilesNeedingArt(in: scene, tileLookup: lookup, resolver: imageResolver)
        let gaps = coverage.filter { !$0.isComplete }
        return List {
            Section {
                LabeledContent("Styles Complete", value: "\(coverage.count - gaps.count) of \(coverage.count)")
                if !newWords.isEmpty {
                    LabeledContent("Words Without a Picture", value: "\(newWords.count)")
                }
                if controller.isActive {
                    Button { isShowingRun = true } label: {
                        Label(controller.phase == .paused
                              ? "Paused, \(controller.completed) of \(controller.total) done"
                              : "Making pictures, \(controller.completed) of \(controller.total) done",
                              systemImage: controller.phase == .paused ? "pause.circle" : "hourglass")
                    }
                }
            }
            if apiKey.isEmpty, !(gaps.isEmpty && newWords.isEmpty) {
                Section {
                    Button("Add an AI Key") { isAddingKey = true }
                } footer: {
                    Text("Pictures are made with your OpenAI key.")
                }
            }
            if !newWords.isEmpty {
                Section("New Words") {
                    startRow("Draw \(newWords.count) new word\(newWords.count == 1 ? "" : "s")",
                             detail: "In the style you\u{2019}re using now",
                             job: .newWords(newWords))
                }
            }
            Section("Styles") {
                ForEach(coverage) { entry in
                    if entry.isComplete {
                        LabeledContent(entry.style.displayName) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    } else {
                        startRow("Finish \(entry.style.displayName)", detail: detail(entry), job: .style(entry))
                    }
                }
                if gaps.count > 1 {
                    startRow("Finish All \(gaps.count) Styles", detail: nil, job: .all(gaps))
                }
            }
            Section {
            } footer: {
                Text("Pictures are made one at a time. A run keeps going while you use BlasterAI, the board included; leaving the app pauses it until you come back. Pause or cancel it here.")
            }
        }
        .navigationTitle("Artwork")
        .confirmationDialog(pending.map(title) ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible, presenting: pending) { job in
            Button("Start") { start(job) }
            Button("Cancel", role: .cancel) {}
        } message: { job in
            let (draws, recolors) = pictures(job)
            Text(estimate.line(draws: draws, recolors: recolors)
                 + " It keeps going while you use the app; leaving the app pauses it.")
        }
        .sheet(isPresented: $isShowingRun) { SceneImageBatchSheet(controller: controller) }
        .sheet(isPresented: $isAddingKey) { APIKeyEntrySheet() }
    }

    private func startRow(_ title: String, detail: String?, job: Job) -> some View {
        Button { pending = job } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(apiKey.isEmpty || controller.isActive)
    }

    /// Counts of **words**, named by the work: a recolor keeps the figure, a
    /// fresh drawing does not, and they cost differently.
    private func detail(_ entry: SceneImageBatch.StyleCoverage) -> String {
        var parts: [String] = []
        if !entry.needsBase.isEmpty {
            parts.append("\(entry.needsBase.count) word\(entry.needsBase.count == 1 ? "" : "s") to draw")
        }
        if !entry.needsVariants.isEmpty {
            parts.append("\(entry.needsVariants.count) to recolor")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func title(_ job: Job) -> String {
        switch job {
        case .newWords(let words): "Draw \(words.count) new word\(words.count == 1 ? "" : "s")?"
        case .style(let entry): "Finish \(entry.style.displayName)?"
        case .all(let gaps): "Finish all \(gaps.count) styles?"
        }
    }

    /// Pictures a job may make, as (fresh drawings, recolors). An upper bound:
    /// a word without art in a style is drawn once and recolored into the
    /// style's other variants; a word missing variants is only recolored.
    private func pictures(_ job: Job) -> (Int, Int) {
        func count(_ entry: SceneImageBatch.StyleCoverage) -> (Int, Int) {
            let extra = max(entry.style.variants.count - 1, 0)
            return (entry.needsBase.count,
                    entry.needsBase.count * extra + entry.needsVariants.count * max(extra, 1))
        }
        switch job {
        case .newWords(let words): return (words.count, 0)
        case .style(let entry): return count(entry)
        case .all(let gaps):
            return gaps.map(count).reduce((0, 0)) { ($0.0 + $1.0, $0.1 + $1.1) }
        }
    }

    private func start(_ job: Job) {
        switch job {
        case .newWords(let words):
            controller.start(tiles: words, apiKey: apiKey, context: modelContext, resolver: imageResolver)
        case .style(let entry):
            controller.start(tiles: entry.needsBase + entry.needsVariants, mode: .completeStyle(entry.style),
                             apiKey: apiKey, context: modelContext, resolver: imageResolver)
        case .all(let gaps):
            controller.startSweep(gaps.map { ($0.style, $0.needsBase + $0.needsVariants) },
                                  apiKey: apiKey, context: modelContext, resolver: imageResolver)
        }
        isShowingRun = true
    }
}
