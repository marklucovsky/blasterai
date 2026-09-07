// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ScenesTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension AdminView {

    /// Pull a pending `admin/scenes/...` request off the coordinator and turn it
    /// into an actual push.
    func consumePendingSceneDetail() {
        guard let detail = adminRoute.consumeDetail(for: .scenes) else { return }
        switch detail {
        case .vocabulary: vocabDetail = .vocabulary
        default:          break
        }
    }

    var scenesTab: some View {
        NavigationStack {
            List {
                AuthorNameField()
                scenesSection
                newSceneSection
                importSceneSection
                Section {
                    NavigationLink {
                        VocabManagerView()
                    } label: {
                        Label("Manage Vocabulary", systemImage: "textformat.abc")
                    }
                } footer: {
                    Text("Hide or restore words, and review anything the moderation gate flagged.")
                }
            }
            .navigationTitle("Scenes")
            .navigationDestination(item: $navigateToNewScene) { scene in
                SceneEditorView(scene: scene)
            }
            // A script asking for `admin/scenes/vocabulary` sets a pending
            // detail; the tab that owns the destination is the only thing that
            // can push it, and it clears the request on arrival so a later
            // hand-selection of this tab doesn't silently push again.
            .navigationDestination(item: $vocabDetail) { _ in
                VocabManagerView()
            }
            .onAppear { consumePendingSceneDetail() }
            .onChange(of: adminRoute.pendingDetail) { _, _ in consumePendingSceneDetail() }
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Scenes", systemImage: "square.grid.2x2.fill") }
        .sheet(isPresented: $isCreatingScene) {
            SceneGeneratorSheet(allTiles: allTiles, apiKey: resolvedAPIKey) { scene in
                navigateToNewScene = scene
            } onManual: { name in
                createBlankScene(name: name)
            }
        }
        .sheet(item: $sceneToShare) { scene in
            ShareBoardSheet(subject: .scene(scene))
        }
        .confirmationDialog(
            "This is a built-in board",
            isPresented: Binding(get: { sceneToClone != nil },
                                 set: { if !$0 { sceneToClone = nil } }),
            titleVisibility: .visible,
            presenting: sceneToClone
        ) { scene in
            Button("Make My Copy") { cloneSystemSceneForEditing(scene) }
            Button("Cancel", role: .cancel) { sceneToClone = nil }
        } message: { scene in
            Text("\(scene.baseName) is supplied and updated by BlasterAI, so it can't be edited directly. We'll make you an editable copy and switch to it. Your copy is yours — app updates won't touch it.")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.blasterScene, .blasterPack, .json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $pendingImportURL) { item in
            ImportRouteSheet(url: item.url) { pendingImportURL = nil }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    var scenesSection: some View {
        Section {
            ForEach(scenes) { scene in
                Group {
                    if scene.isSystemOwned {
                        // System scenes are immutable — the editor is the single
                        // door to every scene mutation, so refusing to open it
                        // here is what keeps them pristine. Tapping offers an
                        // editable copy instead.
                        Button {
                            sceneToClone = scene
                        } label: {
                            SceneRow(scene: scene, onActivate: { activateScene(scene) })
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: SceneEditorView(scene: scene)) {
                            SceneRow(scene: scene, onActivate: { activateScene(scene) })
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    activateButton(scene)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteButton(scene)
                    shareButton(scene)
                    duplicateButton(scene)
                }
                // The same actions on touch-and-hold.
                //
                // A swipe is invisible until you already know it is there, and it
                // is the wrong gesture on a Mac, where these boards are edited
                // with a trackpad and a right-click is what a caregiver reaches
                // for. Offering both costs one modifier and means no action is
                // reachable only by a gesture nobody discovered.
                .contextMenu {
                    activateButton(scene)
                    shareButton(scene)
                    duplicateButton(scene)
                    if isDeletable(scene) {
                        Divider()
                        deleteButton(scene)
                    }
                }
            }
        } header: {
            Text("Scenes")
        } footer: {
            Text("Swipe a board left to share, duplicate or delete it, or right to make it active. Touch and hold a board for the same actions.")
        }
    }

    // MARK: - Row actions
    //
    // Written once and used by both the swipe and the menu, so the two cannot
    // drift into offering different things.

    /// A board we ship is undeletable as well as uneditable: a caregiver who
    /// wants rid of one keeps their own copy and stops activating this.
    func isDeletable(_ scene: BlasterScene) -> Bool {
        !scene.isDefault && !scene.isSystemOwned
    }

    @ViewBuilder
    func activateButton(_ scene: BlasterScene) -> some View {
        if !scene.isActive {
            Button {
                activateScene(scene)
            } label: {
                Label("Activate", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    func shareButton(_ scene: BlasterScene) -> some View {
        Button {
            sceneToShare = scene
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
    }

    @ViewBuilder
    func duplicateButton(_ scene: BlasterScene) -> some View {
        Button {
            duplicateScene(scene)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .tint(.indigo)
    }

    @ViewBuilder
    func deleteButton(_ scene: BlasterScene) -> some View {
        if isDeletable(scene) {
            Button(role: .destructive) {
                deleteScene(scene)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    var newSceneSection: some View {
        Section {
            Button {
                isCreatingScene = true
            } label: {
                Label("New Scene", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    var importSceneSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import Scene", systemImage: "square.and.arrow.down")
            }
        }
    }

    // MARK: - Scene actions

    func duplicateScene(_ scene: BlasterScene) {
        _ = BlasterScene.duplicate(of: scene, in: modelContext,
                                   authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                                   authorName: DeviceProfileStore.authorName(context: modelContext))
        try? modelContext.save()
    }

    /// Activate, and say what happened.
    ///
    /// Every call site used to be `try?`, which is how §9's "never silently"
    /// was actually being broken: `activate` already repaired a dangling home
    /// page, and the caregiver's board changed under them with no explanation.
    /// A thrown refusal went nowhere either.
    func activateScene(_ scene: BlasterScene) {
        do {
            let outcome = try scene.activate(context: modelContext)
            try? modelContext.save()
            if let message = outcome.message {
                activationNotice = ActivationNotice(title: "Scene Activated", message: message)
            }
        } catch {
            // Nothing was mutated — `activate` validates before it touches
            // anything — so the previously active scene is still the board.
            activationNotice = ActivationNotice(
                title: "Can't Use This Scene",
                message: error.localizedDescription)
        }
    }

    /// Clone-on-write for an immutable system scene: take an editable copy,
    /// make it active, and open the editor on it. The caregiver asked to edit,
    /// so they land in something they can actually edit rather than being told
    /// no. See `BlasterScene.isSystemOwned`.
    func cloneSystemSceneForEditing(_ scene: BlasterScene) {
        let copy = BlasterScene.cloneForEditing(
            scene, in: modelContext,
            authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
            authorName: DeviceProfileStore.authorName(context: modelContext))
        activateScene(copy)
        sceneToClone = nil
        navigateToNewScene = copy       // reuse the post-generation editor route
    }

    func deleteScenes(at offsets: IndexSet) {
        for index in offsets {
            let scene = scenes[index]
            if scene.isDefault { continue }
            let wasActive = scene.isActive
            modelContext.delete(scene)
            if wasActive {
                // Restore default
                if let defaultScene = scenes.first(where: { $0.isDefault }) {
                    defaultScene.isActive = true
                }
            }
        }
        try? modelContext.save()
    }

    func deleteScene(_ scene: BlasterScene) {
        guard !scene.isDefault else { return }
        let wasActive = scene.isActive
        modelContext.delete(scene)
        if wasActive {
            if let defaultScene = scenes.first(where: { $0.isDefault }) {
                defaultScene.isActive = true
            }
        }
        try? modelContext.save()
    }

    var resolvedAPIKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    func createBlankScene(name: String) {
        let scene = BlasterScene(name: name.isEmpty ? "New Scene" : name)
        scene.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                             authorName: DeviceProfileStore.authorName(context: modelContext))
        modelContext.insert(scene)
        navigateToNewScene = scene
    }

    /// Keys a fresh install already owns, so an export need not carry them.
    ///
    /// `vocabulary.json`, NOT `isSystem`. The two look interchangeable and are
    /// not: `isSystem` means first-party, and bundled PACK words are first-party
    /// while being absent until the pack is installed. Filtering on it dropped
    /// every pack word from every export. See `BundledVocabulary`.
    var defaultTileKeys: Set<String> { BundledVocabulary.keys }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Route through the same confirmation sheet as the file-open/iMessage
            // path so an in-app import is previewed (new words, images) before it
            // lands — rather than importing immediately.
            pendingImportURL = ImportSheetURL(url: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
