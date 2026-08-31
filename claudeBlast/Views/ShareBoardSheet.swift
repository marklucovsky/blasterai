// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ShareBoardSheet.swift
//  claudeBlast
//
//  The one place a scene or a page leaves the app.
//

import SwiftUI
import SwiftData

/// What is being shared.
///
/// The unit is **whatever the caregiver navigated to**. Both levels offer the
/// same destinations; only the native file differs, because a scene and a page
/// mean different things on arrival — a scene becomes a board, a page becomes
/// vocabulary.
enum ShareSubject {
    case scene(BlasterScene)
    case page(PageSpec, in: BlasterScene)

    var scene: BlasterScene {
        switch self {
        case .scene(let s): return s
        case .page(_, let s): return s
        }
    }

    var title: String {
        switch self {
        case .scene(let s): return s.name.isEmpty ? "Scene" : s.name
        case .page(let p, _): return p.key
        }
    }

    /// Every tile key involved, in board order.
    var tileKeys: [String] {
        switch self {
        case .scene(let s): return s.pages.flatMap { $0.tiles.map(\.key) }
        case .page(let p, _): return p.tiles.map(\.key)
        }
    }

    var basename: String {
        let raw = title.sanitizedFilename
        return raw.isEmpty ? "blaster" : raw
    }
}

/// Where a share can go. PDF and OBZ join this list in later sessions; the sheet
/// is built to grow a row rather than be rewritten.
private enum ShareDestination: String, Identifiable, CaseIterable {
    case nativeFile
    case tileImages

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nativeFile: return "square.and.arrow.up.on.square"
        case .tileImages: return "photo.on.rectangle.angled"
        }
    }
}

struct ShareBoardSheet: View {
    let subject: ShareSubject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TileImageResolver.self) private var imageResolver
    @Query private var allTiles: [TileModel]

    @State private var setScope: ExportSetScope = .activeSet
    @State private var exported: ExportedFile?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var isPage: Bool {
        if case .page = subject { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ShareDestination.allCases) { destination in
                        Button { produce(destination) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(for: destination))
                                        .foregroundStyle(.primary)
                                    Text(blurb(for: destination))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: destination.icon)
                            }
                        }
                        .disabled(isWorking)
                    }
                } header: {
                    Text("Share \(isPage ? "Page" : "Scene")")
                } footer: {
                    Text(isPage
                         ? "A shared page travels as a vocabulary pack: the words and their pictures, with no layout. Whoever receives it can build a page from those words whenever they like."
                         : "A shared scene arrives as a scene — the same pages, laid out the same way.")
                }

                Section {
                    Picker("Styles", selection: $setScope) {
                        ForEach(ExportSetScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                } header: {
                    Text("Pictures")
                } footer: {
                    Text("Applies to exported images. Blaster files always carry every style, so the person receiving them sees your words in whichever style they use.")
                }

                if isWorking {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exported) { file in
                ActivityView(items: [file.url])
            }
            .alert("Share failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Copy

    private func title(for destination: ShareDestination) -> String {
        switch destination {
        case .nativeFile: return isPage ? "Blaster Pack" : "Blaster Scene"
        case .tileImages: return "Tile Pictures"
        }
    }

    private func blurb(for destination: ShareDestination) -> String {
        switch destination {
        case .nativeFile:
            return isPage ? "Words and pictures, for another Blaster" : "The whole board, for another Blaster"
        case .tileImages:
            return "A folder of PNG images"
        }
    }

    // MARK: - Producing the file

    private func produce(_ destination: ShareDestination) {
        isWorking = true
        defer { isWorking = false }
        do {
            switch destination {
            case .nativeFile: exported = try nativeFile()
            case .tileImages: exported = try tileImages()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func nativeFile() throws -> ExportedFile {
        switch subject {
        case .scene(let scene):
            // Stamp identity and provenance before the file leaves, exactly as
            // the old scenes-tab export did — a shared scene without an id can
            // never be recognised as an update on the far side.
            let authorID = DeviceProfileStore.ensureAuthorID(context: modelContext)
            let authorName = DeviceProfileStore.authorName(context: modelContext)
            scene.ensureIdentity(authorID: authorID, authorName: authorName)
            if scene.authorName.isEmpty, !authorName.isEmpty,
               scene.sceneID.hasPrefix(authorID + "/") {
                scene.authorName = authorName
            }
            try? modelContext.save()

            let defaultKeys = Set(allTiles.filter(\.isSystem).map(\.key))
            let data = try SceneExporter.exportJSON(scene,
                                                    defaultTileKeys: defaultKeys,
                                                    tileLookup: tileLookup,
                                                    context: modelContext)
            return try ExportedFile.write(data, named: "\(subject.basename).\(BlasterSceneFormat.fileExtension)")

        case .page(let page, let scene):
            let data = try PackExporter.exportPageJSON(page, from: scene,
                                                       tileLookup: tileLookup,
                                                       context: modelContext)
            return try ExportedFile.write(data, named: "\(subject.basename).\(BlasterPackFormat.fileExtension)")
        }
    }

    private func tileImages() throws -> ExportedFile {
        let url = try TileImageExporter.exportZip(keys: subject.tileKeys,
                                                  scope: setScope,
                                                  resolver: imageResolver,
                                                  basename: subject.basename)
        return ExportedFile(url: url, displayName: url.lastPathComponent)
    }
}
