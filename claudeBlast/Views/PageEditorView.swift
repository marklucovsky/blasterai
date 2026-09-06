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
    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// True on iPhone, and on any Mac window narrow enough that the navigation
    /// bar can no longer hold four controls beside the title.
    private var isCompactWidth: Bool { hSizeClass == .compact }

    @State private var undoStack: [[TileEntry]] = []
    @State private var redoStack: [[TileEntry]] = []
    @State private var prePickerSnapshot: [TileEntry]? = nil
    private let maxUndoDepth = 25

    /// Multi-select mode toggle. Lives here so it sits in the nav bar; the grid
    /// editor (`TileGridEditor`) owns the actual selection set.
    @State private var isSelecting = false

    /// Page-level share. A page leaves as a vocabulary pack — see `ShareBoardSheet`.
    @State private var isSharingPage = false

    /// Rename sheet presentation. Separate from `renameDraft` on purpose — see
    /// `rename(to:)`.
    @State private var isRenaming = false
    /// What is typed in the rename field. Owned here so the sheet can be a plain
    /// binding, and deliberately NOT the presentation state.
    @State private var renameDraft = ""

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
            Button {
                renameDraft = page?.displayName ?? ""
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
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
                    Text("This page is empty.")
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
                        onAddSpace: { addSpacer() },
                        onTapTile: { editingTileKey = $0 },
                        cell: { entry in
                            // The editor shows what the child cannot.
                            //
                            // On the board a concealed word draws as empty
                            // space; here it has to stay visible and legible, or
                            // the caregiver is arranging a page with invisible
                            // contents and cannot find the word to reveal it
                            // again. Same picture, dimmed, with a badge saying
                            // why — the exact inverse of the child's view.
                            if entry.isSpacer {
                                SpacerCell()
                            } else if let tile = tileLookup[entry.key] {
                                PageTileCell(tile: tile, link: entry.link,
                                             isConcealed: entry.isConcealed)
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
        .navigationTitle(page?.title ?? pageKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { pageEditorToolbar }
        .sheet(isPresented: $isRenaming) {
            PageRenameSheet(
                currentTitle: page?.title ?? pageKey,
                pageKey: pageKey,
                draft: $renameDraft,
                onSave: { rename(to: $0) })
        }
        .sheet(isPresented: $isSharingPage) {
            if let page {
                ShareBoardSheet(subject: .page(page, in: scene))
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

    // MARK: - Toolbar

    /// At a narrow width SwiftUI protects the inline title and **drops** toolbar
    /// items rather than collapsing them — undo/redo (leading) vanish first,
    /// then whatever trails. Nothing tells the user those actions still exist;
    /// they are simply gone. A resizable Mac window makes this trivial to hit,
    /// and an iPhone is permanently in that state. So the bar carries as few
    /// things as it can, and everything else lives in an explicit overflow menu.
    ///
    /// ## Why there is no "+" here
    ///
    /// There was, and it did exactly what the grid's add cell does — the same
    /// `openPicker()`. But the add cell sits in **slot 0** of the grid, ahead of
    /// the first tile, so it is on screen without scrolling however long the page
    /// is; it is also a drop target that moves a dragged tile to the front, which
    /// a toolbar button cannot be. The duplicate bought nothing and cost the one
    /// bar slot that a genuinely bar-shaped action needed.
    ///
    /// **Share is that action.** It has no representation anywhere else on the
    /// page, and a caregiver looking to send a page somewhere looks in the
    /// navigation bar — so it is a visible button, not a menu item, at every
    /// width. Both it and Select are gated on the page having tiles: an empty
    /// page has nothing to share and nothing to select, and shows its own "Add
    /// Tiles" button instead.
    @ToolbarContentBuilder
    private var pageEditorToolbar: some ToolbarContent {
        if isCompactWidth {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button("Done") { isSelecting = false }
                } else {
                    if hasTiles {
                        Button { isSharingPage = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share page")
                    }
                    Menu {
                        Button { undo() } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(undoStack.isEmpty)
                        Button { redo() } label: {
                            Label("Redo", systemImage: "arrow.uturn.forward")
                        }
                        .disabled(redoStack.isEmpty)
                        if hasTiles {
                            Button { isSelecting = true } label: {
                                Label("Select Tiles", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More page actions")
                }
            }
        } else {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(redoStack.isEmpty)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button("Done") { isSelecting = false }
                } else if hasTiles {
                    Button { isSelecting = true } label: { Image(systemName: "checkmark.circle") }
                        .accessibilityLabel("Select tiles")
                    Button { isSharingPage = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share page")
                }
            }
        }
    }

    /// Rename this page.
    ///
    /// **Sets `displayName`; the key never moves.** Everything that points at a
    /// page points at its key — links, `homePageKey`, the minted `page_<key>`
    /// tile, TileScript navigation, `.obf` filenames, and `LoggedUtterance`
    /// history that must stay true to what was actually pressed. A rename that
    /// touched the key would either break all of those or silently rewrite
    /// history.
    ///
    /// Empty restores the derived name, so a rename is always undoable without a
    /// separate reset.
    ///
    /// **The page-link tile's label follows.** `page_<key>` is what the child
    /// actually reads on the board; leaving it behind would rename the page
    /// everywhere the caregiver looks and nowhere the child does. Note the tile
    /// is keyed from the page key alone, so two scenes with a page keyed `farm`
    /// share it and both labels move together — rare, and the alternative (a
    /// board still showing the old word) is the worse surprise.
    private func rename(to newName: String) {
        guard let idx = pageIndex else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var pages = scene.pages
        pages[idx].displayName = trimmed
        scene.pages = pages

        if let link = tileLookup[PageLink.key(forPage: pageKey)] {
            link.displayName = trimmed.isEmpty ? PageNaming.displayName(pageKey) : trimmed
        }
        try? modelContext.save()
        isRenaming = false
    }

    /// Add a deliberate gap at the front of the page.
    ///
    /// **Slot 0, exactly where a newly picked tile lands** (`TilePickerView`
    /// inserts at index 0). Anything added from the Add cell appears right next
    /// to it, on screen without scrolling however long the page is — and from
    /// there the caregiver drags it where it belongs, using the reorder gesture
    /// they already know. Appending would have put a new gap off the bottom of a
    /// long page, where the one thing a blank cell cannot do is announce itself.
    ///
    /// Goes through `tilesBinding`, so it records one undo step and saves like
    /// every other page mutation.
    private func addSpacer() {
        tilesBinding.wrappedValue = [TileEntry.spacer()] + (page?.tiles ?? [])
    }

    /// Whether the page has anything on it — gates Select and Share.
    private var hasTiles: Bool { page.map { !$0.tiles.isEmpty } == true }

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
/// A deliberate gap, as the caregiver sees it.
///
/// The child sees nothing here at all. The editor has to show *something*, or a
/// spacer is indistinguishable from the end of the page and cannot be selected,
/// moved or removed.
struct SpacerCell: View {
    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.tertiary)
                .aspectRatio(1, contentMode: .fit)
            Text("space")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }
}

struct PageTileCell: View {
    let tile: TileModel
    var link: String = ""
    /// Concealed on this page: still drawn, deliberately muted, and badged.
    var isConcealed: Bool = false

    /// Same rule as the board: part of speech, or blue for a nav tile.
    private var accent: Color {
        link.isEmpty ? TileColorResolver.color(for: tile) : TileColorResolver.navigation
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                // The editor draws the tile the way the child will see it.
                //
                // It was a bare picture, which was survivable while colour was a
                // hairline nobody arranged by. Now that colour means part of
                // speech, a caregiver grouping the board into colour blocks — the
                // whole point of a Fitzgerald layout — was doing it blind here and
                // only finding out on the board.
                ZStack {
                    accent
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white)
                        .padding(6)
                    TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                        .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .opacity(isConcealed ? 0.32 : 1)
                .overlay(alignment: .center) {
                    if isConcealed {
                        Image(systemName: "eye.slash.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                if !link.isEmpty {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, TileColorResolver.navigation)
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

    // MARK: - Part of speech

    /// The tile's part of speech, and the control that lets a therapist correct
    /// it.
    ///
    /// **It sets the part of speech, not the colour**, even though colour is
    /// what a caregiver notices. Picking a colour directly would break the axis
    /// the colour stands for: two words could end up the same colour with
    /// different parts of speech, and the coverage report would then disagree
    /// with the board. One axis, and the colour follows from it.
    ///
    /// "Automatic" is the normal state and names what it resolved to, so the
    /// difference between *nobody has said* and *someone chose this* stays
    /// visible. Clearing back to Automatic is how a correction is undone —
    /// there is no separate reset.
    @ViewBuilder
    private func partOfSpeechPicker(_ tile: TileModel) -> some View {
        NavigationLink {
            PartOfSpeechPickerList(selection: partOfSpeechBinding(tile),
                                   automatic: tile.derivedPartOfSpeech)
        } label: {
            HStack(spacing: 8) {
                partOfSpeechSwatch(TileColorResolver.color(for: tile))
                Text("Word type")
                if tile.storedPartOfSpeech != nil {
                    Text("edited")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                Spacer(minLength: 8)
                Text(tile.storedPartOfSpeech?.label
                     ?? automaticLabel(tile.derivedPartOfSpeech))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What "Automatic" currently works out to, so the row is never a mystery.
    private func automaticLabel(_ resolved: PartOfSpeech?) -> String {
        guard let resolved else { return "Automatic" }
        return "Automatic (\(resolved.label))"
    }

    /// Writes through to the model, and keeps `PartOfSpeechIndex` in step so the
    /// coverage report counts the word the same way the board colours it.
    private func partOfSpeechBinding(_ tile: TileModel) -> Binding<PartOfSpeech?> {
        Binding(
            get: { tile.storedPartOfSpeech },
            set: { newValue in
                tile.storedPartOfSpeech = newValue
                PartOfSpeechIndex.setStored(newValue, for: tile.key)
                try? modelContext.save()
            }
        )
    }

    private var entry: TileEntry? {
        scene.pages.first { $0.key == pageKey }?.tiles.first { $0.key == tileKey }
    }

    private var entryBinding: (link: Binding<String>, audible: Binding<Bool>, concealed: Binding<Bool>) {
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
        let concealed = Binding<Bool>(
            get: { entry?.isConcealed ?? false },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                pages[p].tiles[t].isConcealed = newValue
                scene.pages = pages
            }
        )
        return (link, audible, concealed)
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

                        if let tile { partOfSpeechPicker(tile) }

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

                    Toggle("Conceal on this page", isOn: entryBinding.concealed)
                } header: {
                    Text("Behavior")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if (entry?.link ?? "").isEmpty {
                            Text("A word tile always adds to the sentence tray.")
                        } else {
                            Text("This tile opens a page. Turn this on if it should also speak the word.")
                        }
                        // Says what conceal is *for*, because the obvious
                        // alternative — removing the tile — is worse in a way
                        // that is not obvious.
                        Text("Concealing keeps the tile's place on the board but draws it "
                             + "empty, so nothing else moves. Removing it instead would shift "
                             + "every word after it, and the child would have to learn the "
                             + "board again. This page only — the word stays available "
                             + "everywhere else.")
                    }
                }

                Section("Navigation") {
                    Picker("Link to Page", selection: entryBinding.link) {
                        Text("None").tag("")
                        ForEach(scene.pages, id: \.key) { page in
                            Text(page.title).tag(page.key)
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
/// A dot in the tile's real board colour. Drawn rather than an SF Symbol so it
/// survives every context that would otherwise template-render it.
@ViewBuilder
func partOfSpeechSwatch(_ color: Color, size: CGFloat = 12) -> some View {
    Circle()
        .fill(color)
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
}

/// The word-type list.
///
/// A pushed list rather than a menu because the colour is the point, and a menu
/// renders its option icons monochrome. Here each row owns its own swatch, so a
/// therapist picks the colour they can see.
struct PartOfSpeechPickerList: View {
    @Binding var selection: PartOfSpeech?
    /// What Automatic works out to for this tile, so the row is never a mystery.
    let automatic: PartOfSpeech?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(nil, label: automaticRowLabel, color: TileColorResolver.color(for: automatic))
            } footer: {
                Text("Automatic uses the word's own type, or the class it was created with. "
                     + "Choose a type to override it — the tile's colour follows.")
            }

            Section("Word type") {
                ForEach(PartOfSpeech.display) { pos in
                    row(pos, label: pos.label, color: TileColorResolver.color(for: pos))
                }
            }
        }
        .navigationTitle("Word Type")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var automaticRowLabel: String {
        guard let automatic else { return "Automatic" }
        return "Automatic (\(automatic.label))"
    }

    @ViewBuilder
    private func row(_ value: PartOfSpeech?, label: String, color: Color) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack(spacing: 10) {
                partOfSpeechSwatch(color, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).foregroundStyle(.primary)
                    // The term stays standard; the examples do the explaining.
                    if let value {
                        Text(value.examples)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Rename a page.
///
/// Shows the key, because a caregiver who has been living with `play_activities`
/// deserves to know it is still there and still what everything points at — the
/// name is a label, not a move.
struct PageRenameSheet: View {
    let currentTitle: String
    let pageKey: String
    @Binding var draft: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Page name", text: $draft, prompt: Text(currentTitle))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                } footer: {
                    Text("Leave it empty to go back to \(PageNaming.displayName(pageKey)).")
                }

                Section {
                    LabeledContent("Key", value: pageKey)
                        .font(.caption.monospaced())
                } footer: {
                    Text("The key never changes. Links to this page, scripts, and your "
                         + "activity history all point at it, so renaming is safe — it "
                         + "only changes what you see.")
                }
            }
            .navigationTitle("Rename Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        onSave(draft)
        dismiss()
    }
}
