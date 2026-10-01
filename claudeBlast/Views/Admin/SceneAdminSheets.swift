// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneAdminSheets.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UIKit

/// Set the device's optional author display name — the "contact name" that
/// travels with scenes this device creates + shares ("by Greta"). Async and
/// skippable: never captured at onboarding. Setting it backfills scenes this
/// device already authored so they immediately show the name.
struct AuthorNameField: View {
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var loaded = false

    var body: some View {
        Section {
            TextField("Your name (optional)", text: $name)
                .textInputAutocapitalization(.words)
                .onSubmit(commit)
        } header: {
            Text("Author")
        } footer: {
            Text("Optional. Scenes you create and share are labeled \u{201C}by \(name.isEmpty ? "you" : name)\u{201D} so others know who made them. Set or change it anytime.")
        }
        .onAppear {
            guard !loaded else { return }
            name = DeviceProfileStore.current(context: modelContext)?.authorName ?? ""
            loaded = true
        }
        // Persist as the user types so nothing is lost if they navigate away
        // without pressing return; the full commit (trim + backfill + save)
        // also runs on submit and when the field leaves the screen.
        .onChange(of: name) { _, newValue in
            guard loaded else { return }
            let profile = DeviceProfileStore.ensure(context: modelContext)
            profile.authorName = newValue
            profile.modifiedAt = .now
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard loaded else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != name { name = trimmed }
        let profile = DeviceProfileStore.ensure(context: modelContext)
        profile.authorName = trimmed
        profile.modifiedAt = .now
        // Backfill onto scenes THIS device authored (sceneID under our author id)
        // that don't already carry a name — so existing ones reflect it at once.
        let prefix = DeviceProfileStore.ensureAuthorID(context: modelContext) + "/"
        if let scenes = try? modelContext.fetch(FetchDescriptor<BlasterScene>()) {
            for s in scenes where s.authorName.isEmpty && s.sceneID.hasPrefix(prefix) {
                s.authorName = trimmed
            }
        }
        try? modelContext.save()
    }
}

struct SceneRow: View {
    let scene: BlasterScene
    let onActivate: () -> Void

    private var isSystemScene: Bool { scene.isSystemOwned }

    /// " · designed for iPad 12×5", or nothing when undeclared.
    private func designedSuffix(_ scene: BlasterScene) -> String {
        scene.designedLayout.map { " · designed for \($0.title)" } ?? ""
    }

