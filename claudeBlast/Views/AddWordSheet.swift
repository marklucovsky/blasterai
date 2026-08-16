// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AddWordSheet.swift
//  claudeBlast
//
//  Create a caregiver vocabulary word inline while authoring a page. Collisions
//  are prevented in the UI: any word class already used by this key is disabled
//  in the type picker, so you can only land on a free class. Creating then makes
//  either a plain new key (no collision) or a homograph `<key>_<wordClass>` (the
//  key exists in another class), label unchanged.
//  Optionally attaches a photo (pick → square crop → CloudKit-safe compress) so a
//  word + its picture can land in one step.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddWordSheet: View {
    let initialWord: String
    let existingTiles: [TileModel]
    let defaultWordClass: String
    /// Called with the created (or existing-duplicate) tile to place on the page.
    let onCommit: (TileModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver

    @State private var displayName: String
    @State private var wordClass: String

    // Inline photo (held until the word is created).
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropTarget: CropTarget?
    @State private var processedPhoto: Data?               // camera photo → userImageData override
    @State private var generatedArt: [String: Data] = [:]  // imageSetRaw → AI art → TileArtVariant
    @State private var photoPreview: UIImage?
    @State private var photoError: String?
    @State private var isGenerating = false
    @State private var imageDetail = ""
    @AppStorage(AppSettingsKey.generateAllStyles) private var generateAllStyles = false

    private var apiKey: String { OpenAIKeyVault.currentKey() ?? "" }

    private struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    init(initialWord: String,
         existingTiles: [TileModel],
         defaultWordClass: String,
         onCommit: @escaping (TileModel) -> Void) {
        self.initialWord = initialWord
        self.existingTiles = existingTiles
        self.defaultWordClass = defaultWordClass
        self.onCommit = onCommit
        let name = initialWord.trimmingCharacters(in: .whitespacesAndNewlines)
        _displayName = State(initialValue: name)
        // Start on a caregiver-selectable class that isn't already taken by this
        // key (structural classes can't leak in via the caller's default).
        let selectable = VocabularyClasses.caregiverSelectable.map(\.name)
        let taken = Self.takenClasses(for: name, in: existingTiles)
        let preferred = (selectable.contains(defaultWordClass) && !taken.contains(defaultWordClass))
            ? defaultWordClass : nil
        let initial = preferred
            ?? selectable.first { !taken.contains($0) }
            ?? selectable.first ?? "describe"
        _wordClass = State(initialValue: initial)
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Word classes already used by this word — disabled in the picker so a
    /// same-word/same-class duplicate can't be created (only a homograph in a
    /// free class, or a brand-new key). Homographs share the displayName, not
    /// the key (pony/animal is key "pony", pony/food is key "pony_food"), so we
    /// match on displayName (plus the exact base key for safety).
    private var takenClasses: Set<String> {
        Self.takenClasses(for: trimmedName, in: existingTiles)
    }

    private static func takenClasses(for name: String, in tiles: [TileModel]) -> Set<String> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let base = TileModel.normalizeKey(trimmed)
        return Set(tiles
            .filter { $0.key == base || $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
            .map(\.wordClass))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $displayName)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                        alignment: .leading, spacing: 8
                    ) {
                        ForEach(VocabularyClasses.caregiverSelectable) { cls in
                            classChip(cls)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Type")
                } footer: {
                    // Show the scheme rather than a free color control: tile color
                    // is derived from the word class (no manual picker yet).
                    Text(takenClasses.isEmpty
                         ? "Tile color is set by the word class."
                         : "Tile color is set by the word class. Greyed types already exist for “\(trimmedName)”.")
                }

                Section("Photo") {
                    if let photoPreview {
                        HStack {
                            Image(uiImage: photoPreview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                            Button(role: .destructive) {
                                processedPhoto = nil
                                generatedArt = [:]
                                self.photoPreview = nil
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photoPreview == nil ? "Add Photo" : "Replace Photo",
                              systemImage: "photo.badge.plus")
                    }
                    .disabled(isGenerating)

                    if !apiKey.isEmpty {
                        Toggle("Generate all styles", isOn: $generateAllStyles)
                            .font(.caption)
                            .disabled(isGenerating)

                        Button {
                            Task { await generateImage() }
                        } label: {
                            Label(photoPreview == nil ? "Generate with AI" : "Regenerate (fresh image)",
                                  systemImage: "wand.and.stars")
                        }
                        .disabled(isGenerating || trimmedName.isEmpty)

                        if photoPreview != nil {
                            Button {
                                Task { await refineImage() }
                            } label: {
                                Label("Refine this image", systemImage: "wand.and.rays")
                            }
                            .disabled(isGenerating || imageDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        // Detail / refinement field, with a one-tap clear.
                        HStack(spacing: 6) {
                            TextField(photoPreview == nil ? "Add a detail (optional)" : "Describe a change, e.g. give him red hair",
                                      text: $imageDetail, axis: .vertical)
                                .font(.caption)
                                .lineLimit(1...2)
                                .disabled(isGenerating)
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
                                .disabled(isGenerating)
                                .accessibilityLabel("Clear text")
                            }
                        }

                        if photoPreview != nil {
                            Text("Refine keeps this picture and applies your change. Regenerate makes a brand-new image.")
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

                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Generating image…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let photoError {
                        Text(photoError).font(.caption).foregroundStyle(.red)
                    }
                    Text("Optional. A photo or AI image shows on this tile everywhere it appears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty || takenClasses.contains(wordClass))
                }
            }
            .onChange(of: displayName) { _, _ in
                // If editing the word made the current class collide, hop to a free one.
                if takenClasses.contains(wordClass) {
                    wordClass = VocabularyClasses.caregiverSelectable
                        .map(\.name).first { !takenClasses.contains($0) } ?? wordClass
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(item: $cropTarget) { target in
                SquareImageCropper(
                    image: target.image,
                    onCrop: { square in
                        cropTarget = nil
                        applyCrop(square)
                    },
                    onCancel: { cropTarget = nil }
                )
            }
        }
    }

    /// A selectable, color-coded word-class chip. Classes already used by this
    /// key are greyed and non-tappable (collision prevention).
    @ViewBuilder
    private func classChip(_ cls: VocabularyClass) -> some View {
        let taken = takenClasses.contains(cls.name)
        let selected = wordClass == cls.name
        Button {
            wordClass = cls.name
        } label: {
            HStack(spacing: 6) {
                Circle().fill(cls.color).frame(width: 11, height: 11)
                Text(cls.label).font(.subheadline)
                if taken {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(selected ? cls.color.opacity(0.22) : Color.secondary.opacity(0.12)))
            .overlay(Capsule().strokeBorder(selected ? cls.color : .clear, lineWidth: 2))
            .opacity(taken ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(taken)
    }

    // MARK: - Create

    private func create() {
        let base = TileModel.normalizeKey(trimmedName)
        guard !base.isEmpty, !takenClasses.contains(wordClass) else { return }

        // Key exists in another class → homograph; otherwise a brand-new key.
        let finalKey = existingTiles.contains(where: { $0.key == base })
            ? uniqueKey(base: "\(base)_\(wordClass)")
            : base

        let tile = TileModel(key: finalKey, value: trimmedName, wordClass: wordClass)
        tile.isSystem = false
        if let processedPhoto {
            tile.userImageData = processedPhoto   // camera photo → removable override
        }
        modelContext.insert(tile)
        // AI-generated art is the word's CANONICAL per-style art (synced), keyed to
        // the now-final tile key. The key isn't known until here, so it's held until
        // commit and upserted per style.
        // No longer a failable lookup: any id is storable, because the art was
        // generated for that set and a build that doesn't recognise the id must
        // not throw the image away.
        for (setRaw, data) in generatedArt {
            TileArtVariant.upsert(tileKey: finalKey, imageSet: ImageSetID(setRaw),
                                  imageData: data, context: modelContext)
        }
        try? modelContext.save()
        if processedPhoto != nil { resolver.invalidatePhoto(for: finalKey) }
        if !generatedArt.isEmpty { resolver.invalidateVariants(for: finalKey) }
        onCommit(tile)
        dismiss()
    }

    /// Ensure `base` is unique against existing tiles; append _2, _3, … if taken.
    private func uniqueKey(base: String) -> String {
        let keys = Set(existingTiles.map(\.key))
        guard keys.contains(base) else { return base }
        var n = 2
        while keys.contains("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }

    // MARK: - Photo

    private func loadPhoto(_ item: PhotosPickerItem) async {
        photoError = nil
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = "Couldn't read that photo."
                return
            }
            cropTarget = CropTarget(image: image)
        } catch {
            photoError = "Couldn't read that photo."
        }
    }

    private func applyCrop(_ square: UIImage) {
        photoError = nil
        do {
            let data = try TilePhotoProcessor.process(square)
            processedPhoto = data
            photoPreview = UIImage(data: data)
        } catch let err as TilePhotoProcessor.ProcessError {
            photoError = err.errorDescription
        } catch {
            photoError = "Couldn't process that photo."
        }
    }

    // MARK: - AI image

    /// Generate a first-pass image for the word (no crop step — already square).
    private func generateImage() async {
        isGenerating = true
        photoError = nil
        defer { isGenerating = false }
        let targets = generateAllStyles
            ? ImageSetCatalog.generationTargets(preferring: resolver.activeSet)
            : [resolver.activeSet]
        for set in targets {
            do {
                let image = try await TileImageGenerator.generate(
                    displayName: trimmedName, wordClass: wordClass,
                    imageSet: set, detail: imageDetail, apiKey: apiKey)
                let data = try TilePhotoProcessor.process(image)
                generatedArt[set.rawValue] = data
                if set == resolver.activeSet { photoPreview = UIImage(data: data) }
            } catch let err as TilePhotoProcessor.ProcessError {
                photoError = err.errorDescription
            } catch {
                photoError = (error as? LocalizedError)?.errorDescription ?? "Couldn't generate an image."
            }
        }
        if photoPreview == nil, let first = generatedArt.values.first {
            photoPreview = UIImage(data: first)   // active set wasn't a generation target (e.g. High Contrast)
        }
    }

    /// Refine the current image (image-to-image) with the detail as the change —
    /// each refine builds on the last, so context is preserved in the image.
    private func refineImage() async {
        guard let base = photoPreview else { return }
        isGenerating = true
        photoError = nil
        defer { isGenerating = false }
        do {
            let image = try await TileImageGenerator.edit(
                baseImage: base, instruction: imageDetail, apiKey: apiKey)
            let data = try TilePhotoProcessor.process(image)
            // Refine updates the displayed style's canonical art, not the override.
            generatedArt[resolver.activeSet.rawValue] = data
            photoPreview = UIImage(data: data)
        } catch let err as TilePhotoProcessor.ProcessError {
            photoError = err.errorDescription
        } catch {
            photoError = (error as? LocalizedError)?.errorDescription ?? "Couldn't refine the image."
        }
    }
}
