// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI
import SwiftData

/// Read-only preview of a BlasterScene's board, as the child would see it —
/// without activating the scene. Tapping a navigation (linked) tile follows the
/// link — to the scene's own pages, and to BlasterAI 60's (`sys:` links and
/// the inherited system row) as the board does; leaf tiles are inert.
///
/// Laid out on the scene's designed grid (`BlasterScene.designedFor`), whatever
/// device this is — a phone board designed on an iPad previews as the phone
/// will show it. Paged as the board pages, under the system row, so every word
/// is where the child will find it. Undeclared, this device's own layout.
struct ScenePreviewBoardView: View {
    let scene: BlasterScene
    /// Built once, in `init`. The tiles come in as a plain array, so nothing
    /// is lost by not recomputing it — and it used to be recomputed over every
    /// TileModel for each cell, and for each entry inside `visibleTiles`' filter.
    private let tileLookup: [String: TileModel]

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]
    @Query(filter: #Predicate<BlasterScene> { $0.isTemplate })
    private var templateScenes: [BlasterScene]
    @State private var currentPageKey: String
    @State private var displayPage: Int? = 0
    @AppStorage(AppSettingsKey.boardLayout) private var boardLayoutRaw: String =
        BoardLayout.current().rawValue

    init(scene: BlasterScene, allTiles: [TileModel]) {
        self.scene = scene
        self.tileLookup = Dictionary(allTiles.map { ($0.key, $0) },
                                     uniquingKeysWith: { first, _ in first })
        _currentPageKey = State(initialValue: scene.homePageKey)
    }

    private var currentPage: PageSpec? {
        // As the child sees it, at the board's current level.
        let pages = scene.visiblePages
        return SystemLinks.page(forKey: currentPageKey, scenePages: pages, systemPages: systemPages)
            ?? pages.first
    }

    /// The pages of what the scene is built on — its templates over
    /// BlasterAI 60 (`TemplateChain`) — for the links into them. Empty when
    /// previewing BlasterAI 60.
    private var chain: TemplateChain? {
        guard let system = systemScenes.first, system.id != scene.id else { return nil }
        return TemplateChain(scene: scene, templates: templateScenes, system: system)
    }

    private var systemPages: [PageSpec] { chain?.pages(atLevel: nil) ?? [] }

    /// The page a tapped link opens, as the board resolves it: a scene page, a
    /// BlasterAI 60 page (`<system>:`), or nil when there is no such page.
    static func destination(of link: String, fromPage: String, scene: BlasterScene,
                            systemPages: [PageSpec], systemHomePageKey: String?) -> String? {
        let dest = SystemLinks.destination(of: link, fromPage: fromPage,
                                           homePageKey: scene.homePageKey,
                                           systemHomePageKey: systemHomePageKey,
                                           systemIsActive: scene.isDefault,
                                           shadowed: scene.shadowedSystemKeys)
        guard SystemLinks.page(forKey: dest, scenePages: scene.pages, systemPages: systemPages) != nil
        else { return nil }
        return dest
    }

    private var grid: (cols: Int, rows: Int) {
        GridLayoutCalculator.authoringGrid(
            designed: scene.designedLayout,
            isPhone: GridLayoutCalculator.isPhone(screenSize: GridLayoutCalculator.deviceScreenSize),
            deviceLayout: BoardLayout(rawValue: boardLayoutRaw) ?? .standard)
    }

    /// The tiles the board would draw: retired and unreviewed words, spacers
    /// and concealed cells all keep their place, empty.
    private func visibleTiles(_ page: PageSpec) -> [TileEntry] {
        TileEntry.holdingHiddenCells(page.tiles) { tileLookup[$0]?.isHiddenFromChild == true }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let page = currentPage {
                    GeometryReader { geo in
                        let spec = GridLayoutCalculator.compute(geo: geo.size, grid: grid, look: TileLook.current())
                        // The system row on every screen, as the board draws it.
                        let chrome = BoardChrome.inherits(scene)
                            ? BoardChrome.row(for: scene, level: scene.effectiveRevealLevel,
                                              inherited: chain?.navBar) : []
                        let perScreen = max(1, spec.perPage - (chrome.isEmpty ? 0 : spec.cols))
                        let placement = BoardChrome.placement(for: scene, inherited: chain?.navBarPlacement)
                        let chunks = visibleTiles(page).chunked(into: perScreen)
                        let columns = Array(repeating: GridItem(.fixed(spec.tileSize),
                                                                spacing: spec.horizontalSpacing),
                                            count: spec.cols)
                        TabView(selection: $displayPage) {
                            ForEach(Array((chunks.isEmpty ? [[]] : chunks).enumerated()),
                                    id: \.offset) { index, tiles in
                                LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                                    ForEach(Array(BoardChrome.arrange(content: tiles, chrome: Array(chrome.prefix(spec.cols)),
                                                                      placement: placement, perScreen: perScreen)
                                        .enumerated()), id: \.offset) { _, entry in
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

    /// "Designed for iPad 10×6", or the device layout being shown in its place.
    private var gridSubtitle: String {
        if let designed = scene.designedLayout { return "Designed for \(designed.title)" }
        return "\(grid.cols)×\(grid.rows) · this device's layout"
    }

    private var pageTitle: String {
        let name = scene.name.isEmpty ? "Preview" : scene.name
        return currentPageKey != scene.homePageKey
            ? "\(name) · \(SystemLinks.displayName(of: currentPageKey, chain: chain))" : name
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
            if let dest = Self.destination(of: entry.link, fromPage: currentPageKey, scene: scene,
                                           systemPages: systemPages,
                                           systemHomePageKey: chain?.homePageKey ?? systemScenes.first?.homePageKey) {
                go(to: dest)
            }
        } label: {
            // The board's own tile. A preview exists to be checked against
            // what the child will see, colours and folder badges included.
            TileFace(tile: tile, key: entry.key, link: entry.link, linkColor: entry.linkColor,
                     isAudible: entry.isAudible, labelFontSize: labelFontSize)
        }
        .buttonStyle(.plain)
    }
}
