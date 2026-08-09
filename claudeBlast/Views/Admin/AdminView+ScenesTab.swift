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
            .navigationTitle("Boards")
            .navigationDestination(item: $navigateToNewScene) { scene in
                SceneEditorView(scene: scene)
            }
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Boards", systemImage: "square.grid.2x2.fill") }
        .sheet(isPresented: $isCreatingScene) {
            SceneGeneratorSheet(allTiles: allTiles, apiKey: resolvedAPIKey) { scene in
                navigateToNewScene = scene
            } onManual: { name in
                createBlankScene(name: name)
            }
        }
        .sheet(item: $sceneToUpdate) { scene in
            UpdateConfirmationSheet(
                sceneName: scene.name,
                onConfirm: { duplicateFirst, remember in
                    applySystemSceneUpdate(duplicateFirst: duplicateFirst, remember: remember)
                }
            )
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
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
        Section("Boards") {
            ForEach(scenes) { scene in
                NavigationLink(destination: SceneEditorView(scene: scene)) {
                    SceneRow(
                        scene: scene,
                        updateAvailable: bundleUpdateAvailable,
                        onActivate: { activateScene(scene) },
                        onUpdate: { sceneToUpdate = scene }
                    )
                }
                .swipeActions(edge: .leading) {
                    if !scene.isActive {
                        Button("Activate") { activateScene(scene) }
                            .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !scene.isDefault {
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
                Label("New Board", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    var importSceneSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import Board", systemImage: "square.and.arrow.down")
            }
        }
    }

    // MARK: - Scene actions

    func applySystemSceneUpdate(duplicateFirst: Bool, remember: Bool) {
        // Persist the sticky preference state to match the toggle exactly:
        // - remember ON → store remembered=true + the duplicate value
        // - remember OFF → store remembered=false (toggling off explicitly
        //   forgets a previous choice, so the dialog reverts to safe defaults
        //   next time)
        let defaults = UserDefaults.standard
        defaults.set(remember, forKey: AppSettingsKey.forceRefreshDuplicateRemembered)
        if remember {
            defaults.set(duplicateFirst, forKey: AppSettingsKey.forceRefreshDuplicate)
        }

        // Snapshot the current Core-First into a duplicate before applying
        // the bundled overwrite, so the caregiver always has a recovery path.
        if duplicateFirst, let source = sceneToUpdate {
            _ = BlasterScene.duplicate(of: source, in: modelContext,
                                       authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                                       authorName: DeviceProfileStore.authorName(context: modelContext))
            try? modelContext.save()
        }

        sceneToUpdate = nil
        guard BootstrapLoader.updateSystemScene(context: modelContext) else { return }
        bundleUpdateAvailable = BootstrapLoader.isBundleUpdateAvailable()
        sentenceEngine.clearSelection()
    }

    func duplicateScene(_ scene: BlasterScene) {
        _ = BlasterScene.duplicate(of: scene, in: modelContext,
                                   authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                                   authorName: DeviceProfileStore.authorName(context: modelContext))
        try? modelContext.save()
    }

    func activateScene(_ scene: BlasterScene) {
        try? scene.activate(context: modelContext)
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
        let scene = BlasterScene(name: name.isEmpty ? "New Board" : name)
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
