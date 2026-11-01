// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneCoverView.swift
//  claudeBlast
//
//  Choose the picture that stands for a scene where something links to it.
//  See `SceneCover`.
//

import SwiftUI
import SwiftData

struct SceneCoverView: View {
    @Bindable var scene: BlasterScene

    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    /// Made in `onAppear`, never while the body is built: a model written from
    /// a body is the "setting value during update" crash.
    @State private var cover: TileModel?
    @State private var cropTarget: CropTarget?
    @State private var photoError: String?

    private struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Form {
            if let cover {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            TileImageView(key: cover.key, wordClass: cover.wordClass)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(scene.name).font(.headline)
                        }
                        Spacer()
                    }
                } footer: {
                    Text("This picture stands for the whole scene wherever it is linked, such as on a child's My Topics. Pick one of the scene's words, or add a photo.")
                }

                TilePhotoSection(tile: cover) { picked in
                    cropTarget = CropTarget(image: picked)
                }

                Section("Use a Word's Picture") {
                    let lookup = tileLookup
                    ForEach(SceneCover.candidateWords(of: scene), id: \.self) { word in
                        Button {
                            SceneCover.use(word: word, on: cover)
                            try? modelContext.save()
                            resolver.invalidateAliases()
                            resolver.invalidatePhoto(for: cover.key)
                        } label: {
                            HStack(spacing: 12) {
                                TileImageView(key: word, wordClass: lookup[word]?.wordClass ?? "")
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(lookup[word]?.displayName ?? word)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if !cover.hasUserImage, cover.bundleImage == word {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cover")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if cover == nil {
                cover = SceneCover.ensure(for: scene, context: modelContext)
                try? modelContext.save()
                resolver.invalidateAliases()
            }
        }
        .fullScreenCover(item: $cropTarget) { target in
            SquareImageCropper(
                image: target.image,
                onCrop: { square in
                    cropTarget = nil
                    if let cover {
                        photoError = TilePhotoCommit.apply(
                            square, to: cover,
                            context: modelContext, resolver: resolver)
                    }
                },
                onCancel: { cropTarget = nil }
            )
        }
        .alert("Couldn't Save Photo",
               isPresented: Binding(get: { photoError != nil },
                                    set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
    }
}
