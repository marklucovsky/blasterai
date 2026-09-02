// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PackImportSheet.swift
//  claudeBlast
//
//  Confirm-before-import preview for a .blasterpack file.
//

import SwiftUI
import SwiftData
import UIKit

/// Routes an incoming file to the sheet that understands it.
///
/// A scene and a pack arrive by the identical road — a file open, an iMessage
/// attachment, the in-app picker — and differ only in what they mean. One view
/// owns that decision so no caller has to repeat it, and so a file with the
/// wrong extension fails with an explanation rather than a decode error.
struct ImportRouteSheet: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        if url.pathExtension.lowercased() == BlasterPackFormat.fileExtension {
            PackImportSheet(url: url, onDismiss: onDismiss)
        } else {
            SceneImportSheet(url: url, onDismiss: onDismiss)
        }
    }
}

struct PackImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver

    @State private var pack: ExportablePack?
    @State private var error: String?
    @State private var result: PackImporter.ImportResult?

    /// Words the device already has — their identity will not be touched.
    @State private var knownKeys: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Import Failed", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if let result {
                    resultView(result)
                } else if let pack {
                    preview(pack)
                } else {
                    ProgressView("Loading pack…")
                }
            }
            .navigationTitle("Add Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { onDismiss() }
                }
                if let pack, result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { performImport(pack) }
                    }
                }
            }
        }
        .task { load() }
    }

    // MARK: - Preview

    @ViewBuilder
    private func preview(_ pack: ExportablePack) -> some View {
        let newWords = pack.words.filter { !knownKeys.contains($0.key) }
        let existing = pack.words.filter { knownKeys.contains($0.key) }

        List {
            Section {
                LabeledContent("Pack", value: pack.displayName)
                if let author = pack.authorName, !author.isEmpty {
                    LabeledContent("From", value: author)
                }
                if let scene = pack.sourceScene, !scene.isEmpty {
                    LabeledContent("Made for", value: scene)
                }
            } footer: {
                // Say plainly what this does and does not do. A caregiver who
                // expects a ready-made page and gets loose words has been
                // surprised by the app, which is the one thing an AAC tool
                // cannot afford to do.
                Text("These words join your vocabulary with their pictures. No page or board is created — you can build one from them whenever you like, using **New Page → From a pack**.")
            }

            if !newWords.isEmpty {
                Section("Adds \(newWords.count) word\(newWords.count == 1 ? "" : "s")") {
                    ForEach(newWords, id: \.key) { word in
                        wordRow(word)
                    }
                }
            }

            if !existing.isEmpty {
                Section {
                    ForEach(existing, id: \.key) { word in
                        wordRow(word)
                    }
                } header: {
                    Text("Already in your vocabulary")
                } footer: {
                    Text("These stay exactly as they are. Pictures are added only for styles you have none for.")
                }
            }
        }
    }

    private func wordRow(_ word: ExportablePackWord) -> some View {
        HStack(spacing: 12) {
            packArtThumbnail(word)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.displayName.isEmpty ? word.key : word.displayName)
                Text(word.wordClass)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The picture this word will actually have **on this device**.
    ///
    /// It used to show `word.art?.first` — the first embedded variant, sorted by
    /// set id, which is an arbitrary one of the *sender's* styles. That was wrong
    /// twice over: a preview in the sender's skin misrepresents what the
    /// recipient is about to get, and system words carry no embedded art at all
    /// (deliberately — the recipient already ships it), so most rows drew an
    /// empty grey box.
    ///
    /// So: resolve locally first, which covers every word this device already
    /// has, and fall back to the embedded art only for a genuinely new word —
    /// preferring the entry for the style the recipient is actually using.
    @ViewBuilder
    private func packArtThumbnail(_ word: ExportablePackWord) -> some View {
        if let image = localArt(for: word.key) ?? embeddedArt(word) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
        }
    }

    /// Art already on this device, in the recipient's own style.
    private func localArt(for key: String) -> UIImage? {
        resolver.image(for: key, in: resolver.activeSet)
            ?? resolver.image(for: key, in: ImageSetID.universalBackfill)
    }

    /// Art carried by the file, preferring the recipient's active style so a new
    /// word previews as close to its eventual appearance as the pack allows.
    private func embeddedArt(_ word: ExportablePackWord) -> UIImage? {
        let art = word.art ?? []
        let preferred = art.first { $0.imageSet == resolver.activeSet.rawValue }
            ?? art.first { $0.imageSet == ImageSetID.universalBackfill.rawValue }
            ?? art.first
        let encoded = preferred?.imageData ?? word.imageData
        guard let encoded, let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Result

    @ViewBuilder
    private func resultView(_ result: PackImporter.ImportResult) -> some View {
        List {
            Section {
                LabeledContent("Added", value: "\(result.newWordCount) new word\(result.newWordCount == 1 ? "" : "s")")
                if result.existingWordCount > 0 {
                    LabeledContent("Already had", value: "\(result.existingWordCount)")
                }
                if !result.artUpdatedKeys.isEmpty {
                    LabeledContent("Pictures added", value: "\(result.artUpdatedKeys.count)")
                }
            } header: {
                Text(result.wasUpdate ? "Pack updated" : "Pack added")
            } footer: {
                Text("Find these words under **\(result.pack.displayName)** in the tile picker, or start a board from them with **New Scene from Collections**.")
            }

            if !result.oversizedImages.isEmpty {
                Section("Pictures skipped") {
                    ForEach(result.oversizedImages, id: \.self) { key in
                        Text(key).font(.callout)
                    }
                }
            }
        }
    }

    // MARK: - Work

    private func load() {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try PackImporter.preview(data)
            let deviceTiles = (try? modelContext.fetch(FetchDescriptor<TileModel>())) ?? []
            knownKeys = Set(deviceTiles.map(\.key))
            pack = decoded
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performImport(_ pack: ExportablePack) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let imported = try PackImporter.importJSON(data, context: modelContext)
            // Newly arrived art is invisible until the resolver drops its
            // negative caches — it remembers which keys had no variant.
            for key in imported.artUpdatedKeys {
                resolver.invalidateVariants(for: key)
                resolver.invalidatePhoto(for: key)
            }
            result = imported
        } catch {
            self.error = error.localizedDescription
        }
    }
}