    /// Provenance dot color: BlasterAI = purple, local = green, imported = orange.
    private var provenanceColor: Color {
        switch scene.provenance {
        case .firstParty: return .purple
        case .local:      return .green
        case .imported:   return .orange
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scene.name)
                        .font(.headline)
                    if scene.isDefault {
                        badge("Default", .blue)
                    }
                }
                Text("\(scene.pages.count) pages · \(scene.lastModified, style: .date)\(designedSuffix(scene))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Provenance dot (purple=BlasterAI, green=mine, orange=others) +
                // attribution + stable slug — replaces the System/Imported badges.
                HStack(spacing: 5) {
                    Circle().fill(provenanceColor).frame(width: 7, height: 7)
                    Text(scene.attribution)
                    if !scene.slug.isEmpty {
                        Text("·")
                        Text(scene.slug).monospaced()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                if isSystemScene {
                    Text("Built-in board — supplied and updated by BlasterAI. Tap to make an editable copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !scene.descriptionText.isEmpty {
                    Text(scene.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if scene.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Activate") { onActivate() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Scene Generator Sheet

/// Creating a scene, as a walk rather than a form.
///
/// Every way in — describe it to the AI, load a ready-made example, or tick
/// packs and word classes — lands in the same three closing steps:
///
///     compose / example / collections
///        └─→ review    "are these the right words?"   Cancel · Refine · Next
///        └─→ structure "what pages does it need?"     Back · Next
///        └─→ confirm   "is this the right board?"     Back · Accept
///
/// Nothing is written until Accept. Structure used to be decided *for* a
/// generated scene and not offered at all to the other two paths; making it a
/// step every path walks is what lets a scene start flat and grow deliberately.
/// The collections path skips `review` — its words were chosen by hand a screen
/// ago, and there is nothing for the AI to refine.
struct SceneGeneratorSheet: View {
    let allTiles: [TileModel]
    let apiKey: String
    let onAccept: (BlasterScene) -> Void
    let onManual: (String) -> Void

    private enum Step { case compose, manual, collections, review, structure, confirm }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .compose
    /// Which entry the scene in flight came from — see `isFromCollections`.
    @State private var origin: Step = .compose
    @State private var sessionDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var manualName = ""
    /// The scene as reviewed, before any structure. Kept so Back from confirm
    /// can re-run the structure step against the original rather than piling a
    /// second copy of everything onto a scene that already has it.
    @State private var reviewScene: GeneratedScene? = nil
    /// The scene as it will be built: `reviewScene` plus the structure step's
    /// pages. Equal to `reviewScene` when nothing was added.
    @State private var finalScene: GeneratedScene? = nil
    @State private var structure = SceneStructureResult()
    @State private var structurePlan = SceneStructurePlan()
    /// One moderation review for the whole walk. See `ScenePreviewView.review`.
    @State private var wordReview = NewWordReviewModel()
    /// How this scene was asked for — the typed brief, then any refine
    /// instructions, in order. Logged on Accept; see `AuthoringLog`.
    @State private var brief: [String] = []
    @State private var collectionsName = ""
    @State private var collectionsPlan = SceneStructurePlan()
    /// Set while previewing an unedited cached starter; drives the cache-import
    /// accept path and the "served from cache" badge. Cleared on refine.
    @State private var cachedStarter: StarterScene? = nil
    @State private var cachedPreviewImages: [String: Data] = [:]
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false

    var body: some View {
        NavigationStack {
            switch step {
            case .compose:
                generatorForm
            case .manual:
                manualForm
            case .collections:
                SceneFromCollectionsView(
                    allTiles: allTiles,
                    sceneName: $collectionsName,
                    plan: $collectionsPlan,
                    onNext: { scene, result in
                        reviewScene = scene
                        finalScene = scene
                        structure = result
                        origin = .collections
                        step = .confirm
                    },
                    onBack: { step = .compose }
                )
            case .review:
                if let reviewScene {
                    ScenePreviewView(
                        preview: reviewScene,
                        allTiles: allTiles,
                        apiKey: apiKey,
                        previewImages: cachedPreviewImages,
                        stage: .review,
                        review: wordReview,
                        onRefined: { instruction in
                            cachedStarter = nil
                            brief.append(instruction)
                        },
                        onNext: { scene in
                            self.reviewScene = scene
                            step = .structure
                        },
                        onAccept: { _ in },
                        onCancel: { dismiss() }
                    )
                    .navigationTitle("Scene Preview")
                    .navigationBarTitleDisplayMode(.inline)
                }
            case .structure:
                if let reviewScene {
                    SceneStructureStep(
                        scene: reviewScene,
                        allTiles: allTiles,
                        plan: $structurePlan,
                        onNext: { scene, result in
                            finalScene = scene
                            structure = result
                            step = .confirm
                        },
                        onBack: { step = .review }
                    )
                }
            case .confirm:
                if let finalScene {
                    ScenePreviewView(
                        preview: finalScene,
                        allTiles: allTiles,
                        apiKey: apiKey,
                        previewImages: cachedPreviewImages,
                        extraTiles: structure.createdTiles,
                        stage: .confirm,
                        review: wordReview,
                        onAccept: { buildAndAccept($0) },
                        onCancel: { step = isFromCollections ? .collections : .structure }
                    )
                    .navigationTitle("Scene Preview")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    /// Which entry produced the scene now in flight. The collections path has no
    /// review stage, so Back from confirm has to return to its own picker rather
    /// than to a structure step it never visited.
    private var isFromCollections: Bool { origin == .collections }

    private var generatorForm: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $sessionDescription)
                        .frame(minHeight: 100)
                        .disabled(isGenerating)
                } header: {
                    Text("Describe the session")
                } footer: {
                    Text("Describe the goal in plain language — the AI builds the pages, tiles, and navigation. Or tap an idea below to start.")
                        .font(.caption)
                }

                if !StarterSceneCatalog.all.isEmpty {
                    Section {
                        ForEach(StarterSceneCatalog.all) { starter in
                            Button {
                                sessionDescription = starter.prompt
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.grid.2x2.fill")
                                            .font(.caption)
                                            .foregroundStyle(.tint)
                                        Text(starter.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("Ready-made")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                            .foregroundStyle(.tint)
                                    }
                                    Text(starter.blurb)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .disabled(isGenerating)
                        }
                    } header: {
                        Text("Start from an example")
                    } footer: {
                        Text("Loads instantly as a ready-made scene. Edit the description to generate a fresh one with AI.")
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        step = .collections
                    } label: {
                        Label("Build from collections", systemImage: "square.stack.3d.up.fill")
                    }
                    .disabled(isGenerating)
                } header: {
                    Text("No AI — combine packs & classes")
                } footer: {
                    Text("Pick vocabulary packs and word classes; each becomes a page, with a home screen linking them. Instant, no key needed. You still see the board before it is saved.")
                        .font(.caption)
                }

                // (The error moved next to Generate — same reason as the New
                // Page sheet: buried in a long Form, it was below the fold
                // while the button sat in the fixed footer, so a refusal read
                // as a dead button.)

                if apiKey.isEmpty {
                    Section {
                        Text("Add an OpenAI API key in Admin to generate custom scenes. The ready-made examples above work without a key.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            if let error = generationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            Button {
                runGeneration()
            } label: {
                Group {
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Generating…")
                        }
                    } else {
                        // Demo mode always presents "Generate Scene" ✨ so a
                        // prebuilt sample reads as live AI on stage.
                        let isCached = StarterSceneCatalog.matching(sessionDescription) != nil && !demoMode
                        Label(isCached ? "Load Example" : "Generate Scene",
                              systemImage: isCached ? "square.grid.2x2.fill" : "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(sessionDescription.trimmingCharacters(in: .whitespaces).isEmpty
                      || isGenerating
                      || (apiKey.isEmpty && StarterSceneCatalog.matching(sessionDescription) == nil))
            .padding()
        }
        .navigationTitle("New Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Manual") { step = .manual }
                    .font(.subheadline)
            }
        }
    }

    private var manualForm: some View {
        Form {
            Section("Scene Name") {
                TextField("e.g. Morning routine", text: $manualName)
            }
        }
        .navigationTitle("New Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { step = .compose }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onManual(manualName)
                    dismiss()
                }
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func runGeneration() {
        let desc = sessionDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }

        // Unchanged starter prompt → preview the bundled scene (instant, no key).
        if let starter = StarterSceneCatalog.matching(desc) {
            loadCachedStarter(starter)
            return
        }

        guard !apiKey.isEmpty else { return }
        isGenerating = true
        generationError = nil
        let service = SceneGeneratorService(apiKey: apiKey)
        let tiles = allTiles
        Task {
            do {
                let result = try await service.generate(description: desc, allTiles: tiles)
                await MainActor.run { show(result, brief: [desc]) }
            } catch {
                await MainActor.run { generationError = OpenAIFailure.caregiverMessage(for: error) }
            }
            await MainActor.run { isGenerating = false }
        }
    }

    /// Show a cached starter in the shared Scene Preview (no API call). Accept
    /// imports the bundle (preserving its art); Refine turns it into a live scene.
    private func loadCachedStarter(_ starter: StarterScene) {
        guard let loaded = starter.loadPreview() else {
            generationError = "Couldn't load the example."
            return
        }
        cachedStarter = starter
        cachedPreviewImages = loaded.images
        if demoMode {
            // Demo: play the "Generating…" beat so a prebuilt sample reads as live AI.
            isGenerating = true
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                await MainActor.run {
                    show(loaded.scene, brief: [starter.prompt])
                    isGenerating = false
                }
            }
        } else {
            show(loaded.scene, brief: [starter.prompt])
        }
    }

    /// Enter the closing walk with a freshly produced scene.
    private func show(_ scene: GeneratedScene, brief: [String] = []) {
        self.brief = brief
        reviewScene = scene
        finalScene = scene
        structure = SceneStructureResult()
        structurePlan = SceneStructurePlan()
        origin = .compose
        step = .review
    }

    private func buildAndAccept(_ generated: GeneratedScene) {
        // Unedited cached starter → import the bundle (art re-attached from
        // sidecars inside importBundle, preserving the bundled pictures), then
        // lay the structure step's pages on top. The structure can't go through
        // `generated` here: the bundle import, not the preview, is what produces
        // this scene, and going the other way would cost the bundled art.
        if let starter = cachedStarter {
            if let scene = starter.importBundle(context: modelContext) {
                scene.creationSummary = "⚡ Served from cache — instant, no tokens used"
                scene.applyStructure(structure)
                logBrief(for: scene)
                try? modelContext.save()
                onAccept(scene)
            }
            dismiss()
            return
        }
        // MUST fetch rather than use `allTiles`: the structure step installs pack
        // words and mints page-link tiles, and that @Query snapshot predates them.
        // Building against the stale map would drop every nav tile it just added.
        let tiles = (try? modelContext.fetch(FetchDescriptor<TileModel>())) ?? allTiles
        let tileLookup = Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        if let scene = try? SceneBuilder.build(from: generated, tileLookup: tileLookup, context: modelContext) {
            if let tokens = generated.tokenUsage {
                scene.creationSummary = "Generated with AI · \(tokens) tokens"
            }
            logBrief(for: scene)
            try? modelContext.save()
            onAccept(scene)
        }
        dismiss()
    }

    /// Record how this scene was asked for: the original brief as the creation,
    /// then each refine instruction in the order they were given. Logged only on
    /// Accept — a brief for a scene that was cancelled describes nothing.
    private func logBrief(for scene: BlasterScene) {
        guard let first = brief.first else {
            AuthoringLog.created(.scene, key: scene.sceneID, in: modelContext)
            return
        }
        AuthoringLog.created(.scene, key: scene.sceneID, prompt: first, in: modelContext)
        for instruction in brief.dropFirst() {
            AuthoringLog.refined(.scene, key: scene.sceneID, instruction: instruction,
                                 in: modelContext)
        }
    }
}

// MARK: - Scene Preview View

struct ScenePreviewView: View {
    /// Which half of the wizard this preview is serving.
    ///
    /// The same grid does both jobs, because they show the same thing and only
    /// the question differs: *review* asks "is this the right vocabulary?" and
    /// leads to the structure step; *confirm* asks "is this the right board?"
    /// and is the last stop before the scene is saved.
    enum Stage {
        /// Cancel · Refine · Next — before structure is chosen.
        case review
        /// Back · Accept — after it is.
        case confirm
        /// Cancel · Accept — not part of the creation walk. Refining a scene
        /// that already exists previews a replacement for it; there is no
        /// structure step to go forward to and nothing behind it to go back to.
        case standalone
    }

    let allTiles: [TileModel]
    let apiKey: String
    /// Bundled art for not-yet-imported tiles (cached starter preview), key→PNG.
    let previewImages: [String: Data]
    /// Tiles created since `allTiles` was captured — pack words installed and
    /// page links minted by the structure step. A `@Query` snapshot does not
    /// refresh mid-flow, so without these the pages just added would render as
    /// empty gaps.
    let extraTiles: [TileModel]
    let stage: Stage
    /// See `review` below.
    let injectedReview: NewWordReviewModel?
    /// Called when an in-place refinement replaces the scene, with the
    /// instruction that drove it — so a cached starter preview can drop its
    /// "served from cache" identity (it's a live scene now), and so the host can
    /// keep the instruction for the authoring log.
    let onRefined: (String) -> Void
    /// Review stage only: move on to the structure step with the scene as shown.
    let onNext: (GeneratedScene) -> Void
    /// Confirm stage only: emits the scene to build.
    let onAccept: (GeneratedScene) -> Void
    /// Cancel (review) or Back (confirm) — the host decides which it is.
    let onCancel: () -> Void

    /// The scene currently shown — seeded from the initial preview and replaced
    /// in place by AI refinement.
    @State private var working: GeneratedScene
    @State private var selectedPageIndex = 0
    @State private var isRefining = false
    @State private var refineError: String? = nil
    @State private var showRefineSheet = false

    init(preview: GeneratedScene,
         allTiles: [TileModel],
         apiKey: String,
         previewImages: [String: Data] = [:],
         extraTiles: [TileModel] = [],
         stage: Stage = .standalone,
         review: NewWordReviewModel? = nil,
         onRefined: @escaping (String) -> Void = { _ in },
         onNext: @escaping (GeneratedScene) -> Void = { _ in },
         onAccept: @escaping (GeneratedScene) -> Void,
         onCancel: @escaping () -> Void) {
        self.allTiles = allTiles
        self.apiKey = apiKey
        self.previewImages = previewImages
        self.extraTiles = extraTiles
        self.stage = stage
        self.injectedReview = review
        self.onRefined = onRefined
        self.onNext = onNext
        self.onAccept = onAccept
        self.onCancel = onCancel
        // Nothing is wrapped around the scene here: `parse` adds no chrome, and
        // structure is its own step. What you see is what was produced.
        _working = State(initialValue: preview)
    }

    private var tileLookup: [String: TileModel] {
        Dictionary((allTiles + extraTiles).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 76))]

    private var currentPage: GeneratedPage {
        working.pages[min(selectedPageIndex, working.pages.count - 1)]
    }

    /// Distinct proposed-new word display names across the whole scene.
    private var newWords: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for page in working.pages {
            for tile in page.tiles where tile.isProposedNew {
                if let name = tile.displayName, seen.insert(tile.key).inserted {
                    names.append(name)
                }
            }
        }
        return names
    }

    // At-authoring moderation review of the proposed NEW words (same as Page
    // Preview). Injected by the wizard so keep/remove decisions survive the walk
    // from review to confirm: each stage is a different view, so a `@State` model
    // here would be built fresh on arrival and the caregiver's answers — the
    // whole point of the gate — would silently reset. `ownReview` covers the
    // standalone case, which has only one stage and nothing to carry.
    @State private var ownReview = NewWordReviewModel()
    private var review: NewWordReviewModel { injectedReview ?? ownReview }

    private var newWordEntries: [(key: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for page in working.pages {
            for tile in page.tiles where tile.isProposedNew {
                if let name = tile.displayName, seen.insert(tile.key).inserted { out.append((tile.key, name)) }
            }
        }
        return out
    }
    private var presentNewKeys: Set<String> { Set(newWordEntries.map(\.key)) }

    private func removeNewWord(_ key: String) {
        let newPages = working.pages.map { page -> GeneratedPage in
            var p = page
            p.tiles.removeAll { $0.key == key }
            return p
        }
        working = GeneratedScene(name: working.name, description: working.description,
                                 homePageKey: working.homePageKey, pages: newPages,
                                 newWords: working.newWords, tokenUsage: working.tokenUsage,
                                 rawContent: working.rawContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(working.name)
                    .font(.headline)
                if !working.description.isEmpty {
                    Text(working.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal)

            // New-word summary: tells the author what will be added to vocabulary.
            if !newWords.isEmpty {
                Label("Adds \(newWords.count) new word\(newWords.count == 1 ? "" : "s"): \(newWords.joined(separator: ", "))",
                      systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Page picker
            if working.pages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(working.pages.indices, id: \.self) { i in
                            let page = working.pages[i]
                            let isHome = page.key == working.homePageKey
                            Button { selectedPageIndex = i } label: {
                                HStack(spacing: 4) {
                                    Text(page.key)
                                    if isHome {
                                        Image(systemName: "house.fill")
                                            .font(.caption2)
                                    }
                                }
                                .font(.caption)
                                .fontWeight(selectedPageIndex == i ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selectedPageIndex == i
                                                   ? Color.accentColor
                                                   : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedPageIndex == i ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            } else {
                Spacer().frame(height: 12)
            }

            // Tile count
            Text("\(currentPage.tiles.count) tile\(currentPage.tiles.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            // Tile grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(currentPage.tiles, id: \.key) { genTile in
                        if let tile = tileLookup[genTile.key] {
                            GeneratedTileCell(key: tile.bundleImage, displayName: tile.displayName,
                                              wordClass: tile.wordClass, link: genTile.link,
                                              imageData: previewImages[genTile.key])
                        } else if let name = genTile.displayName, let wc = genTile.wordClass {
                            GeneratedTileCell(key: genTile.key, displayName: name,
                                              wordClass: wc, link: genTile.link, isNew: true,
                                              imageData: previewImages[genTile.key])
                                .overlay(alignment: .bottomTrailing) {
                                    NewWordReviewBadge(key: genTile.key, review: review)
                                }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .task(id: presentNewKeys) { await review.analyze(newWordEntries, apiKey: apiKey) }

            if let refineError {
                Text(refineError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            Divider()

            NewWordReviewStatus(review: review, present: presentNewKeys)

            actionBar
                .padding()
        }
        .sheet(isPresented: $showRefineSheet) {
            SceneRefineInputSheet { instruction in
                showRefineSheet = false
                runRefine(instruction)
            } onCancel: {
                showRefineSheet = false
            }
        }
    }

    /// Cancel/Back on the left, then the stage's forward move. Refine only
    /// appears at review: once structure has been added, a refine would rewrite
    /// the topical layer underneath it and the pages would no longer match the
    /// words they were built around.
    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 10) {
            switch stage {
            case .review:
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Spacer()
                Button {
                    showRefineSheet = true
                } label: {
                    if isRefining {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Refining…") }
                    } else {
                        Label("Refine", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefining || apiKey.isEmpty)
                Button("Next") { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefining || !review.canAccept(present: presentNewKeys))
            case .confirm, .standalone:
                Button(stage == .confirm ? "Back" : "Cancel",
                       role: stage == .confirm ? nil : .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(stage == .confirm ? nil : .red)
                Spacer()
                Button("Accept") { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefining || !review.canAccept(present: presentNewKeys))
            }
        }
    }

    /// Hand the scene to whichever move this stage makes.
    ///
    /// Removed and blocked words are dropped only at the end. Dropping them on
    /// the way *through* would change the word set, and the review model keys its
    /// analysis on that set — so the next stage would re-run moderation and throw
    /// away the keep/remove answers the caregiver just gave.
    private func advance() {
        switch stage {
        case .review:
            onNext(working)
        case .confirm, .standalone:
            for key in review.droppedKeys(present: presentNewKeys) { removeNewWord(key) }
            onAccept(working)
        }
    }

    private func runRefine(_ instruction: String) {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !apiKey.isEmpty else { return }
        isRefining = true
        refineError = nil
        let service = SceneRefinerService(apiKey: apiKey)
        let currentTopical = SceneNavigation.topicalTiles(of: working)
        let tiles = allTiles
        Task {
            do {
                let result = try await service.refine(instruction: text, currentTopical: currentTopical, allTiles: tiles)
                await MainActor.run {
                    working = result
                    selectedPageIndex = 0
                    onRefined(text)
                }
            } catch {
                await MainActor.run { refineError = OpenAIFailure.caregiverMessage(for: error) }
            }
            await MainActor.run { isRefining = false }
        }
    }
}

// Small modal that collects a natural-language refinement instruction for a
// scene preview ("add a fish pond and a creek"). Shared by every preview.
struct SceneRefineInputSheet: View {
    let onRefine: (String) -> Void
    let onCancel: () -> Void

    @State private var instruction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe the change…", text: $instruction, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("e.g. \u{201C}add a fish pond and a creek\u{201D}, or \u{201C}remove the tractor\u{201D}. This changes the words the scene is about; pages and core words are the next step.")
                }
            }
            .navigationTitle("Refine Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Refine") { onRefine(instruction) }
                        .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// Lightweight tile cell for AI-generated preview grids (no SwiftData dependency).
// Renders existing tiles and proposed-new words alike; `isNew` adds a badge and
// the word renders as its letter placeholder (no art until generated/added).
private struct GeneratedTileCell: View {
    let key: String
    let displayName: String
    let wordClass: String
    let link: String
    var isNew: Bool = false
    var imageData: Data? = nil

    private var isNav: Bool { !link.isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageData, let ui = UIImage(data: imageData) {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        TileImageView(key: key, wordClass: wordClass)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isNav ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .topLeading) {
                    if isNew {
                        Text("NEW")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.purple))
                            .padding(3)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

                if isNav {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, .blue)
                        .padding(3)
                }
            }

            Text(displayName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}
