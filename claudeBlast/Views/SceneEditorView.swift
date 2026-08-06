// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UIKit

struct SceneEditorView: View {
    @Bindable var scene: BlasterScene
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var imageResolver
    @Environment(SceneArtCoordinator.self) private var sceneArtCoordinator
    @Environment(\.scenePhase) private var scenePhase

    /// Per-scene art controller from the app-level coordinator, so a background
    /// run survives this editor being dismissed and re-entered.
    private var artController: SceneImageBatchController {
        sceneArtCoordinator.controller(for: scene.id)
    }
    private var resolvedAPIKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    @State private var isAddingPage = false
    @State private var isRefining = false
    @State private var isGeneratingArt = false
    @State private var showPreview = false
    @State private var showKeySheet = false
    @State private var pageToLink: PageLinkTarget? = nil
    @AppStorage(AppSettingsKey.generateAllStyles) private var generateAllStyles = false

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// (flagged, blocked) counts for a page's tiles — one pass over a single
    /// hoisted lookup — shown as chips so a caregiver spots pages needing attention.
    private func reviewCounts(_ page: PageSpec) -> (flagged: Int, blocked: Int) {
        let lookup = tileLookup
        var flagged = 0, blocked = 0
        for entry in page.tiles {
            guard let t = lookup[entry.key] else { continue }
            if t.needsReview { flagged += 1 }
            if t.isRetired { blocked += 1 }
        }
        return (flagged, blocked)
    }

    private func countChip(_ text: String, _ system: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system).font(.caption2)
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    /// Caregiver words this scene introduced that still have no art.
    private var tilesNeedingArt: [TileModel] {
        SceneImageBatch.tilesNeedingArt(in: scene, tileLookup: tileLookup, resolver: imageResolver)
    }
    /// Identifier of a freshly-created page to navigate into. Stored as the
    /// page key string now that pages are inline structs rather than
    /// SwiftData entities.
    @State private var navigateToNewPageKey: String? = nil
    @State private var pickerKeysForNewPage: Set<String> = []
    @State private var sceneToExport: BlasterSceneFile?

