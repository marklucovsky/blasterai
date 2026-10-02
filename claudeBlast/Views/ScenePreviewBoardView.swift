// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI

/// Read-only preview of a BlasterScene's board, as the child would see it —
/// without activating the scene. Tapping a navigation (linked) tile follows the
/// link between the scene's pages; leaf tiles are inert.
///
/// Laid out on the scene's designed grid (`BlasterScene.designedFor`), whatever
/// device this is — a phone board designed on an iPad previews as the phone
/// will show it. Paged as the board pages, with Home in cell 0, so every word
/// is where the child will find it. Undeclared, this device's own layout.
struct ScenePreviewBoardView: View {
    let scene: BlasterScene
    let allTiles: [TileModel]

    @Environment(\.dismiss) private var dismiss
    @State private var currentPageKey: String
    @State private var displayPage: Int? = 0
    @AppStorage(AppSettingsKey.boardLayout) private var boardLayoutRaw: String =
        BoardLayout.current().rawValue

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

    private var grid: (cols: Int, rows: Int) {
        GridLayoutCalculator.authoringGrid(
            designed: scene.designedLayout,
            isPhone: GridLayoutCalculator.isPhone(screenSize: GridLayoutCalculator.deviceScreenSize),
            deviceLayout: BoardLayout(rawValue: boardLayoutRaw) ?? .standard)
    }

    /// The tiles the board would draw: retired and unreviewed words are gone,
    /// spacers and concealed cells keep their place.
    private func visibleTiles(_ page: PageSpec) -> [TileEntry] {
        page.tiles.filter { $0.isEmptyCell || tileLookup[$0.key]?.isHiddenFromChild != true }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let page = currentPage {
                    GeometryReader { geo in
                        let spec = GridLayoutCalculator.compute(geo: geo.size, grid: grid)
                        let chunks = visibleTiles(page).chunked(into: max(1, spec.perPage - 1))
                        let columns = Array(repeating: GridItem(.fixed(spec.tileSize),
                                                                spacing: spec.horizontalSpacing),
                                            count: spec.cols)
                        TabView(selection: $displayPage) {
                            ForEach(Array((chunks.isEmpty ? [[]] : chunks).enumerated()),
                                    id: \.offset) { index, tiles in
                                LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                                    HomeGridCell(isEnabled: currentPageKey != scene.homePageKey,
                                                 action: { go(to: scene.homePageKey) },
                                                 onOpenMenu: {},
                                                 labelFontSize: spec.labelFontSize)
                                    ForEach(tiles) { entry in
                                        previewCell(entry, labelFontSize: spec.labelFontSize)
                                    }
                                }
                                .padding(.horizontal, spec.horizontalPadding)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .tag(index as Int?)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    }
                } else {
                    ContentUnavailableView("Empty scene", systemImage: "square.grid.2x2")
                        .padding(.top, 60)
                }
            }
            .navigationTitle(pageTitle)
            .navigationSubtitle(gridSubtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentPageKey != scene.homePageKey {
                        Button { go(to: scene.homePageKey) } label: {
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

    private func go(to key: String) {
        currentPageKey = key
        displayPage = 0
    }

    /// "Designed for iPad 12×5", or the device layout being shown in its place.
    private var gridSubtitle: String {
        if let designed = scene.designedLayout { return "Designed for \(designed.title)" }
        return "\(grid.cols)×\(grid.rows) · this device's layout"
    }

    private var pageTitle: String {
        let name = scene.name.isEmpty ? "Preview" : scene.name
        return currentPageKey != scene.homePageKey ? "\(name) · \(currentPageKey)" : name
    }

    @ViewBuilder
    private func previewCell(_ entry: TileEntry, labelFontSize: CGFloat) -> some View {
        if entry.isEmptyCell {
            // Holds its place and draws nothing, as on the board.
            Color.clear.aspectRatio(1, contentMode: .fit)
        } else {
            tileCell(entry, labelFontSize: labelFontSize)
        }
    }

    @ViewBuilder
    private func tileCell(_ entry: TileEntry, labelFontSize: CGFloat) -> some View {
        let tile = tileLookup[entry.key]
        let isLink = !entry.link.isEmpty
        Button {
            guard isLink else { return }
            let dest = entry.link == "<home>" ? scene.homePageKey : entry.link
            if scene.page(withKey: dest) != nil { go(to: dest) }
        } label: {
            // Same rule as the board: part of speech, or blue for a nav tile.
            // A preview whose colors are a 12% wash of the real ones cannot be
            // used to check the one thing a preview is for — whether the board
            // reads correctly before a child ever sees it.
            let accent = isLink
                ? TileColorResolver.linkColor(slotRawValue: entry.linkColor)
                : TileColorResolver.color(for: tile)
            VStack(spacing: 0) {
                // Badge bottom-right, as on the board. A preview exists to be
                // checked against what the child will see.
                ZStack(alignment: .bottomTrailing) {
                    TileImageView(key: tile?.bundleImage ?? entry.key,
                                  wordClass: tile?.wordClass ?? "")
                        .padding(2)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(5)
                    if isLink {
                        let badge = TileColorResolver.marker(on: accent)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(TileColorResolver.label(on: badge), badge)
                            .padding(3)
                    }
                }
                Text(tile?.displayName ?? entry.key)
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(TileColorResolver.label(on: accent))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
                    .padding(.vertical, GridLayoutCalculator.labelBandPadding)
            }
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
