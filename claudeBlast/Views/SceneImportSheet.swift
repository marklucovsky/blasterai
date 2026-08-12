// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImportSheet.swift
//  claudeBlast
//
//  Confirm-before-import preview for a .blasterscene file (file open / iMessage
//  share / in-app picker). Shows what the import adds — new words, auto-filled
//  art for words you have without an image — and asks per-word consent before
//  replacing any image you already customized.
//

import SwiftUI
import SwiftData
import UIKit

struct SceneImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver

    @State private var preview: ExportableScene?
    @State private var error: String?
    @State private var importResult: SceneImporter.ImportResult?

    // Analysis vs this device's vocabulary.
    @State private var newWords: [ExportableTile] = []
    @State private var fillWords: [ExportableTile] = []
    @State private var collisions: [ExportableTile] = []
    /// Device's current image for each collision key (the "Yours" thumbnail).
    @State private var deviceImage: [String: UIImage] = [:]
    /// Per-collision choice: true = take the shared image, false = keep yours.
    @State private var useShared: [String: Bool] = [:]

    /// Conflict detected before writing (an update to a locally-edited scene).
    @State private var conflict: SceneImporter.SceneImportConflict = .none
    /// The resolution actually applied — for the result banner's wording.
    @State private var lastResolution: SceneImporter.SceneImportResolution?
    /// Receiver's local "from …" tag for an import that carried no author.
    @State private var receiverLabel: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Import Failed", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if let preview {
                    importPreview(preview)
                } else {
                    ProgressView("Loading scene…")
                }
            }
            .navigationTitle("Import Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .task { loadPreview() }
    }

    // MARK: - Preview

    @ViewBuilder
    private func importPreview(_ scene: ExportableScene) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    LabeledContent("Name", value: scene.name)
                    if !scene.description.isEmpty {
                        LabeledContent("Description", value: scene.description)
                    }
                    LabeledContent("Pages", value: "\(scene.pages.count)")
                    let tileCount = scene.pages.reduce(0) { $0 + $1.tiles.count }
                    LabeledContent("Tiles", value: "\(tileCount)")
                }

                if !newWords.isEmpty {
                    Section {
                        thumbStrip(newWords)
                    } header: {
                        Label("Adds \(newWords.count) new word\(newWords.count == 1 ? "" : "s") to your vocabulary",
                              systemImage: "sparkles")
                    }
                }

                if !fillWords.isEmpty {
                    Section {
                        thumbStrip(fillWords)
                    } header: {
                        Label("Adds art for \(fillWords.count) word\(fillWords.count == 1 ? "" : "s") you have without an image",
                              systemImage: "photo.badge.plus")
                    }
                }

                if !collisions.isEmpty {
                    Section {
                        ForEach(collisions, id: \.key) { tile in
                            collisionRow(tile)
                        }
                    } header: {
                        Label("\(collisions.count) word\(collisions.count == 1 ? "" : "s") already have your own image",
                              systemImage: "exclamationmark.2")
                    } footer: {
                        Text("Choose which image to keep. Your image is kept unless you pick the shared one.")
                    }
                }

                if newWords.isEmpty && fillWords.isEmpty && collisions.isEmpty {
                    Section {
                        Label("No vocabulary changes — everything is already on this device.",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let result = importResult {
                importResultBanner(result)
            } else {
                importActions()
            }
        }
    }

    /// Bottom action area: a single Import button, or — when this file updates a
    /// scene the receiver has locally edited — a keep-mine / take-update /
    /// keep-both prompt.
    @ViewBuilder
    private func importActions() -> some View {
        VStack(spacing: 10) {
            if case .modifiedExisting(let name) = conflict {
                VStack(alignment: .leading, spacing: 3) {
                    Label("You've edited your copy of \u{201C}\(name)\u{201D}",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                    Text("This file is a newer version. Choose what to do with your edited copy:")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { performImport(resolution: .keepBoth) } label: {
                    Label("Keep Both", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button(role: .destructive) { performImport(resolution: .takeUpdate) } label: {
                    Label("Replace Mine with the Update", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                Button { performImport(resolution: .keepMine) } label: {
                    Label("Keep Mine (skip the update)", systemImage: "hand.raised").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            } else {
                Button { performImport() } label: {
                    Label("Import Scene", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding()
    }

    /// Horizontal strip of word thumbnails (shared image or letter placeholder).
    @ViewBuilder
    private func thumbStrip(_ tiles: [ExportableTile]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(tiles, id: \.key) { tile in
                    VStack(spacing: 3) {
                        thumb(sharedImage(tile), wordClass: tile.wordClass, name: tile.displayName)
                        Text(tile.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1).frame(width: 56)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A collision row: the word, with tappable Yours / Shared image choices.
    @ViewBuilder
    private func collisionRow(_ tile: ExportableTile) -> some View {
        let shared = useShared[tile.key] ?? false
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.displayName).font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                choice(label: "Yours", image: deviceImage[tile.key], wordClass: tile.wordClass,
                       name: tile.displayName, selected: !shared) { useShared[tile.key] = false }
                choice(label: "Shared", image: sharedImage(tile), wordClass: tile.wordClass,
                       name: tile.displayName, selected: shared) { useShared[tile.key] = true }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func choice(label: String, image: UIImage?, wordClass: String, name: String,
                        selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                thumb(image, wordClass: wordClass, name: name)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                Label(label, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumb(_ image: UIImage?, wordClass: String, name: String) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(colorForWordClass(wordClass))
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.headline).bold().foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func importResultBanner(_ result: SceneImporter.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(bannerTitle(result), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.headline)
            if result.wasUpdate {
                Text("This scene was already on your device (matched by id) — refreshed in place, not duplicated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if result.newTileCount > 0 {
                Text("\(result.newTileCount) new word\(result.newTileCount == 1 ? "" : "s") added").font(.caption)
            }
            if !result.imageUpdatedKeys.isEmpty {
                Text("\(result.imageUpdatedKeys.count) image\(result.imageUpdatedKeys.count == 1 ? "" : "s") updated").font(.caption)
            }
            if !result.skippedKeys.isEmpty {
                Text("\(result.skippedKeys.count) tile(s) not found: \(result.skippedKeys.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
            // The file carried no author — let the receiver tag who it's from
            // ("from Greta"), like naming a contact. Optional; saved on Done too.
            if result.needsReceiverLabel {
                Divider().padding(.vertical, 2)
                Text("This scene didn't include an author. Tag who it's from (optional):")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g. from Greta", text: $receiverLabel)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .onSubmit { saveReceiverLabel(result.scene) }
            }
            Button("Done") {
                if result.needsReceiverLabel { saveReceiverLabel(result.scene) }
                onDismiss()
            }
            .buttonStyle(.bordered).padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.green.opacity(0.1)))
        .padding(.horizontal)
    }

    // MARK: - Data

    private func sharedImage(_ tile: ExportableTile) -> UIImage? {
        guard let b64 = tile.imageData, let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    private func loadPreview() {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let scene = try SceneImporter.preview(data)
            preview = scene
            // Detect (without writing) whether this updates a scene the receiver
            // has locally edited — so we can prompt instead of clobbering.
            conflict = SceneImporter.conflict(for: data, context: modelContext)

            let deviceTiles = (try? modelContext.fetch(FetchDescriptor<TileModel>())) ?? []
            let analysis = SceneImporter.analyze(scene, deviceTiles: deviceTiles)
            newWords = analysis.newWords
            fillWords = analysis.fillWords
            collisions = analysis.collisions

            let byKey = Dictionary(deviceTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            for tile in collisions {
                if let data = byKey[tile.key]?.userImageData, let img = UIImage(data: data) {
                    deviceImage[tile.key] = img
                }
            }
            useShared = Dictionary(collisions.map { ($0.key, false) }, uniquingKeysWith: { first, _ in first })
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performImport(resolution: SceneImporter.SceneImportResolution? = nil) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let accepted = Set(useShared.filter { $0.value }.map { $0.key })
            let result = try SceneImporter.importJSON(
                data, context: modelContext,
                sourceURL: url.scheme == "https" ? url.absoluteString : "",
                acceptedImageCollisions: accepted,
                resolution: resolution)
            // Re-render any tiles whose image was filled or replaced.
            for key in result.imageUpdatedKeys { resolver.invalidatePhoto(for: key) }
            lastResolution = resolution
            importResult = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bannerTitle(_ result: SceneImporter.ImportResult) -> String {
        switch lastResolution {
        case .keepMine: return "Kept Your Version"
        case .keepBoth: return "Imported as a Copy"
        default:        return result.wasUpdate ? "Updated" : "Imported"
        }
    }

    private func saveReceiverLabel(_ scene: BlasterScene) {
        scene.receivedLabel = receiverLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
    }
}
