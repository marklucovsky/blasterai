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
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
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
            allowedContentTypes: [.blasterScene, .json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $pendingImportURL) { item in
            SceneImportSheet(url: item.url) { pendingImportURL = nil }
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
        Section("Scenes") {
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
                    if !scene.isActive {
                        Button("Activate") { activateScene(scene) }
                            .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // System-owned scenes are undeletable as well as uneditable:
                    // we ship them, and a caregiver who wants rid of one keeps
                    // their own copy and simply stops activating this.
                    if !scene.isDefault && !scene.isSystemOwned {
                        Button(role: .destructive) {
                            deleteScene(scene)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    Button {
                        exportScene(scene)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                    Button {
                        duplicateScene(scene)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.indigo)
                }
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

    func activateScene(_ scene: BlasterScene) {
        try? scene.activate(context: modelContext)
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
        try? copy.activate(context: modelContext)
        try? modelContext.save()
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

    /// Bundled (system) vocabulary keys — the importer already has these, so they
    /// aren't packaged. Caregiver-added words (isSystem=false) ARE exported.
    /// Provenance-based and image-set-independent (unlike a bundled-art check,
    /// which would over-export on a sparse set).
    var defaultTileKeys: Set<String> {
        Set(allTiles.filter(\.isSystem).map(\.key))
    }

    func exportScene(_ scene: BlasterScene) {
        do {
            // Ensure the shared file carries identity + provenance: stamp an id if
            // this scene predates identity, and fill the author name for a scene
            // THIS device authored (never overwrite an imported scene's author).
            let authorID = DeviceProfileStore.ensureAuthorID(context: modelContext)
            let authorName = DeviceProfileStore.authorName(context: modelContext)
            scene.ensureIdentity(authorID: authorID, authorName: authorName)
            if scene.authorName.isEmpty, !authorName.isEmpty, scene.sceneID.hasPrefix(authorID + "/") {
                scene.authorName = authorName
            }
            try? modelContext.save()

            let tileLookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            let data = try SceneExporter.exportJSON(scene,
                                                    defaultTileKeys: defaultTileKeys,
                                                    tileLookup: tileLookup)
            sceneToExport = BlasterSceneFile(
                data: data,
                filename: scene.name.sanitizedFilename + "." + BlasterSceneFormat.fileExtension
            )
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

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
