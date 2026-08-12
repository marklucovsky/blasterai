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
                Text("\(scene.pages.count) pages · \(scene.lastModified, style: .date)")
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

struct SceneGeneratorSheet: View {
    let allTiles: [TileModel]
    let apiKey: String
    let onAccept: (BlasterScene) -> Void
    let onManual: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var sessionDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var preview: GeneratedScene? = nil
    @State private var manualName = ""
    @State private var showManual = false
    /// Set while previewing an unedited cached starter; drives the cache-import
    /// accept path and the "served from cache" badge. Cleared on refine.
    @State private var cachedStarter: StarterScene? = nil
    @State private var cachedPreviewImages: [String: Data] = [:]
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false

    var body: some View {
        NavigationStack {
            if let preview {
                ScenePreviewView(
                    preview: preview,
                    allTiles: allTiles,
                    apiKey: apiKey,
                    profile: .focused,
                    previewImages: cachedPreviewImages,
                    onRefined: { cachedStarter = nil },
                    onAccept: { scene, focused in buildAndAccept(scene, focused: focused) },
                    onCancel: { dismiss() }
                )
                .navigationTitle("Scene Preview")
                .navigationBarTitleDisplayMode(.inline)
            } else if showManual {
                manualForm
            } else {
                generatorForm
            }
        }
    }

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
                    NavigationLink {
                        SceneFromCollectionsView(allTiles: allTiles) { scene in
                            onAccept(scene)
                            dismiss()
                        }
                    } label: {
                        Label("Build from collections", systemImage: "square.stack.3d.up.fill")
                    }
                    .disabled(isGenerating)
                } header: {
                    Text("No AI — combine packs & classes")
                } footer: {
                    Text("Pick vocabulary packs and word classes; each becomes a page, with a home screen linking them. Instant, no key needed.")
                        .font(.caption)
                }

                if let error = generationError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if apiKey.isEmpty {
                    Section {
                        Text("Add an OpenAI API key in Admin to generate custom scenes. The ready-made examples above work without a key.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

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
                Button("Manual") { showManual = true }
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
                Button("Back") { showManual = false }
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
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { generationError = error.localizedDescription }
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
                    preview = loaded.scene
                    isGenerating = false
                }
            }
        } else {
            preview = loaded.scene
        }
    }

    private func buildAndAccept(_ generated: GeneratedScene, focused: Bool) {
        // Unedited cached starter → import the bundle (art re-attached from
        // sidecars inside importBundle, preserving the bundled pictures).
        if let starter = cachedStarter {
            if let scene = starter.importBundle(context: modelContext) {
                // Starter bundles are authored Focused — flag the imported scene to
                // match, or the editor's Focused toggle shows Off over a focused
                // board (and toggling it re-scaffolds to full).
                scene.isFocused = focused
                scene.creationSummary = "⚡ Served from cache — instant, no tokens used"
                onAccept(scene)
            }
            dismiss()
            return
        }
        let tileLookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        if let scene = try? SceneBuilder.build(from: generated, tileLookup: tileLookup, context: modelContext) {
            // The previewed `generated` scene was already scaffolded at this
            // profile, so the flag matches the pages the board will show.
            scene.isFocused = focused
            if let tokens = generated.tokenUsage {
                scene.creationSummary = "Generated with AI · \(tokens) tokens"
            }
            onAccept(scene)
        }
        dismiss()
    }
}

// MARK: - Scene Preview View

struct ScenePreviewView: View {
    let allTiles: [TileModel]
    let apiKey: String
    /// Board profile used when an in-place refinement re-scaffolds the scene.
    let profile: SceneNavigation.Profile
    /// Bundled art for not-yet-imported tiles (cached starter preview), key→PNG.
    let previewImages: [String: Data]
    /// Called when an in-place refinement replaces the scene (so a cached starter
    /// preview can drop its "served from cache" identity — it's now a live scene).
    let onRefined: () -> Void
    /// Emits the accepted scene plus whether the Focused board profile is on.
    let onAccept: (GeneratedScene, Bool) -> Void
    let onCancel: () -> Void

    /// The scene currently shown — seeded from the initial preview and replaced
    /// in place by AI refinement.
    @State private var working: GeneratedScene
    @State private var selectedPageIndex = 0
    @State private var isRefining = false
    @State private var refineError: String? = nil
    @State private var showRefineSheet = false
    /// Focused board profile: topical tiles alone (template removed) vs the full
    /// familiar board (topical + Core template). Seeded from the caller's profile —
    /// the generator opens Focused (ON); the editor mirrors the scene's setting.
    @State private var focused: Bool

    init(preview: GeneratedScene,
         allTiles: [TileModel],
         apiKey: String,
         profile: SceneNavigation.Profile = .full,
         previewImages: [String: Data] = [:],
         onRefined: @escaping () -> Void = {},
         onAccept: @escaping (GeneratedScene, Bool) -> Void,
         onCancel: @escaping () -> Void) {
        self.allTiles = allTiles
        self.apiKey = apiKey
        self.profile = profile
        self.previewImages = previewImages
        self.onRefined = onRefined
        self.onAccept = onAccept
        self.onCancel = onCancel
        // Seed the toggle + board from the caller's profile: the generator opens
        // Focused, the editor mirrors the scene. Re-scaffold topical-only when
        // Focused (cached starters have no rawContent → fall back to the preview).
        _focused = State(initialValue: profile == .focused)
        if profile == .focused, let content = preview.rawContent,
           let parsed = try? GeneratedScene.parse(content: content, allTiles: allTiles, profile: .focused) {
            var f = parsed
            f.tokenUsage = preview.tokenUsage
            _working = State(initialValue: f)
        } else {
            _working = State(initialValue: preview)
        }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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

    // At-authoring moderation review of the proposed NEW words (same as Page Preview).
    @State private var review = NewWordReviewModel()

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

    /// Accept: drop removed + untouched blocked words, then hand off the cleaned scene.
    private func acceptModerated() {
        for key in review.droppedKeys(present: presentNewKeys) { removeNewWord(key) }
        onAccept(working, focused)
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

            // Focused board toggle — only for AI-generated scenes (cached starters
            // have fixed pages and no raw content to re-scaffold).
            if working.rawContent != nil {
                Toggle(isOn: $focused) {
                    Label("Focused board", systemImage: "scope")
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: focused) { _, _ in applyFocus() }
            }

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

            // Action bar
            HStack(spacing: 10) {
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
                Button("Accept") { acceptModerated() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefining || !review.canAccept(present: presentNewKeys))
            }
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

    /// Re-derive the previewed scene from its raw content at the current profile
    /// (focused ⇄ full) — no API call, just a re-scaffold. Preserves token usage.
    private func applyFocus() {
        guard let content = working.rawContent,
              let parsed = try? GeneratedScene.parse(content: content, allTiles: allTiles,
                                                     profile: focused ? .focused : .full) else { return }
        var next = parsed
        next.tokenUsage = working.tokenUsage
        working = next
        selectedPageIndex = 0
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
                let result = try await service.refine(instruction: text, currentTopical: currentTopical, allTiles: tiles, profile: focused ? .focused : .full)
                await MainActor.run {
                    working = result
                    selectedPageIndex = 0
                    onRefined()
                }
            } catch {
                await MainActor.run { refineError = error.localizedDescription }
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
                    Text("e.g. \u{201C}add a fish pond and a creek\u{201D}, or \u{201C}remove the tractor\u{201D}. The familiar core board stays the same.")
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