    var body: some View {
        List {
            if !scene.creationSummary.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.tint)
                        Text(scene.creationSummary).font(.subheadline)
                        Spacer()
                        Button { scene.creationSummary = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if artController.isActive {
                Section {
                    Button {
                        isGeneratingArt = true
                    } label: {
                        HStack(spacing: 10) {
                            if artController.phase == .paused {
                                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                            } else {
                                ProgressView()
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artController.phase == .paused ? "Art paused" : "Creating new-word art…")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(artController.completed) of \(artController.total) done · tap to manage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("In progress")
                } footer: {
                    Text(artController.phase == .paused
                         ? "Paused. Tap to resume, continue in the background, or cancel."
                         : "Running in the background. Tap to view progress, pause, or cancel.")
                }
            } else if !tilesNeedingArt.isEmpty {
                if resolvedAPIKey.isEmpty {
                    Section {
                        Button {
                            showKeySheet = true
                        } label: {
                            Label("Add an AI Key to generate artwork for new words",
                                  systemImage: "key.fill")
                        }
                    } header: {
                        Text("New-Word Art")
                    } footer: {
                        Text("\(tilesNeedingArt.count) new word\(tilesNeedingArt.count == 1 ? "" : "s") still need a picture. Add your key to generate them with AI.")
                    }
                } else {
                    Section {
                        Toggle("Generate all styles", isOn: $generateAllStyles)
                            .font(.subheadline)
                        Button {
                            artController.start(tiles: tilesNeedingArt, apiKey: resolvedAPIKey,
                                                context: modelContext, resolver: imageResolver)
                            isGeneratingArt = true
                        } label: {
                            Label("Generate art for \(tilesNeedingArt.count) new word\(tilesNeedingArt.count == 1 ? "" : "s")",
                                  systemImage: "sparkles")
                        }
                    } header: {
                        Text("New-Word Art")
                    } footer: {
                        Text(generateAllStyles
                             ? "These words were added by AI and don't have pictures yet. Art is generated for every tile style."
                             : "These words were added by AI and don't have pictures yet.")
                    }
                }
            }

            Section("Scene Info") {
                LabeledContent("Name") {
                    TextField("Scene name", text: $scene.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Description") {
                    TextField("Optional description", text: $scene.descriptionText)
                        .multilineTextAlignment(.trailing)
                }
                if !scene.pages.isEmpty {
                    Picker("Home Page", selection: $scene.homePageKey) {
                        ForEach(scene.pages, id: \.key) { page in
                            Text(page.key).tag(page.key)
                        }
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { scene.isFocused }, set: { setProfile(focused: $0) })) {
                    Text("Focused board")
                }
                .disabled(scene.isDefault)
            } header: {
                Text("Board")
            } footer: {
                Text("Focused trims the board for 1:1 sessions: the topical tiles plus a short needs strip (hungry/thirsty, help, feelings) and the body & health page. Off uses the full familiar board (people, food, drinks, body & health).")
            }

            Section("Pages (\(scene.pages.count))") {
                ForEach(scene.pages, id: \.key) { page in
                    NavigationLink(destination: PageEditorView(scene: scene, pageKey: page.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(page.key)
                                    .font(.headline)
                                if scene.homePageKey == page.key {
                                    Text("HOME")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.blue.opacity(0.15)))
                                        .foregroundStyle(.blue)
                                }
                            }
                            HStack(spacing: 8) {
                                Text("\(page.tiles.count) tile\(page.tiles.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let counts = reviewCounts(page)
                                if counts.flagged > 0 { countChip("\(counts.flagged)", "flag.fill", .orange) }
                                if counts.blocked > 0 { countChip("\(counts.blocked)", "eye.slash.fill", .red) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            guard let newKey = scene.duplicatePage(page.key) else { return }
                            try? modelContext.save()
                            // A duplicated page is otherwise unreachable — offer the
                            // same link-placement step AI pages get, so the caregiver
                            // can wire it into the scene (skippable). Only when there's
                            // another page to link it from.
                            if scene.pages.contains(where: { $0.key != newKey }) {
                                pageToLink = PageLinkTarget(pageKey: newKey)
                            }
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.indigo)
                    }
                }
                .onDelete(perform: deletePages)

                Button {
                    isAddingPage = true
                } label: {
                    Label("Add Page", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(scene.name.isEmpty ? "New Scene" : scene.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPreview = true
                } label: {
                    Image(systemName: "eye")
                }
                .accessibilityLabel("Preview scene")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isRefining = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Refine with AI")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportScene()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
        }
        .fullScreenCover(isPresented: $showPreview) {
            ScenePreviewBoardView(scene: scene, allTiles: allTiles)
        }
        .sheet(isPresented: $showKeySheet) {
            APIKeyEntrySheet()
        }
        .sheet(isPresented: $isRefining) {
            SceneRefinementSheet(scene: scene, allTiles: allTiles, apiKey: resolvedAPIKey)
        }
        .sheet(isPresented: $isGeneratingArt) {
            SceneImageBatchSheet(controller: artController)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: artController.appBecameActive()
            case .background: artController.appMovedToBackground()
            default: break
            }
        }
        .onChange(of: isGeneratingArt) { _, shown in
            // Clear a finished run once its summary is dismissed so the banner
            // returns to its idle state.
            if !shown, artController.phase == .finished { artController.reset() }
        }
        .sheet(isPresented: $isAddingPage) {
            PageGeneratorSheet(scene: scene, allTiles: allTiles, apiKey: resolvedAPIKey) { pageKey, preSelectedKeys in
                if !preSelectedKeys.isEmpty {
                    // Edit path: dive into the new page with the picker pre-loaded.
                    pickerKeysForNewPage = preSelectedKeys
                    navigateToNewPageKey = pageKey
                } else if scene.pages.contains(where: { $0.key != pageKey }) {
                    // Finalized page with somewhere to link → offer the link step,
                    // then return to the scene editor (page is in the Pages list).
                    pageToLink = PageLinkTarget(pageKey: pageKey)
                }
                // else: finalized page, nothing to link → stay in the scene editor.
            }
        }
        .navigationDestination(item: $navigateToNewPageKey) { pageKey in
            PageEditorView(scene: scene, pageKey: pageKey, autoOpenPickerWithKeys: pickerKeysForNewPage)
        }
        .sheet(item: $pageToLink) { target in
            PageLinkPlacementSheet(scene: scene, target: target, allTiles: allTiles)
        }
    }

    private func exportScene() {
        // Bundled (system) keys aren't packaged; caregiver words are. Provenance-
        // based so it's independent of the active image set.
        let defaultKeys = Set(allTiles.filter(\.isSystem).map(\.key))
        let tileLookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        guard let data = try? SceneExporter.exportJSON(scene,
                                                       defaultTileKeys: defaultKeys,
                                                       tileLookup: tileLookup) else { return }
        sceneToExport = BlasterSceneFile(
            data: data,
            filename: scene.name.sanitizedFilename + "." + BlasterSceneFormat.fileExtension
        )
    }

    private func deletePages(at offsets: IndexSet) {
        var pages = scene.pages
        let deletedKeys = Set(offsets.map { pages[$0].key })
        for index in offsets.sorted().reversed() {
            pages.remove(at: index)
        }
        // Clean up links to the deleted page(s) so nothing opens an empty page:
        // silent nav tiles (incl. the page_link tile) are removed; audible tiles
        // that also linked there keep the word but drop the dead link.
        if !deletedKeys.isEmpty {
            for i in pages.indices {
                pages[i].tiles = pages[i].tiles.compactMap { entry in
                    guard deletedKeys.contains(entry.link) else { return entry }
                    return entry.isAudible
                        ? TileEntry(key: entry.key, link: "", isAudible: true)
                        : nil
                }
            }
        }
        scene.pages = pages
        if !scene.pages.contains(where: { $0.key == scene.homePageKey }) {
            scene.homePageKey = scene.pages.first?.key ?? ""
        }
        // Drop the now-orphaned page_link tiles for the deleted pages from vocab.
        for key in deletedKeys {
            let linkKey = PageLink.key(forPage: key)
            if let tile = allTiles.first(where: { $0.key == linkKey }) {
                modelContext.delete(tile)
            }
        }
        try? modelContext.save()
    }

    /// Re-scaffold the scene at the chosen board profile. Pure local transform:
    /// the topical layer is preserved and the core board is rebuilt full or lean.
    private func setProfile(focused: Bool) {
        let lookup = tileLookup
        let topical = SceneNavigation.topicalKeys(of: scene).map { key -> GeneratedTile in
            let tile = lookup[key]
            let isCaregiverWord = (tile?.isSystem == false)
            return GeneratedTile(key: key, isAudible: true, link: "",
                                 displayName: tile?.value,
                                 wordClass: isCaregiverWord ? tile?.wordClass : nil)
        }
        let base = GeneratedScene(
            name: scene.name,
            description: scene.descriptionText,
            homePageKey: scene.homePageKey,
            pages: [GeneratedPage(key: scene.homePageKey, tiles: topical)]
        )
        let scaffolded = SceneNavigation.scaffold(base, allTiles: allTiles,
                                                  validKeys: Set(allTiles.map(\.key)),
                                                  profile: focused ? .focused : .full)
        do {
            try SceneBuilder.update(scene, from: scaffolded, tileLookup: lookup, context: modelContext)
            scene.isFocused = focused
            try? modelContext.save()
        } catch {
            // Leave the scene unchanged on failure.
        }
    }
}

// MARK: - Page Generator Sheet

/// A featured "Build with AI" example. The goal is pre-vetted: leaving it
/// unchanged serves a cached answer (0 tokens); editing it runs real AI. Each
/// projects one non-system `demo` word (no art) so the caregiver experiences
/// image generation on accept.
private struct AIPageExample: Identifiable {
    let name: String        // page key
    let title: String
    let goal: String        // the cacheable, vetted prompt
    let packId: String      // supplies the on-screen words (+ set-switching art)
    let demoKey: String     // new, non-system word — no art (image-gen demo)
    let demoClass: String
    let demoName: String
    var id: String { name }
}

private struct PageGeneratorSheet: View {
    let scene: BlasterScene
    let allTiles: [TileModel]
    let apiKey: String
    /// Callback: (newly created page key, pre-selected keys for Edit path —
    /// empty for Accept path).
    let onCreate: (String, Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var pageName = ""
    @State private var pageGoal = ""
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var preview: GeneratedPageResult? = nil
    /// Set while previewing a vocabulary pack as a page; drives the install +
    /// page-create accept path. Cleared on Retry (→ back to the form).
    @State private var cachedPack: VocabPack? = nil

    /// Set while previewing a cached AI example (unedited vetted goal). Drives the
    /// "served from cache · 0 tokens" badge + the demo-word projection.
    @State private var cachedAIExample: AIPageExample? = nil
    @State private var showRefine = false

    /// Set while previewing a page copied from another scene; drives the copy
    /// accept path + the provenance badge.
    @State private var cachedCopy: PageSpec? = nil
    @State private var cachedCopyFrom: String = ""

    /// Set while previewing "all words of a class"; drives the class-query accept
    /// path + the provenance badge.
    @State private var cachedClassQuery: [String]? = nil

    /// All scenes — source list for the "Copy from another scene" picker.
    @Query private var allScenes: [BlasterScene]

    /// Featured "Build with AI" examples. Tapping fills the vetted goal; Generate
    /// with it unchanged serves the cached answer (0 tokens), editing runs real AI.
    private let aiExamples: [AIPageExample] = [
        AIPageExample(name: "space", title: "Space adventure",
            goal: "Outer space and space travel — rockets, planets, the moon, stars, astronauts, and aliens.",
            packId: "packs.blasterai.app/space",
            demoKey: "spacesuit", demoClass: "object", demoName: "Spacesuit"),
        AIPageExample(name: "vehicles", title: "Things that go",
            goal: "Vehicles that go — cars, trucks, buses, trains, planes and boats, plus emergency vehicles like fire trucks, ambulances, and police cars.",
            packId: "packs.blasterai.app/vehicles",
            demoKey: "scooter", demoClass: "object", demoName: "Scooter"),
    ]

    /// Pack ids featured as AI examples — hidden from the pack list to avoid
    /// duplicating space/vehicles across both sections.
    private var aiExamplePackIDs: Set<String> { Set(aiExamples.map(\.packId)) }

    /// The featured AI example whose vetted goal exactly matches the current goal
    /// (unchanged) — Generate serves it from cache; any edit falls through to AI.
    private var matchedAIExample: AIPageExample? {
        let g = pageGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        return aiExamples.first { $0.goal == g }
    }

    /// A live AI preview (not a deterministic pack / copy / cached-AI one) — only
    /// these allow Edit and Refine.
    private var isLivePreview: Bool {
        cachedPack == nil && cachedAIExample == nil && cachedCopy == nil && cachedClassQuery == nil
    }
    private var previewProvenance: String? {
        if cachedAIExample != nil { return "⚡ Served from cache · 0 tokens" }
        if cachedCopy != nil { return "📄 Copied from \(cachedCopyFrom)" }
        if let classes = cachedClassQuery {
            return "🏷️ All \(classes.map(\.capitalized).joined(separator: " & ")) words"
        }
        return nil
    }

    /// Caregiver-selectable classes that have at least one word in the current
    /// vocabulary, with counts — the "add a page of one class" options.
    private var classQueryOptions: [(cls: VocabularyClass, count: Int)] {
        let counts = allTiles.reduce(into: [String: Int]()) { $0[$1.wordClass, default: 0] += 1 }
        return VocabularyClasses.caregiverSelectable.compactMap { c in
            let n = counts[c.name] ?? 0
            return n > 0 ? (c, n) : nil
        }
    }

    /// Other scenes that have at least one page — sources to copy a page from.
    private var copyableScenes: [BlasterScene] {
        allScenes.filter { $0.persistentModelID != scene.persistentModelID && !$0.pages.isEmpty }
    }

    var body: some View {
        NavigationStack {
            if preview != nil, let previewBinding = Binding($preview) {
                PagePreviewView(
                    preview: previewBinding,
                    pageName: pageName,
                    allTiles: allTiles,
                    apiKey: apiKey,
                    provenance: previewProvenance,
                    allowEdit: isLivePreview,
                    onAccept: { if let p = self.preview { buildAndAccept(p, editMode: false) } },
                    onEdit:   { if let p = self.preview { buildAndAccept(p, editMode: true) } },
                    onRetry:  { cachedPack = nil; cachedAIExample = nil; cachedCopy = nil; cachedClassQuery = nil; self.preview = nil; runGeneration() },
                    onRefine: (isLivePreview && !apiKey.isEmpty) ? { showRefine = true } : nil,
                    onCancel: { dismiss() }
                )
                .navigationTitle("Page Preview")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showRefine) {
                    PageRefineInputSheet(pageName: pageName,
                                         currentTiles: preview?.primaryPage.tiles ?? [],
                                         allTiles: allTiles, apiKey: apiKey,
                                         scenePages: scene.pages, homePageKey: scene.homePageKey) { refined in
                        self.preview = refined
                    }
                }
            } else {
                generatorForm
            }
        }
    }

    private var generatorForm: some View {
        VStack(spacing: 0) {
            Form {
                Section("Page Name") {
                    TextField("e.g. emotions", text: $pageName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(isGenerating)
                }

                Section {
                    TextField("e.g. feelings and emotions for a 6-year-old", text: $pageGoal)
                        .disabled(isGenerating)
                } header: {
                    Label("AI Goal", systemImage: "sparkles")
                } footer: {
                    Text("Describe what this page should help communicate.")
                }

                Section {
                    ForEach(aiExamples, id: \.name) { ex in
                        Button {
                            pageName = ex.name
                            pageGoal = ex.goal
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.caption).foregroundStyle(.tint)
                                    Text(ex.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("AI")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                        .foregroundStyle(.tint)
                                }
                                Text(ex.goal)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .disabled(isGenerating)
                    }
                } header: {
                    Text("Build with AI")
                } footer: {
                    Text("Tap a vetted prompt, then Generate — the AI invents the page with new words and artwork.")
                        .font(.caption)
                }

                let packList = PackCatalog.all.filter { !aiExamplePackIDs.contains($0.id) }
                if !packList.isEmpty {
                    Section {
                        ForEach(packList) { pack in
                            Button {
                                loadPackPage(pack)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.caption).foregroundStyle(.tint)
                                    Text(pack.displayName)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(pack.words.count) words")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .disabled(isGenerating)
                        }
                    } header: {
                        Text("Start from a vocabulary pack")
                    } footer: {
                        Text("Builds a page instantly from a ready-made vocabulary pack — set-switching art, no key needed.")
                            .font(.caption)
                    }
                }

                let classOptions = classQueryOptions
                if !classOptions.isEmpty {
                    Section {
                        DisclosureGroup("Choose a word class") {
                            ForEach(classOptions, id: \.cls.id) { opt in
                                Button {
                                    loadClassQueryPage([opt.cls.name])
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle().fill(opt.cls.color).frame(width: 12, height: 12)
                                        Text(opt.cls.label)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(opt.count) word\(opt.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .disabled(isGenerating)
                            }
                        }
                    } header: {
                        Text("Add a page of one word class")
                    } footer: {
                        Text("Builds a page instantly from every word already in your vocabulary of that class — no key needed.")
                            .font(.caption)
                    }
                }

                if !copyableScenes.isEmpty {
                    Section {
                        ForEach(copyableScenes, id: \.persistentModelID) { src in
                            DisclosureGroup(src.name.isEmpty ? "Untitled scene" : src.name) {
                                ForEach(src.pages, id: \.key) { page in
                                    Button {
                                        loadCopiedPage(from: src, page: page)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.caption).foregroundStyle(.tint)
                                            Text(page.key).foregroundStyle(.primary)
                                            if page.key == src.homePageKey {
                                                Label("Home", systemImage: "house.fill")
                                                    .labelStyle(.titleAndIcon)
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                                    .foregroundStyle(.blue)
                                            }
                                            Spacer()
                                            Text("\(page.tiles.count) tiles")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .disabled(isGenerating)
                                }
                            }
                        }
                    } header: {
                        Text("Copy from another scene")
                    } footer: {
                        Text("Copies a page's word tiles into this scene. Navigation links are dropped — re-add them here if needed.")
                            .font(.caption)
                    }
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
                        Text("Add an OpenAI API key in Admin to generate a custom page. The ready-made examples above work without a key.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    // Unedited vetted prompt → serve from cache (0 tokens); any
                    // edit runs the real generator.
                    if let ex = matchedAIExample {
                        loadCachedAIPage(ex)
                    } else {
                        runGeneration()
                    }
                } label: {
                    Group {
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Generating…")
                            }
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pageGoal.trimmingCharacters(in: .whitespaces).isEmpty
                          || pageName.trimmingCharacters(in: .whitespaces).isEmpty
                          || isGenerating
                          || (apiKey.isEmpty && matchedAIExample == nil))

                Button("Skip AI — Create Empty Page") {
                    createEmptyPage(preSelectedKeys: [])
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(pageName.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
            }
            .padding()
        }
        .navigationTitle("New Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func runGeneration() {
        let goal = pageGoal.trimmingCharacters(in: .whitespaces)
        let name = normalizedPageKey(pageName)
        guard !goal.isEmpty, !name.isEmpty, !apiKey.isEmpty else { return }
        isGenerating = true
        generationError = nil
        let service = PageGeneratorService(apiKey: apiKey)
        let tiles = allTiles
        let pages = scene.pages
        let homeKey = scene.homePageKey
        Task {
            do {
                let result = try await service.generate(pageGoal: goal, pageName: name, allTiles: tiles,
                                                        scenePages: pages, homePageKey: homeKey)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { generationError = error.localizedDescription }
            }
            await MainActor.run { isGenerating = false }
        }
    }

    private func buildAndAccept(_ result: GeneratedPageResult, editMode: Bool) {
        // Deterministic sources (copied page / cached-AI example / vocab pack) all
        // resolve through CollectionSource → the shared commit tail. AI generation
        // (below) is NOT a source — it produces its own multi-page result.

        // A page copied from another scene.
        if let copy = cachedCopy, !editMode {
            commitSource(.copyPage(copy), honoring: result)
            return
        }
        // Cached AI example (vetted goal, served instantly): its pack + the
        // projected demo word (no art) so the caregiver experiences art generation.
        if let ex = cachedAIExample, !editMode {
            var lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            guard let pack = PackCatalog.pack(id: ex.packId),
                  var built = CollectionSource.build(.pack(pack), into: modelContext,
                                                     allTiles: allTiles, existing: lookup) else { dismiss(); return }
            // The demo word is a projected new tile — materialize it so the
            // preview's demo entry resolves (the preview already includes it).
            if lookup[ex.demoKey] == nil {
                let demo = TileModel(key: ex.demoKey, value: ex.demoName, wordClass: ex.demoClass)
                demo.isSystem = false
                modelContext.insert(demo)
                lookup[ex.demoKey] = demo
            }
            built.baseKey = ex.name   // examples name the page, not by pack slug
            built.tiles = previewTiles(result, lookup: lookup)   // honor prune/reorder
            guard !built.tiles.isEmpty else { dismiss(); return }
            commitBuilt(built, lookup: lookup)
            return
        }
        // A vocabulary pack accepted as a page.
        if let pack = cachedPack, !editMode {
            commitSource(.pack(pack), honoring: result)
            return
        }
        // Every word of a class (or classes), in vocabulary order.
        if let classes = cachedClassQuery, !editMode {
            commitSource(.wordClass(classes: classes), honoring: result)
            return
        }
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        var lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // Materialize proposed-new words (both paths) so they're real tiles —
        // wired onto the page (accept) or pre-selectable in the picker (edit).
        for genPage in [result.primaryPage] + result.subPages {
            for gen in genPage.tiles where gen.isProposedNew {
                guard lookup[gen.key] == nil,
                      let displayName = gen.displayName,
                      let wordClass = gen.wordClass else { continue }
                let tile = TileModel(key: gen.key, value: displayName, wordClass: wordClass)
                tile.isSystem = false
                modelContext.insert(tile)
                lookup[gen.key] = tile
            }
        }

        if editMode {
            // Edit path: create empty page, pass pre-selected keys to caller.
            createEmptyPage(preSelectedKeys: result.primaryTileKeys)
        } else {
            // Accept path: append the AI-generated page (and any sub-pages)
            // to the scene's inline pages array.
            var pages = scene.pages
            let primaryTiles: [TileEntry] = result.primaryPage.tiles.compactMap { gen in
                guard lookup[gen.key] != nil else { return nil }
                return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
            }
            pages.append(PageSpec(key: key, tiles: primaryTiles))
            for genSub in result.subPages {
                let subTiles: [TileEntry] = genSub.tiles.compactMap { gen in
                    guard lookup[gen.key] != nil else { return nil }
                    return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
                }
                pages.append(PageSpec(key: genSub.key, tiles: subTiles))
            }
            scene.pages = pages
            if scene.homePageKey.isEmpty { scene.homePageKey = key }
            PageLink.mint(pageKey: key,
                          displayName: pageName.trimmingCharacters(in: .whitespacesAndNewlines),
                          context: modelContext, existing: lookup)
            onCreate(key, [])
        }
        try? modelContext.save()
        dismiss()
    }

    /// Build `source`, then commit it **using the preview's (possibly pruned /
    /// reordered) tiles** rather than the source's full set — so edits made in the
    /// Page Preview's Select mode hold. The source still supplies side effects
    /// (installing pack words), the page name, and the cover image.
    private func commitSource(_ source: CollectionSource, honoring result: GeneratedPageResult) {
        let lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        guard var built = CollectionSource.build(source, into: modelContext,
                                                 allTiles: allTiles, existing: lookup) else { dismiss(); return }
        built.tiles = previewTiles(result, lookup: lookup)
        guard !built.tiles.isEmpty else { dismiss(); return }
        commitBuilt(built, lookup: lookup)
    }

    /// The preview's primary-page tiles as `TileEntry`s, in the preview's current
    /// order, dropping any whose key isn't a real tile. Reflects prune/reorder
    /// done in the Page Preview.
    private func previewTiles(_ result: GeneratedPageResult, lookup: [String: TileModel]) -> [TileEntry] {
        result.primaryPage.tiles.compactMap { g in
            guard lookup[g.key] != nil else { return nil }
            return TileEntry(key: g.key, link: g.link, isAudible: g.isAudible)
        }
    }

    /// Word tiles of `page` present in device vocab and not structural
    /// (page_link / navigation) — what a copy carries over.
    /// The shared "commit a built page" tail: uniquify the key against the scene,
    /// append the page, set home if empty, mint its nav link, save, notify, close.
    private func commitBuilt(_ built: CollectionSource.Built, lookup: [String: TileModel]) {
        let pageKey = uniquePageKey(built.baseKey)
        var pages = scene.pages
        pages.append(PageSpec(key: pageKey, tiles: built.tiles))
        scene.pages = pages
        if scene.homePageKey.isEmpty { scene.homePageKey = pageKey }
        switch built.cover {
        case .data(let data):
            PageLink.mint(pageKey: pageKey, displayName: built.displayName, image: data,
                          context: modelContext, existing: lookup)
        case .key(let imageKey):
            PageLink.mint(pageKey: pageKey, displayName: built.displayName, imageKey: imageKey,
                          context: modelContext, existing: lookup)
        }
        try? modelContext.save()
        onCreate(pageKey, [])
        dismiss()
    }

    /// A page key derived from `base`, made unique against the scene (`_2`, `_3`, …).
    private func uniquePageKey(_ base: String) -> String {
        var key = base
        var n = 2
        while scene.pages.contains(where: { $0.key == key }) { key = "\(base)_\(n)"; n += 1 }
        return key
    }

    private func copyableTiles(from page: PageSpec) -> [TileModel] {
        let lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return page.tiles.compactMap { entry in
            guard let t = lookup[entry.key],
                  t.wordClass != PageLink.wordClass, t.wordClass != "navigation" else { return nil }
            return t
        }
    }

    private func loadCopiedPage(from src: BlasterScene, page: PageSpec) {
        let tiles = copyableTiles(from: page)
        guard !tiles.isEmpty else {
            generationError = "That page has no copyable word tiles."
            return
        }
        cachedCopy = page
        cachedCopyFrom = src.name.isEmpty ? "another scene" : src.name
        pageName = page.key
        let gen = tiles.map {
            GeneratedTile(key: $0.key, isAudible: true, link: "",
                          displayName: $0.displayName, wordClass: $0.wordClass)
        }
        preview = GeneratedPageResult(primaryPage: GeneratedPage(key: page.key, tiles: gen), subPages: [])
    }

    /// Preview every word of `classes` (vocabulary order) as a page. Accept
    /// resolves through `CollectionSource.wordClass` — same filtering, so the
    /// committed page matches the preview.
    private func loadClassQueryPage(_ classes: [String]) {
        let set = Set(classes)
        let tiles = allTiles.filter { set.contains($0.wordClass) }
        guard !tiles.isEmpty else {
            generationError = "No words in that class yet."
            return
        }
        cachedClassQuery = classes
        let name = classes.map(\.capitalized).joined(separator: " & ")
        pageName = name
        let gen = tiles.map {
            GeneratedTile(key: $0.key, isAudible: true, link: "",
                          displayName: $0.displayName, wordClass: $0.wordClass)
        }
        preview = GeneratedPageResult(primaryPage: GeneratedPage(key: name.lowercased(), tiles: gen),
                                      subPages: [])
    }

    private func loadPackPage(_ pack: VocabPack) {
        cachedPack = pack
        pageName = pack.displayName
        let tiles = pack.words.map {
            GeneratedTile(key: $0.key, isAudible: true, link: "",
                          displayName: $0.displayName, wordClass: $0.wordClass)
        }
        preview = GeneratedPageResult(primaryPage: GeneratedPage(key: pack.slug, tiles: tiles),
                                      subPages: [])
    }

    /// Cached AI example → preview the pack's words plus the projected demo word
    /// (rendered via bundled art / placeholder). Accept imports + adds the demo.
    private func loadCachedAIPage(_ ex: AIPageExample) {
        cachedAIExample = ex
        pageName = ex.name
        var tiles: [GeneratedTile] = []
        if let pack = PackCatalog.pack(id: ex.packId) {
            tiles = pack.words.map {
                GeneratedTile(key: $0.key, isAudible: true, link: "",
                              displayName: $0.displayName, wordClass: $0.wordClass)
            }
        }
        tiles.append(GeneratedTile(key: ex.demoKey, isAudible: true, link: "",
                                   displayName: ex.demoName, wordClass: ex.demoClass))
        preview = GeneratedPageResult(primaryPage: GeneratedPage(key: ex.name, tiles: tiles),
                                      subPages: [])
    }

    private func createEmptyPage(preSelectedKeys: Set<String>) {
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        var pages = scene.pages
        pages.append(PageSpec(key: key, tiles: []))
        scene.pages = pages
        if scene.homePageKey.isEmpty { scene.homePageKey = key }
        PageLink.mint(pageKey: key,
                      displayName: pageName.trimmingCharacters(in: .whitespacesAndNewlines),
                      context: modelContext,
                      existing: Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }))
        onCreate(key, preSelectedKeys)
        dismiss()
    }

    private func normalizedPageKey(_ name: String) -> String {
        name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Page Preview View

private struct PagePreviewView: View {
    @Binding var preview: GeneratedPageResult
    let pageName: String
    let allTiles: [TileModel]
    var apiKey: String = ""
    var previewImages: [String: Data] = [:]
    var provenance: String? = nil
    var allowEdit: Bool = true
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onRetry: () -> Void
    var onRefine: (() -> Void)? = nil
    let onCancel: () -> Void

    @State private var selectedSection = 0  // 0 = primary, 1+ = sub-pages
    @State private var isSelecting = false
    // At-authoring moderation review of the proposed NEW words.
    @State private var review = NewWordReviewModel()

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var allSections: [GeneratedPage] {
        [preview.primaryPage] + preview.subPages
    }

    /// Every proposed NEW word across all sections (key, display name) — the set
    /// the moderation review audits and gates Accept on.
    private var newWords: [(key: String, name: String)] {
        allSections.flatMap(\.tiles)
            .filter(\.isProposedNew)
            .compactMap { gt in gt.displayName.map { (gt.key, $0) } }
    }
    private var presentNewKeys: Set<String> { Set(newWords.map(\.key)) }

    /// Remove a NEW word from every section (a removed 🟡, or a 🔴 pruned on Accept).
    private func removeNewWord(_ key: String) {
        preview.primaryPage.tiles.removeAll { $0.key == key }
        for i in preview.subPages.indices { preview.subPages[i].tiles.removeAll { $0.key == key } }
    }

    /// Accept: drop the words the caregiver removed + untouched blocked, then hand off.
    private func acceptModerated() {
        for key in review.droppedKeys(present: presentNewKeys) { removeNewWord(key) }
        onAccept()
    }
    private var sectionIndex: Int { min(selectedSection, allSections.count - 1) }
    private var currentTiles: [GeneratedTile] { allSections[sectionIndex].tiles }

    /// The current section's tiles as an editable `[TileEntry]` binding. Writes
    /// map the new order/membership back onto the section's `GeneratedTile`s by
    /// key (preserving each tile's full data), so the preview prunes/reorders in
    /// place and Accept builds from the edited result.
    private var currentSectionBinding: Binding<[TileEntry]> {
        Binding(
            get: { currentTiles.map { TileEntry(key: $0.key, link: $0.link, isAudible: $0.isAudible) } },
            set: { newEntries in
                let byKey = Dictionary(currentTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                let reordered = newEntries.compactMap { byKey[$0.key] }
                if sectionIndex == 0 { preview.primaryPage.tiles = reordered }
                else { preview.subPages[sectionIndex - 1].tiles = reordered }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if allSections.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allSections.indices, id: \.self) { i in
                            Button { selectedSection = i } label: {
                                Text(i == 0 ? pageName : allSections[i].key)
                                    .font(.caption)
                                    .fontWeight(selectedSection == i ? .semibold : .regular)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(selectedSection == i
                                                       ? Color.accentColor
                                                       : Color.secondary.opacity(0.15))
                                    )
                                    .foregroundStyle(selectedSection == i ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            } else {
                Text(pageName)
                    .font(.headline)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }

            if let provenance {
                Text(provenance)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            HStack {
                Text("\(currentTiles.count) tile\(currentTiles.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if !currentTiles.isEmpty {
                    Button(isSelecting ? "Done" : "Select") { isSelecting.toggle() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            // Editable like the page editor (prune / reorder / bulk-delete before
            // Accept), minus the add-tile cell — you refine the generated set here.
            TileGridEditor(
                tiles: currentSectionBinding,
                isSelecting: $isSelecting,
                wordClassOf: { key in tileLookup[key]?.wordClass ?? currentTiles.first { $0.key == key }?.wordClass },
                minTile: 60,
                maxTile: 76,
                showAddCell: false,
                cell: { entry in generatedCell(entry.key) }
            )
            .onChange(of: selectedSection) { _, _ in isSelecting = false }

            Divider()

            NewWordReviewStatus(review: review, present: presentNewKeys)

            HStack(spacing: 10) {
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("Retry") { onRetry() }
                    .buttonStyle(.bordered)
                if let onRefine {
                    Button("Refine") { onRefine() }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                }
                Spacer()
                if allowEdit {
                    Button("Edit") { onEdit() }
                        .buttonStyle(.bordered)
                }
                Button("Accept") { acceptModerated() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!review.canAccept(present: presentNewKeys))
            }
            .padding()
        }
        // Moderation runs here, in the open — not silently at image-gen time.
        .task(id: presentNewKeys) { await review.analyze(newWords, apiKey: apiKey) }
    }

    /// Renders one preview tile by key — an existing tile via its art, or a
    /// proposed NEW word (flagged) via its declared display name / class.
    @ViewBuilder
    private func generatedCell(_ key: String) -> some View {
        if let gt = currentTiles.first(where: { $0.key == key }) {
            if let tile = tileLookup[gt.key] {
                GeneratedTileCell(key: tile.bundleImage, displayName: tile.displayName,
                                  wordClass: tile.wordClass, link: gt.link,
                                  imageData: previewImages[gt.key])
            } else if let name = gt.displayName, let wc = gt.wordClass {
                GeneratedTileCell(key: gt.key, displayName: name,
                                  wordClass: wc, link: gt.link, isNew: true,
                                  imageData: previewImages[gt.key])
                    .overlay(alignment: .bottomTrailing) {
                        NewWordReviewBadge(key: gt.key, review: review)
                    }
            }
        }
    }
}

// MARK: - Page Refine Sheet

/// Iteratively refine a previewed page with a natural-language instruction
/// ("add more sea creatures"). Mirrors the scene refine flow: keeps the current
/// tiles and applies only the change, then hands the refined result back so the
/// preview updates in place. Refine vs. Retry — Retry regenerates from scratch.
private struct PageRefineInputSheet: View {
    let pageName: String
    let currentTiles: [GeneratedTile]
    let allTiles: [TileModel]
    let apiKey: String
    let scenePages: [PageSpec]
    let homePageKey: String
    let onComplete: (GeneratedPageResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var isRefining = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. add more sea creatures, remove the boat",
                              text: $instruction, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(isRefining)
                } header: {
                    Label("Refine with AI", systemImage: "wand.and.stars")
                } footer: {
                    Text("Describe one change. The AI keeps the current tiles and applies just this.")
                }
                if let error {
                    Section { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Refine Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isRefining)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRefining {
                        ProgressView()
                    } else {
                        Button("Refine") { run() }
                            .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func run() {
        let inst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inst.isEmpty, !apiKey.isEmpty else { return }
        isRefining = true
        error = nil
        let service = PageGeneratorService(apiKey: apiKey)
        Task {
            do {
                let refined = try await service.refine(instruction: inst, pageName: pageName,
                                                       currentTiles: currentTiles, allTiles: allTiles,
                                                       scenePages: scenePages, homePageKey: homePageKey)
                await MainActor.run { onComplete(refined); dismiss() }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isRefining = false }
            }
        }
    }
}

// Lightweight tile cell for AI preview grids (no SwiftData dependency).
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

// MARK: - Scene Refinement Sheet

/// Iteratively refine the active scene with a natural-language instruction
/// ("add a fish pond and a creek"). Refinement rewrites the scene's topical
/// layer and re-scaffolds the familiar core board around it (see
/// SceneRefinerService / SceneNavigation). The change is previewed before it is
/// applied in place.
private struct SceneRefinementSheet: View {
    let scene: BlasterScene
    let allTiles: [TileModel]
    let apiKey: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var instruction = ""
    @State private var isRefining = false
    @State private var errorMessage: String? = nil
    @State private var preview: GeneratedScene? = nil

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var profile: SceneNavigation.Profile { scene.isFocused ? .focused : .full }

    var body: some View {
        NavigationStack {
            if let preview {
                ScenePreviewView(
                    preview: preview,
                    allTiles: allTiles,
                    apiKey: apiKey,
                    profile: profile,
                    onAccept: { scene, _ in apply(scene) },
                    onCancel: { dismiss() }
                )
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Describe the change…", text: $instruction, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Refine \(scene.name.isEmpty ? "Scene" : scene.name)")
            } footer: {
                Text("e.g. \u{201C}add a fish pond and a creek\u{201D} — the activity tiles update; the familiar core board stays the same.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    runRefine()
                } label: {
                    HStack {
                        if isRefining { ProgressView().padding(.trailing, 4) }
                        Text(isRefining ? "Refining\u{2026}" : "Refine")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty || apiKey.isEmpty || isRefining)
            }
        }
        .navigationTitle("Refine Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func runRefine() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !apiKey.isEmpty else { return }
        isRefining = true
        errorMessage = nil
        let service = SceneRefinerService(apiKey: apiKey)
        let lookup = tileLookup
        let topical = SceneNavigation.topicalKeys(of: scene).map { key -> GeneratedTile in
            let tile = lookup[key]
            let isCaregiverWord = (tile?.isSystem == false)
            return GeneratedTile(key: key, isAudible: true, link: "",
                                 displayName: tile?.value,
                                 wordClass: isCaregiverWord ? tile?.wordClass : nil)
        }
        let tiles = allTiles
        Task {
            do {
                let result = try await service.refine(instruction: text, currentTopical: topical, allTiles: tiles, profile: profile)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isRefining = false }
        }
    }

    private func apply(_ generated: GeneratedScene) {
        do {
            try SceneBuilder.update(scene, from: generated, tileLookup: tileLookup, context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            preview = nil
        }
    }
}
