// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileGridEditor.swift
//  claudeBlast
//

import SwiftUI
import UIKit

/// Reusable tile-grid editing surface: renders a page's tiles as the child sees
/// them and supports direct manipulation — multi-select (tap to select, "select
/// all of {class}"), bulk delete / move-to-front / move-to-end, and native
/// drag-and-drop reorder. It is deliberately storage-agnostic: it edits a
/// `Binding<[TileEntry]>`, so the same surface drives both the persistent page
/// editor (bound to a scene page, with undo) and the not-yet-committed page
/// *preview* (bound to transient state, prune before Accept). Every mutation
/// flows through the binding as a single assignment, so the owner records undo
/// and persists however it likes.
///
/// Cell rendering is injected (`cell`) because callers show different chrome
/// (a scene tile vs. a freshly-generated one); the editor only owns the
/// selection overlay, the drop-target ring, and the drag arbitration.
struct TileGridEditor<Cell: View>: View {
    @Binding var tiles: [TileEntry]
    /// Owner-controlled so the container can place the Select/Done toggle in its
    /// own chrome (nav bar vs. preview button row).
    @Binding var isSelecting: Bool

    /// Word class for a tile key — drives the "Select all of {class}" menu. Nil
    /// (unknown tile) is simply excluded from class grouping.
    var wordClassOf: (String) -> String?

    var minTile: CGFloat = 84
    var maxTile: CGFloat = 112

    /// Optional inline add-cell (suppressed in the preview). Only shown outside
    /// select mode.
    var showAddCell: Bool = false
    var onAdd: (() -> Void)? = nil

    /// Non-select tap on a tile (e.g. open its properties). No-op if nil.
    var onTapTile: ((String) -> Void)? = nil

    @ViewBuilder var cell: (TileEntry) -> Cell

