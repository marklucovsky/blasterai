// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneCoverView.swift
//  claudeBlast
//
//  Choose the picture that stands for a scene or a page where something links
//  to it. See `SceneCover` and `PageCover`.
//

import SwiftUI
import SwiftData

/// A scene's cover: what a topic on My Topics shows.
struct SceneCoverView: View {
    @Bindable var scene: BlasterScene

    var body: some View {
        CoverPickerView(subject: .scene(scene))
    }
}

/// The picture for a scene or a page: any word's, a photo, or AI art.
///
/// Both kinds of cover are a tile of their own (`scenecover_…`,
/// `pagecover_…`) whose picture borrows a word's or holds its own, so the
/// label stays the scene's or page's name whichever picture it shows.
struct CoverPickerView: View {
    enum Subject {
        case scene(BlasterScene)
        case page(String, in: BlasterScene)

        var scene: BlasterScene {
            switch self {
            case .scene(let scene), .page(_, let scene): scene
            }
        }
    }

    let subject: Subject

    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    /// Made in `onAppear`, never while the body is built: a model written from
    /// a body is the "setting value during update" crash.
    @State private var cover: TileModel?
    @State private var cropTarget: CropTarget?
    @State private var photoError: String?
    @State private var search = ""

    private struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var title: String {
        switch subject {
        case .scene(let scene): scene.name
        case .page(let key, let scene): scene.page(withKey: key)?.title ?? PageNaming.displayName(key)
        }
    }

    /// Words to start from: the page's own, then the rest of the scene's.
    private var suggestions: [String] {
        switch subject {
        case .scene(let scene):
            return SceneCover.candidateWords(of: scene)
        case .page(let key, let scene):
            let own = scene.page(withKey: key).map { page in
                page.tiles.filter { !$0.isEmptyCell && $0.link.isEmpty && !$0.key.hasPrefix("<") }.map(\.key)
            } ?? []
            var seen = Set<String>()
            return (own + SceneCover.candidateWords(of: scene)).filter { seen.insert($0).inserted }
        }
    }

    /// Any word of the vocabulary, best match first.
    private var matches: [String] {
        let query = WordFinder.normalize(search)
        guard !query.isEmpty else { return Array(suggestions.prefix(40)) }
        return allTiles
            .filter { $0.key != cover?.key && !$0.isHiddenFromChild }
            .compactMap { tile in WordFinder.rank(of: query, in: tile).map { (tile, $0) } }
            .sorted { ($0.1, $0.0.key.count, $0.0.key) < ($1.1, $1.0.key.count, $1.0.key) }
            .prefix(40)
            .map(\.0.key)
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
                            Text(title).font(.headline)
                        }
                        Spacer()
                    }
                } footer: {
                    switch subject {
                    case .scene:
                        Text("This picture stands for the whole scene wherever it is linked, such as on a child's My Topics. Use any word's picture, add a photo, or draw one with AI from the scene's description.")
                    case .page:
                        Text("This picture stands for the page on every folder that opens it. Use any word's picture, add a photo, or draw one with AI.")
                    }
                }

                TilePhotoSection(tile: cover, subjectDetail: subjectDetail) { picked in
                    cropTarget = CropTarget(image: picked)
                }

                Section {
                    TextField("Search all words", text: $search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    let lookup = tileLookup
                    ForEach(matches, id: \.self) { word in
                        Button { use(word) } label: {
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
                } header: {
                    Text("Use a Word's Picture")
                } footer: {
                    if search.isEmpty { Text("Words from this \(isPage ? "page and scene" : "scene"). Search to use any word.") }
                }
            }
        }
        .navigationTitle("Cover")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if cover == nil {
                switch subject {
                case .scene(let scene):
                    cover = SceneCover.ensure(for: scene, context: modelContext)
                case .page(let key, let scene):
                    cover = PageCover.ensureOwn(forPage: key, in: scene, context: modelContext)
                }
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

    private var isPage: Bool {
        if case .page = subject { return true }
        return false
    }

    /// AI art of a scene's cover draws its description, not just its name.
    private var subjectDetail: String {
        switch subject {
        case .scene(let scene): scene.descriptionText
        case .page: ""
        }
    }

    private func use(_ word: String) {
        guard let cover else { return }
        SceneCover.use(word: word, on: cover)
        try? modelContext.save()
        resolver.invalidateAliases()
        resolver.invalidatePhoto(for: cover.key)
    }
}
