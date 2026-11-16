// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MePreviewView.swift
//  claudeBlast
//
//  A Me page as the child will see it, from Home or from a page with rules,
//  with every added tile marked by where it came from, and the zones the
//  layout fills. The layout rules (`MeScene.composeHome`) decide where added
//  tiles land; this is how a caregiver sees them do it (Mark, 2026-11-15).
//

import SwiftUI
import SwiftData

struct MePreviewView: View {
    let profile: ChildProfile

    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]
    @Query private var profiles: [ChildProfile]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault }) private var systemScenes: [BlasterScene]

    /// Empty for Home; else a page the child comes from.
    @State private var showFor = ""
    @State private var showsZones = true
    @State private var selected: Int?

    private let cols = PageTemplate.cols
    private let rows = PageTemplate.rows - 1
    /// Where the layout puts what it adds (`MeScene.placeInline`, `withRegion`).
    private let wordColumns = 0..<7
    private let folderColumn = 7

    private func find(_ id: String) -> BlasterScene? { scenes.first { $0.sceneID == id } }
    private var me: BlasterScene? { find(MeScene.sceneID(forProfileID: profile.id)) }
    private var lookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A page's name: its profile's on this device, else its own.
    private func name(_ page: BlasterScene) -> String {
        profiles.first { MeScene.sceneID(forProfileID: $0.id) == page.sceneID }?.visibleName ?? page.name
    }

    /// The words on a rule's source page: a mounted scene's page, or a
    /// BlasterAI 60 page.
    private func words(_ item: TileEntry) -> [TileEntry] {
        if let source = TileToken.scenePageKey(item.link) {
            return find(source.sceneID)?.visiblePages.first { $0.key == source.page }?.tiles ?? []
        }
        let key = TileToken.systemPageKey(item.link).map(TileToken.bareKey) ?? item.link
        return systemScenes.first?.page(withKey: key)?.tiles ?? []
    }

    var body: some View {
        if let me {
            let layers = MeScene.layers(of: me, find: find)
            let cells = MeScene.preview(me.page(withKey: MeScene.homePageKey)?.tiles ?? [], layers: layers,
                                        name: name, contextKey: showFor.isEmpty ? nil : showFor,
                                        systemIsActive: true, rowKeys: [], words: words)
            let lastOwnRow = (0..<rows).last { row in
                (0..<cols).contains { col in
                    let i = row * cols + col
                    return i < cells.count && cells[i].source == .own && wordColumns.contains(col)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    controls(layers: layers)
                    grid(cells, lastOwnRow: lastOwnRow)
                    detail(cells)
                    legend
                    Text("Put what should always stay in place on the page itself or under Pinned. What changes by page goes in rules, and fills the space you leave.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("No Me Page Yet", systemImage: "heart")
        }
    }

    private func controls(layers: [BlasterScene]) -> some View {
        let keys = MeScene.contextKeys(layers: layers)
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Show for", selection: $showFor) {
                Text("Home").tag("")
                ForEach(keys, id: \.self) { key in
                    Text("Coming from " + MeScene.contextTitle(key, system: systemScenes.first, scenes: scenes))
                        .tag(key)
                }
            }
            .pickerStyle(.menu)
            Toggle("Show Zones", isOn: $showsZones)
        }
    }

    private func grid(_ cells: [(tile: TileEntry, source: MeScene.Source?)], lastOwnRow: Int?) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: cols)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<(rows * cols), id: \.self) { index in
                let cell = index < cells.count ? cells[index] : nil
                cellView(cell, index: index, lastOwnRow: lastOwnRow)
                    .onTapGesture { selected = cell?.source == nil ? nil : index }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: (tile: TileEntry, source: MeScene.Source?)?, index: Int,
                          lastOwnRow: Int?) -> some View {
        let row = index / cols, col = index % cols
        let zone = showsZones ? zoneColor(row: row, col: col, lastOwnRow: lastOwnRow) : .clear
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(zone)
            if let cell, !cell.tile.isEmptyCell {
                VStack(spacing: 1) {
                    TileImageView(key: cell.tile.key, wordClass: lookup[cell.tile.key]?.wordClass ?? "")
                        .aspectRatio(1, contentMode: .fit)
                    Text(cell.tile.label ?? lookup[cell.tile.key]?.displayName ?? cell.tile.key)
                        .font(.system(size: 9)).lineLimit(1)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
                .overlay(border(cell.source))
                .overlay(alignment: .topTrailing) { badge(cell.source) }
            }
        }
        .aspectRatio(0.85, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(selected == index ? Color.accentColor : .clear, lineWidth: 2))
    }

    /// Words flow into columns 1–7 below the page's own last row; folders
    /// fill column 8, then 9–10, which are otherwise the page's own links.
    private func zoneColor(row: Int, col: Int, lastOwnRow: Int?) -> Color {
        if col == folderColumn { return .purple.opacity(0.12) }
        if col > folderColumn { return .gray.opacity(0.12) }
        if row > (lastOwnRow ?? -1) { return .green.opacity(0.12) }
        return .clear
    }

    @ViewBuilder
    private func border(_ source: MeScene.Source?) -> some View {
        switch source {
        case .always:
            RoundedRectangle(cornerRadius: 6).stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        case .page:
            RoundedRectangle(cornerRadius: 6).stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        case .pinned, .included:
            RoundedRectangle(cornerRadius: 6).stroke(.indigo, lineWidth: 1.5)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func badge(_ source: MeScene.Source?) -> some View {
        switch source {
        case .pinned(_, let moved), .included(_, let moved):
            Image(systemName: moved ? "arrow.uturn.right.circle.fill" : "pin.circle.fill")
                .font(.system(size: 11)).foregroundStyle(moved ? .orange : .indigo)
                .background(Circle().fill(Color(.systemBackground)))
        default:
            EmptyView()
        }
    }

    /// What the tapped tile is and where it came from.
    @ViewBuilder
    private func detail(_ cells: [(tile: TileEntry, source: MeScene.Source?)]) -> some View {
        if let selected, selected < cells.count, let source = cells[selected].source {
            let word = lookup[cells[selected].tile.key]?.displayName ?? cells[selected].tile.key
            Label("\u{201C}\(word)\u{201D}: " + describe(source), systemImage: "info.circle")
                .font(.subheadline)
        } else {
            Text("Tap a tile to see where it comes from.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func describe(_ source: MeScene.Source) -> String {
        switch source {
        case .own: "on this page"
        case .pinned(let page, let moved):
            "pinned on \(page)" + (moved ? ", moved here because its cell is taken" : "")
        case .included(let page, let moved):
            "on \(page)\u{2019}s page" + (moved ? ", moved here because its cell is taken" : "")
        case .always(let page): "Always, from \(page)"
        case .page(let page): "for the page the user came from, from \(page)"
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(Image(systemName: "pin.circle.fill").foregroundStyle(.indigo), "Pinned, or on an included page")
            legendRow(Image(systemName: "arrow.uturn.right.circle.fill").foregroundStyle(.orange), "Moved: its cell was taken")
            legendRow(dash(.blue), "Always")
            legendRow(dash(.orange), "For the page the user came from")
            if showsZones {
                legendRow(swatch(.green), "Words flow here, below your own tiles")
                legendRow(swatch(.purple), "Folders flow here first")
                legendRow(swatch(.gray), "Your links; filled only when the rest is full")
            }
        }
        .font(.caption)
    }

    private func legendRow(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 8) { mark.frame(width: 18, height: 14); Text(text) }
    }

    private func dash(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.25))
    }
}
