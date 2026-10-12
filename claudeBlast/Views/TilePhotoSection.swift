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
    /// The AI controls start folded away. The Photo section's job is the photo,
    /// and a caregiver reaching for it usually wants the camera roll — three
    /// buttons, a toggle and a text field stacked above that made the common
    /// action the hardest one to find.
    @State private var showArtOptions = false
    /// The style currently being filled, so its row can show a spinner.
    @State private var fillingStyle: String? = nil

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

            // Status sits between the two actions, above the Artwork rows. At the
            // bottom of the section it fell below the fold once Artwork was
            // expanded: a caregiver tapped Classic, saw the spinner stop, and had
            // to know to scroll down to learn the key can't draw.
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

            if !apiKey.isEmpty {
                DisclosureGroup("Artwork", isExpanded: $showArtOptions) {
                    styleCoverage

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
                .font(.subheadline)
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

    /// This word's art, style by style, with a one-tap fill for each gap.
    ///
    /// The per-tile mirror of the scene editor's Art Coverage, and it exists for
    /// the same reason: Regenerate draws the word *afresh*, so with "Generate all
    /// styles" on it replaces the picture the caregiver picked and kept. There
    /// was no way to say "leave what I have and fill the rest" for one word.
    ///
    /// Filling runs through `TileArtCompletion`, the same code the scene-level
    /// batch uses, so the two surfaces cannot mean different things by it.
    @ViewBuilder
    private var styleCoverage: some View {
        let _ = resolver.revision       // re-render as art lands
        let gaps = TileArtCompletion.incompleteStyles(for: tile, resolver: resolver)
        if gaps.isEmpty {
            Label("Art in every style", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            ForEach(gaps, id: \.style.id) { work in
                Button {
                    Task { await fill(work) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(work.style.displayName)
                                .foregroundStyle(.primary)
                            // Named apart because they are different work: a
                            // recolour keeps this figure, a drawing makes a new one.
                            // Named, not counted: "missing 2 of 3" sat next to
                            // the scene editor's "1 word to recolor" for the same
                            // style and read as a contradiction. The scene counts
                            // words; this counts tones within one style, and
                            // saying which ones removes the question.
                            Text(work.needsDrawing
                                 ? "not drawn in this style yet"
                                 : "missing \(work.missing.map(\.shortName).joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if fillingStyle == work.style.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: work.needsDrawing ? "wand.and.stars" : "square.on.square")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .font(.caption)
                .disabled(isLoading || isGenerating || fillingStyle != nil)
            }
            // Mirrors the scene editor's "Finish all N styles". Only shown with
            // more than one gap: with a single one this would be the row above
            // it, worded differently.
            if gaps.count > 1 {
                Button {
                    Task { for work in gaps { await fill(work) } }
                } label: {
                    Label("Fill all \(gaps.count) styles",
                          systemImage: "square.stack.3d.up.fill")
                }
                .font(.caption.weight(.medium))
                .disabled(isLoading || isGenerating || fillingStyle != nil)
            }
        }
    }

    /// Fill one style's gap, leaving every picture this tile already has alone.
    private func fill(_ work: TileArtCompletion.Work) async {
        fillingStyle = work.style.id
        errorMessage = nil
        defer { fillingStyle = nil }
        let images = await TileArtCompletion.generate(
            completing: work.style, for: tile, apiKey: apiKey, resolver: resolver)
        for (set, image) in images.images {
            if let err = TilePhotoCommit.applyVariant(image, to: tile, imageSet: set,
                                                      context: modelContext, resolver: resolver) {
                errorMessage = err
            }
        }
        if images.isEmpty {
            errorMessage = images.failureMessage ?? "Couldn't generate \(work.style.displayName)."
        } else if images.images.count < work.missing.count {
            // Name what is still missing rather than reporting a bare success —
            // a style that silently never appears reads as the app ignoring it.
            let landed = Set(images.images.keys)
            let missing = work.missing.filter { !landed.contains($0) }.map(\.shortName)
            let what = "Couldn't generate: \(missing.joined(separator: ", "))."
            errorMessage = images.failureMessage.map { "\(what) \($0)" } ?? what
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
        let plan = ArtPlan.plan(activeSet: resolver.activeSet)
        let expected = ArtPlan.expectedSets(plan)
        let images = await TileImageGenerator.generate(
            displayName: tile.displayName, wordClass: tile.wordClass,
            plan: plan, detail: imageDetail, apiKey: apiKey)

        for (set, image) in images.images {
            if let err = TilePhotoCommit.applyVariant(image, to: tile, imageSet: set,
                                                      context: modelContext, resolver: resolver) {
                errorMessage = err
            }
        }
        // The reason when there is one, the symptom when there isn't.
        //
        // This button used to fail in complete silence: `generate` swallowed the
        // error and handed back an empty dictionary, so an out-of-credit key and
        // a word the model refused to draw were indistinguishable — and neither
        // said anything at all.
        if images.isEmpty {
            errorMessage = images.failureMessage ?? "Couldn't generate an image."
        } else if images.images.count < expected.count {
            // Name what is missing rather than reporting a bare success — a style
            // that silently never appears reads as the app ignoring the request.
            let missing = expected.filter { images[$0] == nil }.map(\.shortName)
            let what = "Couldn't generate: \(missing.joined(separator: ", "))."
            errorMessage = images.failureMessage.map { "\(what) \($0)" } ?? what
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
            errorMessage = OpenAIFailure.caregiverMessage(for: error)
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
            // `artKey`, not `key`: reads resolve the alias, so a write that did
            // not would store an aliased tile's art where nothing looks.
            TileArtVariant.upsert(tileKey: tile.artKey, imageSet: imageSet,
                                  imageData: processed, context: context)
            try context.save()
            resolver.invalidateVariants(for: tile.artKey)
            return nil
        } catch let err as TilePhotoProcessor.ProcessError {
            return err.errorDescription
        } catch {
            return "Couldn't save that image."
        }
    }
}
