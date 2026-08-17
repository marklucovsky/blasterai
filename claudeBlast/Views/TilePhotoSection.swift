// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePhotoSection.swift
//  claudeBlast
//
//  Reusable Form section for attaching / removing a caregiver photo on a tile.
//  A photo overrides the tile's picture everywhere it appears (see
//  TileImageResolver) and syncs across the family's devices via CloudKit.
//
//  Presentation split: this section ONLY hosts the PhotosPicker + remove button.
//  Picking reports the chosen image up via `onPick`; the HOST presents the
//  square cropper at its root and commits via `TilePhotoCommit`. Presenting the
//  cropper from inside a Form Section (a non-view anchor) while the system photo
//  picker is still dismissing causes "already presenting" modal conflicts/crashes.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct TilePhotoSection: View {
    @Bindable var tile: TileModel
    /// Called with a freshly picked (uncropped) image. The host presents the
    /// cropper and, on confirm, calls `TilePhotoCommit.apply`.
    let onPick: (UIImage) -> Void

    @Environment(TileImageResolver.self) private var resolver
    @Environment(\.modelContext) private var modelContext

    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var imageDetail = ""
    @AppStorage(AppSettingsKey.generateAllStyles) private var generateAllStyles = false

    private var apiKey: String { OpenAIKeyVault.currentKey() ?? "" }

    /// Whether this tile currently shows a real picture (bundled or AI variant) in
    /// the active set — i.e. there's something to Refine / Regenerate. Reading
    /// `resolver.revision` keeps the labels in sync after art is (re)generated.
    private var hasActiveArt: Bool {
        _ = resolver.revision
        return resolver.image(for: tile.key, in: resolver.activeSet) != nil
    }

    /// Refine is offered only when there's active-set art AND no photo override —
    /// a photo would hide the refined variant, which would be confusing.
    private var canRefine: Bool { hasActiveArt && !tile.hasUserImage }

    var body: some View {
        Section("Photo") {
            if tile.hasUserImage {
                Label("Custom photo set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(role: .destructive, action: removePhoto) {
                    Label("Remove Photo", systemImage: "trash")
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(tile.hasUserImage ? "Replace Photo" : "Add Photo",
                      systemImage: "photo.badge.plus")
            }
            .disabled(isLoading || isGenerating)

            if !apiKey.isEmpty {
                Toggle("Generate all styles", isOn: $generateAllStyles)
                    .font(.caption)
                    .disabled(isLoading || isGenerating)

                Button {
                    Task { await generateImage() }
                } label: {
                    Label(hasActiveArt ? "Regenerate (fresh image)" : "Generate with AI",
                          systemImage: "wand.and.stars")
                }
                .disabled(isLoading || isGenerating)

                if canRefine {
                    Button {
                        Task { await refineImage() }
                    } label: {
                        Label("Refine this image", systemImage: "wand.and.rays")
                    }
                    .disabled(isLoading || isGenerating || imageDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 6) {
                    TextField(canRefine ? "Describe a change, e.g. give her red hair" : "Add a detail to guide the image (optional)",
                              text: $imageDetail, axis: .vertical)
                        .font(.caption)
                        .lineLimit(1...2)
                        .disabled(isLoading || isGenerating)
                        .onChange(of: imageDetail) { _, value in
                            if value.count > TileImageGenerator.maxDetailLength {
                                imageDetail = String(value.prefix(TileImageGenerator.maxDetailLength))
                            }
                        }
                    if !imageDetail.isEmpty {
                        Button { imageDetail = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || isGenerating)
                        .accessibilityLabel("Clear text")
                    }
                }
                if canRefine {
                    Text("Refine keeps this picture and applies your change (active style only). Regenerate makes a brand-new image.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if imageDetail.count >= TileImageGenerator.detailCounterThreshold {
                    Text("\(imageDetail.count)/\(TileImageGenerator.maxDetailLength)")
                        .font(.caption2)
                        .foregroundStyle(imageDetail.count >= TileImageGenerator.maxDetailLength ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if isLoading || isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                    if isGenerating {
                        Text("Generating image…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("A photo replaces this tile's picture everywhere it appears, on every device signed in to your iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    /// Decode the picked item to a UIImage and hand it up for cropping. Awaiting
    /// the transfer also lets the system photo picker finish dismissing before
    /// the host presents the cropper.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that photo."
                return
            }
            onPick(image)
        } catch {
            errorMessage = "Couldn't read that photo."
        }
    }

    /// Generate a first-pass image for this tile and store it directly — the
    /// result is already a centered square, so no crop step.
    private func generateImage() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        let plan = ArtPlan.plan(activeSet: resolver.activeSet, allStyles: generateAllStyles)
        let expected = ArtPlan.expectedSets(plan)
        let images = await TileImageGenerator.generate(
            displayName: tile.displayName, wordClass: tile.wordClass,
            plan: plan, detail: imageDetail, apiKey: apiKey)

        for (set, image) in images {
            if let err = TilePhotoCommit.applyVariant(image, to: tile, imageSet: set,
                                                      context: modelContext, resolver: resolver) {
                errorMessage = err
            }
        }
        if images.isEmpty {
            errorMessage = "Couldn't generate an image."
        } else if images.count < expected.count {
            // Name what is missing rather than reporting a bare success — a style
            // that silently never appears reads as the app ignoring the request.
            let missing = expected.filter { images[$0] == nil }.map(\.shortName)
            errorMessage = "Couldn't generate: \(missing.joined(separator: ", "))."
        }
    }

    /// Image-to-image refine of the active set's current art (bundled or variant),
    /// storing the result as this set's canonical variant. Each refine builds on
    /// the last image, so context is preserved.
    private func refineImage() async {
        guard let base = resolver.image(for: tile.key, in: resolver.activeSet)
                ?? resolver.image(for: tile.key) else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let image = try await TileImageGenerator.edit(
                baseImage: base, instruction: imageDetail, apiKey: apiKey)
            if let err = TilePhotoCommit.applyVariant(image, to: tile, imageSet: resolver.activeSet,
                                                      context: modelContext, resolver: resolver) {
                errorMessage = err
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't refine the image."
        }
    }

    private func removePhoto() {
        tile.userImageData = Data()   // empty == no override; reverts to canonical art
        try? modelContext.save()
        resolver.invalidatePhoto(for: tile.key)
    }
}

// MARK: - Commit helper (shared by every host that uses TilePhotoSection)

enum TilePhotoCommit {
    /// Compress the cropped square into a CloudKit-safe blob and store it on the
    /// tile. Returns a user-facing error string on failure, or nil on success.
    @MainActor
    static func apply(_ square: UIImage,
                      to tile: TileModel,
                      context: ModelContext,
                      resolver: TileImageResolver) -> String? {
        do {
            let processed = try TilePhotoProcessor.process(square)
            tile.userImageData = processed
            try context.save()
            resolver.invalidatePhoto(for: tile.key)
            return nil
        } catch let err as TilePhotoProcessor.ProcessError {
            return err.errorDescription
        } catch {
            return "Couldn't save that photo."
        }
    }

    /// Store an AI-generated image as the tile's CANONICAL art for `imageSet` (a
    /// synced TileArtVariant), not the camera-photo override. Returns a
    /// user-facing error on failure, nil on success.
    @MainActor
    static func applyVariant(_ image: UIImage,
                             to tile: TileModel,
                             imageSet: ImageSetID,
                             context: ModelContext,
                             resolver: TileImageResolver) -> String? {
        do {
            let processed = try TilePhotoProcessor.process(image)
            TileArtVariant.upsert(tileKey: tile.key, imageSet: imageSet,
                                  imageData: processed, context: context)
            try context.save()
            resolver.invalidateVariants(for: tile.key)
            return nil
        } catch let err as TilePhotoProcessor.ProcessError {
            return err.errorDescription
        } catch {
            return "Couldn't save that image."
        }
    }
}