    @State private var selectedKeys: Set<String> = []
    @State private var dropTarget: String? = nil
    /// When set, the next tap on a non-selected tile drops the selection before/
    /// after it (collect-to-anchor). Entered from the Move menu.
    @State private var anchorMode: AnchorMove?
    enum AnchorMove { case before, after }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minTile, maximum: maxTile), spacing: 10)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    // Add cell in slot-0 (camera-in-photo-picker pattern) so it's
                    // discoverable without scrolling to the end of a long page.
                    if showAddCell, !isSelecting, let onAdd { addCell(onAdd) }
                    ForEach(tiles, id: \.key) { entry in
                        cellView(entry)
                    }
                }
                .padding(16)
            }
            if isSelecting {
                if let mode = anchorMode { anchorHintBar(mode) } else { selectionBar }
            }
        }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selectedKeys.removeAll(); anchorMode = nil }
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(_ entry: TileEntry) -> some View {
        let key = entry.key
        let selected = isSelecting && selectedKeys.contains(key)
        cell(entry)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor,
                                  lineWidth: (dropTarget == key || selected) ? 3 : 0)
            )
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background(Circle().fill(.background))
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                if let mode = anchorMode {
                    // Anchor pick: only a non-selected tile is a valid drop anchor.
                    if !selectedKeys.contains(key) { moveSelection(anchor: key, before: mode == .before) }
                } else if isSelecting {
                    toggleSelect(key)
                } else {
                    onTapTile?(key)
                }
            }
            // .draggable arbitrates drag-vs-scroll and fires no late system drop
            // haptic, so the synchronous drop haptic below stands alone. Reorder
            // is disabled in select mode (the tap is claimed by selection).
            .draggable(key)
            .dropDestination(for: String.self) { items, _ in
                guard !isSelecting, let moved = items.first else { return false }
                impact(.light)
                // Defer the mutation out of the drop callback so the binding
                // write doesn't re-enter the in-progress view update.
                Task { @MainActor in moveTile(moved, before: key) }
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? key : (dropTarget == key ? nil : dropTarget)
            }
    }

    private func addCell(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "plus").font(.title2).foregroundStyle(.secondary))
                Text("Add").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in   // drop on "+" → move to front
            guard let moved = items.first else { return false }
            impact(.light)
            Task { @MainActor in moveTileToFront(moved) }
            return true
        }
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Menu {
                Button("Select All") { selectedKeys = Set(tiles.map(\.key)) }
                Button("Deselect All") { selectedKeys.removeAll() }
                if !classesOnPage.isEmpty {
                    Divider()
                    ForEach(classesOnPage, id: \.self) { c in
                        Button("All \(c.capitalized)") { selectClass(c) }
                    }
                }
            } label: { Label("Select", systemImage: "checklist") }

            Spacer()
            Text("\(selectedKeys.count) selected")
                .font(.subheadline).foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()

            Menu {
                Button { moveKeys(toFront: true) } label: { Label("Move to Front", systemImage: "arrow.up.to.line") }
                Button { moveKeys(toFront: false) } label: { Label("Move to End", systemImage: "arrow.down.to.line") }
                Divider()
                Button { anchorMode = .before } label: { Label("Move Before Tile…", systemImage: "arrow.left.to.line") }
                Button { anchorMode = .after } label: { Label("Move After Tile…", systemImage: "arrow.right.to.line") }
            } label: { Label("Move", systemImage: "arrow.up.arrow.down") }
                .disabled(selectedKeys.isEmpty)

            Button(role: .destructive) { removeKeys() } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedKeys.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Shown while picking a drop anchor for the selection (move-before/after).
    private func anchorHintBar(_ mode: AnchorMove) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.point.up.left").foregroundStyle(.tint)
            Text("Tap a tile to move \(selectedKeys.count) \(mode == .before ? "before" : "after") it")
                .font(.subheadline)
            Spacer()
            Button("Cancel") { anchorMode = nil }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Selection helpers

    private func toggleSelect(_ key: String) {
        if selectedKeys.contains(key) { selectedKeys.remove(key) } else { selectedKeys.insert(key) }
    }

    /// Distinct word classes present, in sorted order — drives "Select all of X".
    private var classesOnPage: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for e in tiles {
            if let wc = wordClassOf(e.key), seen.insert(wc).inserted { order.append(wc) }
        }
        return order.sorted()
    }

    private func selectClass(_ wordClass: String) {
        for e in tiles where wordClassOf(e.key) == wordClass { selectedKeys.insert(e.key) }
    }

    // MARK: - Mutations (each a single binding assignment → one undo step upstream)

    private func removeKeys() {
        guard !selectedKeys.isEmpty else { return }
        tiles = tiles.filter { !selectedKeys.contains($0.key) }
        selectedKeys.removeAll()
    }

    private func moveKeys(toFront: Bool) {
        guard !selectedKeys.isEmpty else { return }
        let moving = tiles.filter { selectedKeys.contains($0.key) }
        let rest = tiles.filter { !selectedKeys.contains($0.key) }
        tiles = toFront ? moving + rest : rest + moving
    }

    /// Collect-to-anchor: pluck the selection (keeping its internal order) and
    /// drop it as one contiguous block immediately before/after `anchor` — a
    /// non-selected tile. A sparse selection becomes adjacent at the anchor; the
    /// anchor keeps its place among the unselected tiles.
    private func moveSelection(anchor: String, before: Bool) {
        defer { anchorMode = nil }
        guard !selectedKeys.isEmpty, !selectedKeys.contains(anchor) else { return }
        let moving = tiles.filter { selectedKeys.contains($0.key) }
        var rest = tiles.filter { !selectedKeys.contains($0.key) }
        guard let idx = rest.firstIndex(where: { $0.key == anchor }) else { return }
        rest.insert(contentsOf: moving, at: before ? idx : idx + 1)
        tiles = rest
    }

    private func moveTile(_ movedKey: String, before targetKey: String) {
        guard movedKey != targetKey else { dropTarget = nil; return }
        var t = tiles
        guard let from = t.firstIndex(where: { $0.key == movedKey }) else { dropTarget = nil; return }
        let item = t.remove(at: from)
        let insertAt = t.firstIndex(where: { $0.key == targetKey }) ?? t.count
        t.insert(item, at: insertAt)
        tiles = t
        dropTarget = nil
    }

    private func moveTileToFront(_ movedKey: String) {
        var t = tiles
        guard let from = t.firstIndex(where: { $0.key == movedKey }) else { return }
        t.insert(t.remove(at: from), at: 0)
        tiles = t
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
