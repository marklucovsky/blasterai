// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UIKit

/// Grid-based page editor — shows the page as the child sees it and supports
/// direct manipulation: tap-to-edit, native drag-and-drop reorder (press-hold a
/// tile to lift it, drag onto another to drop; a quick swipe still scrolls), an
/// inline add cell, and remove (in the tile's settings). A snapshot undo/redo
/// stack guards against the classic accidental-drop / accidental-remove
/// frustration (depth `maxUndoDepth`, per editing session).
struct PageEditorView: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    var autoOpenPickerWithKeys: Set<String> = []
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.modelContext) private var modelContext

    @State private var isPickingTiles = false
    @State private var editingTileKey: String? = nil
    @State private var pickerInitialKeys: Set<String> = []

    // Undo/redo: snapshots of the page's tile array (reorder / add / remove / bulk).
    // Deep enough to not think about; snapshots are tiny so the memory is moot.
    @State private var undoStack: [[TileEntry]] = []
    @State private var redoStack: [[TileEntry]] = []
    @State private var prePickerSnapshot: [TileEntry]? = nil
    private let maxUndoDepth = 25

    /// Multi-select mode toggle. Lives here so it sits in the nav bar; the grid
    /// editor (`TileGridEditor`) owns the actual selection set.
    @State private var isSelecting = false

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var pageIndex: Int? { scene.pages.firstIndex { $0.key == pageKey } }
    private var page: PageSpec? { scene.pages.first { $0.key == pageKey } }

    /// The page's tiles as an editable binding: each assignment records one undo
    /// snapshot and persists, so the grid editor's bulk/reorder ops are each a
    /// single undoable step.
    private var tilesBinding: Binding<[TileEntry]> {
        Binding(
            get: { page?.tiles ?? [] },
            set: { newTiles in
                guard let idx = pageIndex else { return }
                recordUndo(page?.tiles ?? [])
                var pages = scene.pages
                pages[idx].tiles = newTiles
                scene.pages = pages
                try? modelContext.save()
            }
        )
    }

    /// Caregiver allows a flagged/blocked word — clears the review flags so it
    /// becomes visible to the child again.
    private func keepReview(_ tile: TileModel) {
        tile.approveReview()
        try? modelContext.save()
    }

    /// Caregiver removes a flagged/blocked word — hides it (stays page-attached but
    /// invisible in running scenes; restorable in the Vocab manager) and purges its
    /// cached sentences.
    private func removeReviewed(_ tile: TileModel) {
        tile.retire()
        _ = SentenceCacheManager(modelContext: modelContext).invalidate(containingTileKey: tile.key)
        try? modelContext.save()
    }

    private var isHome: Bool { scene.homePageKey == pageKey }

    /// The home-page control lives here (not the nav bar) so it has room for a
    /// full, non-truncating label and never crowds Select/＋ out of reach in
    /// portrait. Filled blue when this page is the scene's home; tap to toggle.
    private var pageHeader: some View {
        HStack(spacing: 10) {
            Button { toggleHome() } label: {
                Label(isHome ? "Home Page" : "Set as Home",
                      systemImage: isHome ? "house.fill" : "house")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isHome ? Color.blue : Color.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Toggle this page as the scene's home. A scene keeps exactly one home, so
    /// toggling OFF hands home back to the conventional "home"-keyed page if one
    /// exists, otherwise the first other page in the list. A sole page stays home.
    private func toggleHome() {
        if isHome {
            if let next = scene.homeKeyAfterTogglingOffCurrent() {
                scene.homePageKey = next
            }
        } else {
            scene.homePageKey = pageKey
        }
        try? modelContext.save()
    }

    var body: some View {
        Group {
            if let page, page.tiles.isEmpty {
                ContentUnavailableView {
                    Label("No Tiles", systemImage: "square.grid.2x2")
                } description: {
                    Text("Tap + to add tiles to this page.")
                } actions: {
                    Button("Add Tiles") { openPicker() }
                        .buttonStyle(.borderedProminent)
                }
            } else if page != nil {
                VStack(spacing: 0) {
                    pageHeader
                    TileGridEditor(
                        tiles: tilesBinding,
                        isSelecting: $isSelecting,
                        wordClassOf: { tileLookup[$0]?.wordClass },
                        showAddCell: true,
                        onAdd: { openPicker() },
                        onTapTile: { editingTileKey = $0 },
                        cell: { entry in
                            if let tile = tileLookup[entry.key] {
                                PageTileCell(tile: tile, link: entry.link)
                                    .overlay(alignment: .bottomTrailing) {
                                        TileReviewBadge(tile: tile,
                                                        onKeep: { keepReview(tile) },
                                                        onRemove: { removeReviewed(tile) })
                                    }
                            }
                        }
                    )
                }
            } else {
                ContentUnavailableView("Page not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(pageKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(redoStack.isEmpty)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button("Done") { isSelecting = false }
                } else {
                    if page.map({ !$0.tiles.isEmpty }) == true {
                        Button { isSelecting = true } label: { Image(systemName: "checkmark.circle") }
                    }
                    Button { openPicker() } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $isPickingTiles, onDismiss: pickerDismissed) {
            TilePickerView(scene: scene, pageKey: pageKey, initialSelectedKeys: pickerInitialKeys)
        }
        .sheet(item: $editingTileKey) { key in
            TilePropertiesSheet(scene: scene, pageKey: pageKey, tileKey: key,
                                onRemove: { remove(key: key) })
        }
        .task {
            guard !autoOpenPickerWithKeys.isEmpty else { return }
            pickerInitialKeys = autoOpenPickerWithKeys
            prePickerSnapshot = page?.tiles ?? []
            isPickingTiles = true
        }
    }

    // MARK: - Add / Remove

    private func openPicker() {
        pickerInitialKeys = []
        prePickerSnapshot = page?.tiles ?? []
        isPickingTiles = true
    }

    private func pickerDismissed() {
        pickerInitialKeys = []
        if let before = prePickerSnapshot, before != (page?.tiles ?? []) {
            recordUndo(before)
        }
        prePickerSnapshot = nil
    }

    private func remove(key: String) {
        guard let idx = pageIndex, let page else { return }
        recordUndo(page.tiles)
        var pages = scene.pages
        pages[idx].tiles.removeAll { $0.key == key }
        scene.pages = pages
        try? modelContext.save()
    }

    // MARK: - Undo / redo (snapshot stack)

    private func recordUndo(_ before: [TileEntry]) {
        guard undoStack.last != before else { return }
        undoStack.append(before)
        if undoStack.count > maxUndoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func setTiles(_ tiles: [TileEntry]) {
        guard let idx = pageIndex else { return }
        var pages = scene.pages
        pages[idx].tiles = tiles
        scene.pages = pages
        try? modelContext.save()
    }

    private func undo() {
        guard let before = undoStack.popLast() else { return }
        redoStack.append(page?.tiles ?? [])
        if redoStack.count > maxUndoDepth { redoStack.removeFirst() }
        setTiles(before)
    }

    private func redo() {
        guard let after = redoStack.popLast() else { return }
        undoStack.append(page?.tiles ?? [])
        if undoStack.count > maxUndoDepth { undoStack.removeFirst() }
        setTiles(after)
    }
}

// MARK: - Page tile cell

/// A single tile in the editor grid, mirroring the child's board cell, with a
/// small link badge for navigation tiles.
struct PageTileCell: View {
    let tile: TileModel
    var link: String = ""

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                    .padding(5)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                if !link.isEmpty {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(4)
                }
            }
            Text(tile.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

// Allow .sheet(item:) on String state.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Tile Properties Sheet

struct TilePropertiesSheet: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    let tileKey: String
    var onRemove: (() -> Void)? = nil
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver

    /// Image awaiting a square crop. Owned here (the sheet root), not inside the
    /// photo Section, so the cropper presents off a stable anchor.
    @State private var cropTarget: CropTarget?
    @State private var photoError: String?

    private struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var tile: TileModel? {
        allTiles.first { $0.key == tileKey }
    }

    private var entry: TileEntry? {
        scene.pages.first { $0.key == pageKey }?.tiles.first { $0.key == tileKey }
    }

    private var entryBinding: (link: Binding<String>, audible: Binding<Bool>) {
        let link = Binding<String>(
            get: { entry?.link ?? "" },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                let wasEmpty = pages[p].tiles[t].link.isEmpty
                pages[p].tiles[t].link = newValue
                // Adding a link → default to navigate-only (caregiver can re-enable
                // "also speak" via the now-enabled toggle); removing it → a plain
                // word tile, which always speaks.
                if wasEmpty && !newValue.isEmpty {
                    pages[p].tiles[t].isAudible = false
                } else if !wasEmpty && newValue.isEmpty {
                    pages[p].tiles[t].isAudible = true
                }
                scene.pages = pages
            }
        )
        let audible = Binding<Bool>(
            get: { entry?.isAudible ?? true },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                pages[p].tiles[t].isAudible = newValue
                scene.pages = pages
            }
        )
        return (link, audible)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile?.displayName ?? tileKey)
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(tile?.wordClass ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let tile, !tile.isSystem {
                                    Label("Added", systemImage: "person.crop.circle.badge.plus")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                            }
                            // Key is the stable id used in TileScript / scene JSON — surface it (copyable).
                            Text("key: \(tile?.key ?? tileKey)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        // Per-style art review: every style side by side + zoom.
                        TileStyleStripView(tileKey: tile?.key ?? tileKey,
                                           displayName: tile?.displayName ?? tileKey,
                                           wordClass: tile?.wordClass ?? "")
                    }
                    .padding(.vertical, 4)
                }

                if let tile {
                    TilePhotoSection(tile: tile) { picked in
                        cropTarget = CropTarget(image: picked)
                    }
                }

                Section {
                    Toggle("Add to sentence tray", isOn: entryBinding.audible)
                        .disabled((entry?.link ?? "").isEmpty)
                } header: {
                    Text("Behavior")
                } footer: {
                    if (entry?.link ?? "").isEmpty {
                        Text("A word tile always adds to the sentence tray.")
                    } else {
                        Text("This tile opens a page. Turn this on if it should also speak the word.")
                    }
                }

                Section("Navigation") {
                    Picker("Link to Page", selection: entryBinding.link) {
                        Text("None").tag("")
                        ForEach(scene.pages, id: \.key) { page in
                            Text(page.key).tag(page.key)
                        }
                    }
                    let currentLink = entry?.link ?? ""
                    if !currentLink.isEmpty {
                        Text("Tapping this tile navigates to \"\(currentLink)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let onRemove {
                    Section {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove from Page", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Tile Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $cropTarget) { target in
                SquareImageCropper(
                    image: target.image,
                    onCrop: { square in
                        cropTarget = nil
                        if let tile {
                            photoError = TilePhotoCommit.apply(
                                square, to: tile,
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
}
