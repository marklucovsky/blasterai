// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI

/// Read-only preview of a BlasterScene's board, as the child would see it —
/// without activating the scene. Tapping a navigation (linked) tile follows the
/// link between the scene's pages; leaf tiles are inert. Drag/drop editing is a
/// planned follow-on (see the grid page editor work).
struct ScenePreviewBoardView: View {
    let scene: BlasterScene
    let allTiles: [TileModel]

    @Environment(\.dismiss) private var dismiss
    @State private var currentPageKey: String

    init(scene: BlasterScene, allTiles: [TileModel]) {
        self.scene = scene
        self.allTiles = allTiles
        _currentPageKey = State(initialValue: scene.homePageKey)
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var currentPage: PageSpec? {
        scene.page(withKey: currentPageKey) ?? scene.pages.first
    }

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let page = currentPage {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(page.tiles) { entry in
                            previewCell(entry)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView("Empty scene", systemImage: "square.grid.2x2")
                        .padding(.top, 60)
                }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentPageKey != scene.homePageKey {
                        Button { currentPageKey = scene.homePageKey } label: {
                            Label("Home", systemImage: "house.fill")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var pageTitle: String {
        let name = scene.name.isEmpty ? "Preview" : scene.name
        return currentPageKey != scene.homePageKey ? "\(name) · \(currentPageKey)" : name
    }

    @ViewBuilder
    private func previewCell(_ entry: TileEntry) -> some View {
        let tile = tileLookup[entry.key]
        let isLink = !entry.link.isEmpty
        Button {
            guard isLink else { return }
            let dest = entry.link == "<home>" ? scene.homePageKey : entry.link
            if scene.page(withKey: dest) != nil { currentPageKey = dest }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    TileImageView(key: tile?.bundleImage ?? entry.key,
                                  wordClass: tile?.wordClass ?? "")
                        .aspectRatio(1, contentMode: .fit)
                    if isLink {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                            .padding(3)
                    }
                }
                Text(tile?.displayName ?? entry.key)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorForWordClass(tile?.wordClass ?? "").opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
