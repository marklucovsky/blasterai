// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageEditorView.swift
//  claudeBlast
//

import SwiftUI
import os
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
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]
    @Environment(\.modelContext) private var modelContext

    @State private var isPickingTiles = false
    @State private var editingTileKey: String? = nil
    /// Tile Settings' Edit Cell: the grid types the cell. Bumped as the sheet
    /// starts to close, not once it has: waiting out the close added half a
    /// second before the keyboard even began to rise.
    @State private var cellEditRequest = 0
    @State private var pickerInitialKeys: Set<String> = []
    /// The cell the picker's words fill from, in reading order.
    @State private var pickerStart = 0
    /// The on-screen keyboard is up. It takes most of a portrait iPad, so the
    /// page header and the bars above it step aside for the formula bar and
    /// the well.
    @State private var keyboardUp = false

    // Undo/redo: snapshots of the page's tile array (reorder / add / remove / bulk).
    // Deep enough to not think about; snapshots are tiny so the memory is moot.
    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// True on iPhone, and on any Mac window narrow enough that the navigation
    /// bar can no longer hold four controls beside the title.
    private var isCompactWidth: Bool { hSizeClass == .compact }

    @AppStorage(AppSettingsKey.boardLayout) private var boardLayoutRaw: String =
        BoardLayout.current().rawValue

    /// The scene's designed grid, else this device's layout — so the page is
    /// arranged as it will appear. See `GridLayoutCalculator.authoringGrid`.
    private var boardGrid: (cols: Int, rows: Int) {
        GridLayoutCalculator.authoringGrid(
            designed: scene.designedLayout,
            isPhone: GridLayoutCalculator.isPhone(screenSize: GridLayoutCalculator.deviceScreenSize),
            deviceLayout: BoardLayout(rawValue: boardLayoutRaw) ?? .standard)
    }

    @State private var undoStack: [[TileEntry]] = []
    @State private var redoStack: [[TileEntry]] = []
    @State private var prePickerSnapshot: [TileEntry]? = nil
    private let maxUndoDepth = 25

    /// Page-level share. A page leaves as a vocabulary pack — see `ShareBoardSheet`.
    @State private var isSharingPage = false

    /// Rename sheet presentation. Separate from `renameDraft` on purpose — see
    /// `rename(to:)`.
    @State private var isRenaming = false
    @State private var isChoosingCover = false
    @State private var isLinkingPage = false
    /// The level the editor previews: cells above it dim, as concealed cells
    /// do, so a caregiver sees what a child at that level gets without leaving
    /// the editor. 0 shows every level at full strength.
    @State private var previewLevel = 0
    /// What is typed in the rename field. Owned here so the sheet can be a plain
    /// binding, and deliberately NOT the presentation state.
    @State private var renameDraft = ""

    /// Read once per render and handed to the grid. Each call rebuilds the
    /// dictionary over every TileModel, so reading it per cell cost
    /// (all tiles × cells) SwiftData property reads on every render.
    private var tileLookup: [String: TileModel] {
        let state = PerfSignposts.signposter.beginInterval(
            "pageEditor.tileLookup", "\(allTiles.count) tiles")
        defer { PerfSignposts.signposter.endInterval("pageEditor.tileLookup", state) }
        return Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// The page itself, apart from its words: a card over the editor with
    /// what the page *is* — its cover, its name, whether it is Home — and
    /// what is set for the page as a whole (preview level, folders into it).
    /// Drawn as a card, not a bar, so it never reads as part of the grid's
    /// own option bar under it, which is about the words.
    private var pageHeader: some View {
        HStack(spacing: 12) {
            pageIdentity
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                pageSettings(labelled: true)
                pageSettings(labelled: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // System grouped colours, so the card stands off its strip in both
        // modes: white on light grey, raised grey on black.
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemGroupedBackground))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator)))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Cover (tap to change it), name (tap to rename), and a Home badge.
    private var pageIdentity: some View {
        HStack(spacing: 10) {
            if !scene.isDefault {
                // The picture every folder into this page shows. See `PageCover`.
                Button { isChoosingCover = true } label: {
                    // On white, as every list row and chip draws art: tinted,
                    // the card and system colours behind it bled through.
                    TileImageView(key: PageCover.key(ofPage: pageKey, in: scene),
                                  wordClass: PageLink.wordClass)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page cover")
            }
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    renameDraft = page?.displayName ?? ""
                    isRenaming = true
                } label: {
                    HStack(spacing: 6) {
                        Text(page?.title ?? pageKey)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename page")
                Text(wordCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var wordCountText: String {
        let count = page?.tiles.filter { !$0.isSpacer }.count ?? 0
        return count == 1 ? "1 word" : "\(count) words"
    }

    /// Settings for the whole page. `labelled: false` is the narrow fallback.
    @ViewBuilder
    private func pageSettings(labelled: Bool) -> some View {
        HStack(spacing: 8) {
            Button { toggleHome() } label: {
                settingLabel(isHome ? "Home Page" : "Set as Home",
                             isHome ? "house.fill" : "house", labelled)
            }
            .tint(isHome ? .blue : .secondary)
            if scene.revealLevelCount > 0 {
                Menu {
                    Picker("Preview Level", selection: $previewLevel) {
                        Text("All Levels").tag(0)
                        ForEach(1...scene.revealLevelCount, id: \.self) { level in
                            Text("Level \(level)").tag(level)
                        }
                    }
                } label: {
                    settingLabel(previewLevel == 0 ? "All Levels" : "Preview L\(previewLevel)",
                                 "stairs", labelled)
                }
            }
            if !scene.isDefault, scene.pages.contains(where: { $0.key != pageKey }) {
                // Put a folder to this page on others — the step Add Page and
                // Import Page offer once, here whenever it was skipped.
                Button { isLinkingPage = true } label: {
                    settingLabel("Link From…", "arrow.turn.down.right", labelled)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.subheadline)
    }

    @ViewBuilder
    private func settingLabel(_ title: String, _ icon: String, _ labelled: Bool) -> some View {
        if labelled {
            Label(title, systemImage: icon)
        } else {
            Image(systemName: icon).accessibilityLabel(title)
        }
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
            if page != nil {
                VStack(spacing: 0) {
                    if !keyboardUp { pageHeader }
                    PageSpreadsheetView(
                        scene: scene,
                        tiles: tilesBinding,
                        lookup: tileLookup,
                        systemPages: systemScenes.first.map { $0.id == scene.id ? [] : $0.pages } ?? [],
                        cells: pageCells,
                        chrome: BoardChrome.inherits(scene)
                            ? BoardChrome.row(for: scene, level: scene.effectiveRevealLevel) : [],
                        previewLevel: previewLevel,
                        onProperties: { editingTileKey = $0 },
                        onAddWords: { openPicker(from: $0) },
                        onKeepReview: { keepReview($0) },
                        onRemoveReviewed: { removeReviewed($0) },
                        editRequest: cellEditRequest,
                        isCovered: editingTileKey != nil || isPickingTiles || isChoosingCover
                            || isRenaming || isSharingPage || isLinkingPage)
                }
            } else {
                ContentUnavailableView("Page not found", systemImage: "questionmark.folder")
            }
        }
        // The scene the page belongs to; the page's own name is on its card.
        .navigationTitle(scene.name)
        // The grid this page is laid out on, so a caregiver arranging words
        // knows which board's positions they are setting.
        .navigationSubtitle(scene.designedLayout.map { "Designed for \($0.title)" }
                            ?? "\(boardGrid.cols)×\(boardGrid.rows) · this device's layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(keyboardUp ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .animation(.easeOut(duration: 0.2), value: keyboardUp)
        // A hardware keyboard reports only its shortcut bar, well under this.
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            keyboardUp = (end?.height ?? 0) > 150
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        // Editing a page can change what the folders pointing AT it should
        // look like. Automatic folder colors are stored, not computed when
        // drawn, so this is the one moment they are allowed to move — see
        // `SceneLinkColors`. It writes only when something actually changed, so
        // the write it performs does not retrigger itself.
        //
        // Watches the whole scene, not `page?.tiles`. A folder's color depends
        // on a *different* page's contents than the one it sits on, so the
        // narrower dependency was simply the wrong one.
        .onAppear { SceneLinkColors.refresh(scene: scene, context: modelContext) }
        .onChange(of: scene.pages) {
            SceneLinkColors.refresh(scene: scene, context: modelContext)
        }
        .toolbar { pageEditorToolbar }
        .sheet(isPresented: $isLinkingPage) {
            PageLinkPlacementSheet(scene: scene, target: PageLinkTarget(pageKey: pageKey), allTiles: allTiles)
        }
        .sheet(isPresented: $isChoosingCover) {
            NavigationStack {
                CoverPickerView(subject: .page(pageKey, in: scene))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isChoosingCover = false }
                        }
                    }
            }
        }
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
                                onRemove: { remove(key: key) },
                                onEditCell: {
                                    editingTileKey = nil
                                    cellEditRequest += 1
                                })
        }
        .task {
            guard !autoOpenPickerWithKeys.isEmpty else { return }
            pickerInitialKeys = autoOpenPickerWithKeys
            prePickerSnapshot = page?.tiles ?? []
            isPickingTiles = true
        }
    }

    // MARK: - Add / Remove

    private var pageCells: PageCells {
        PageCells(grid: boardGrid, inheritsChrome: BoardChrome.inherits(scene))
    }

    private func openPicker(from start: Int) {
        pickerInitialKeys = []
        pickerStart = start
        prePickerSnapshot = page?.tiles ?? []
        isPickingTiles = true
    }

    /// The picker inserts its words at the front of the page, which would push
    /// every word after them along. On a board that is a different board, so
    /// they are taken back out and put into empty cells instead, from the
    /// cell the caregiver chose: nothing already placed moves.
    private func pickerDismissed() {
        pickerInitialKeys = []
        defer { prePickerSnapshot = nil; pickerStart = 0 }
        guard let before = prePickerSnapshot else { return }
        let after = page?.tiles ?? []
        guard before != after else { return }
        recordUndo(before)
        if after.count > before.count, Array(after.suffix(before.count)) == before {
            let added = Array(after.prefix(after.count - before.count))
            setTiles(pageCells.placing(added, intoEmptyFrom: pickerStart, in: before))
        }
    }

    /// Takes a word off the page and leaves its cell empty, so nothing else moves.
    private func remove(key: String) {
        guard let page, let index = page.tiles.firstIndex(where: { $0.key == key }) else { return }
        recordUndo(page.tiles)
        setTiles(pageCells.setting(nil, at: index, in: page.tiles))
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
    /// Adding words belongs to a cell — the picker fills empty cells from the
    /// selected one — so it lives in the grid's option bar beside the
    /// selection, not in the navigation bar.
    ///
    /// **Share is the bar's action.** It has no representation anywhere else
    /// on the page, and a caregiver looking to send a page somewhere looks in
    /// the navigation bar — so it is a visible button, not a menu item, at every
    /// width. It is gated on the page having tiles: an empty page has nothing to
    /// share.
    @ToolbarContentBuilder
    private var pageEditorToolbar: some ToolbarContent {
        if isCompactWidth {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .accessibilityLabel("Undo and redo")
            }
        } else {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(undoStack.isEmpty)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(redoStack.isEmpty)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if hasTiles {
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

        let title = trimmed.isEmpty ? PageNaming.displayName(pageKey) : trimmed
        if let link = tileLookup[PageLink.key(forPage: pageKey)] {
            link.displayName = title
        }
        PageCover.renamed(page: pageKey, in: scene, to: title, lookup: tileLookup)
        try? modelContext.save()
        isRenaming = false
    }

    /// Whether the page has anything on it — gates Share.
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
        DashedCell(label: "space", look: TileLook.current())
    }
}

/// A cell the child never sees — a gap, the editor's Add — drawn as a dashed
/// outline the shape of a tile, so it lines up with the tiles around it: the
/// whole square on the square look, the picture with its word under it on the
/// classic one.
struct DashedCell: View {
    var systemImage: String? = nil
    let label: String
    let look: TileLook

    var body: some View {
        if look == .square {
            RoundedRectangle(cornerRadius: TileFace.radius(look))
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.tertiary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 2) {
                        if let systemImage {
                            Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary)
                        }
                        Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    }
                }
        } else {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let systemImage {
                            Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary)
                        }
                    }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct PageTileCell: View {
    let tile: TileModel
    var link: String = ""
    /// The slot this link is colored as. Nil on a word tile.
    var linkColor: String? = nil
    /// A doorway (speaks and opens a page) keeps its own color in every mode.
    var isAudible: Bool = true
    /// Concealed on this page: still drawn, deliberately muted, and badged.
    var isConcealed: Bool = false
    /// The level this placement appears from, badged when above 1. 0 hides
    /// the badge (always shown, or a scene without levels).
    var revealLevel: Int = 0
    /// Above the level the editor is previewing: muted like a concealed cell,
    /// because that is what the child at that level sees.
    var isAbovePreview: Bool = false

    var body: some View {
        // The editor draws the tile the way the child will see it: the board's
        // own face, so a caregiver grouping the page into colour blocks — the
        // whole point of a Fitzgerald layout — sees the blocks the child will.
        // It once drew every folder blue for a board that renders them in six
        // colours, and a caregiver arranging by colour was arranging against a
        // picture that did not exist.
        TileFace(tile: tile, key: tile.key, link: link, linkColor: linkColor,
                 isAudible: isAudible, labelFontSize: 10)
        .opacity(isConcealed || isAbovePreview ? 0.32 : 1)
        // Outside the muting, and pinned to the square rather than the whole
        // card: the badge says "this word is hidden", so it must stay legible on
        // a tile that has been dimmed to a third, and it belongs over the
        // picture, not floating between the picture and the word.
        .overlay(alignment: .top) {
            if isConcealed {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "eye.slash.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if revealLevel > 1 {
                Text("L\(revealLevel)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .foregroundStyle(.white)
                    .padding(4)
                    .accessibilityLabel("Appears from level \(revealLevel)")
            }
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
    /// Puts a different word in this cell: closes the sheet and types the
    /// cell's text in the grid. The word itself — its key — never changes.
    var onEditCell: (() -> Void)? = nil
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    /// BlasterAI 60, whose pages any scene can link to (`TileToken.systemPrefix`).
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]
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
    /// **It sets the part of speech, not the color**, even though color is
    /// what a caregiver notices. Picking a color directly would break the axis
    /// the color stands for: two words could end up the same color with
    /// different parts of speech, and the coverage report would then disagree
    /// with the board. One axis, and the color follows from it.
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
    /// coverage report counts the word the same way the board colors it.
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

    private var automaticLabel: String {
        guard let automaticLinkSlot else { return "Automatic" }
        return "Automatic (\(automaticLinkSlot.label))"
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
                // Resolve the color the moment the link is made or repointed,
                // rather than waiting for the next page edit — otherwise a
                // brand-new folder sits in wayfinding blue until something
                // unrelated happens, which reads as the feature not working.
                // An explicitly chosen color is left alone.
                if newValue.isEmpty {
                    pages[p].tiles[t].linkColor = nil
                    pages[p].tiles[t].linkColorIsAuto = true
                } else if pages[p].tiles[t].linkColorIsAuto {
                    pages[p].tiles[t].linkColor = automaticSlot(
                        forLinkTo: newValue, isAudible: pages[p].tiles[t].isAudible,
                        in: pages).rawValue
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

    /// Visibility as one choice: -1 concealed, 0 always shown, N from level N.
    /// Same three states as the grid editor's multi-select menu.
    private var visibilityBinding: Binding<Int> {
        Binding(
            get: {
                guard let entry else { return 0 }
                if entry.isConcealed { return -1 }
                return entry.revealLevel > 1 ? entry.revealLevel : 0
            },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                pages[p].tiles[t].isConcealed = newValue < 0
                if newValue >= 0 { pages[p].tiles[t].revealLevel = newValue }
                scene.pages = pages
            }
        )
    }

    /// The link's color slot, or nil for "work it out from the destination".
    ///
    /// Writing nil does not merely clear the stored value — it re-resolves and
    /// stores the answer, and flips `linkColorIsAuto` back on. "Automatic" is a
    /// standing instruction to follow the page, not an absence of one, which is
    /// what lets a later edit to that page move this color.
    private var linkColorBinding: Binding<TileColorSlot?> {
        Binding(
            get: {
                guard let entry, entry.linkColorIsAuto == false,
                      let raw = entry.linkColor else { return nil }
                return TileColorSlot(rawValue: raw)
            },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                if let newValue {
                    pages[p].tiles[t].linkColor = newValue.rawValue
                    pages[p].tiles[t].linkColorIsAuto = false
                } else {
                    pages[p].tiles[t].linkColorIsAuto = true
                    pages[p].tiles[t].linkColor = automaticSlot(
                        forLinkTo: pages[p].tiles[t].link,
                        isAudible: pages[p].tiles[t].isAudible, in: pages).rawValue
                }
                scene.pages = pages
            }
        )
    }

    /// What "Automatic" would pick for this link right now.
    private var automaticLinkSlot: TileColorSlot? {
        guard let entry, !entry.link.isEmpty else { return nil }
        return automaticSlot(forLinkTo: entry.link, isAudible: entry.isAudible, in: scene.pages)
    }

    /// The color a link to `link` resolves to on its own. A BlasterAI 60 page
    /// is resolved against the core board, where that page lives.
    private func automaticSlot(forLinkTo link: String, isAudible: Bool,
                               in pages: [PageSpec]) -> TileColorSlot {
        let systemKey = TileToken.systemPageKey(link)
        return SceneLinkColors.slot(
            forLinkTo: systemKey ?? link,
            spokenAs: tileKey,
            isAudible: isAudible,
            in: systemKey == nil ? pages : (systemScenes.first?.pages ?? []),
            vocabulary: allTiles.map(\.key),
            partOfSpeech: { PartOfSpeechIndex.partOfSpeech(for: $0) })
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
                            HStack(spacing: 8) {
                                Text("key: \(tile?.key ?? tileKey)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let onEditCell {
                                    Button {
                                        onEditCell()
                                        dismiss()
                                    } label: {
                                        Label("Edit Cell", systemImage: "pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .accessibilityHint("Type a different word or link for this cell")
                                }
                            }
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

                    if scene.revealLevelCount > 0 {
                        Picker("Visibility", selection: visibilityBinding) {
                            Text("Always Shown").tag(0)
                            ForEach(2...max(scene.revealLevelCount, 2), id: \.self) { level in
                                Text("From Level \(level)").tag(level)
                            }
                            Text("Concealed").tag(-1)
                        }
                    } else {
                        Toggle("Conceal on this page", isOn: entryBinding.concealed)
                    }
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
                        // The core board's own pages. Not offered on the core
                        // board itself, where they are already the list above.
                        // Each label names the board: a menu-style picker does
                        // not draw a Section header, so a heading would not say
                        // whose Actions page this is.
                        if let system = systemScenes.first, system.id != scene.id {
                            Divider()
                            ForEach(system.pages, id: \.key) { page in
                                let link = TileToken.systemLink(to: page.key)
                                Text(SystemLinks.displayName(of: link)).tag(link)
                            }
                        }
                    }
                    let currentLink = entry?.link ?? ""
                    if !currentLink.isEmpty {
                        Text("Tapping this tile navigates to \"\(SystemLinks.displayName(of: currentLink))\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NavigationLink {
                            LinkColorPickerList(selection: linkColorBinding,
                                                automatic: automaticLinkSlot,
                                                destination: currentLink)
                        } label: {
                            HStack(spacing: 8) {
                                partOfSpeechSwatch(
                                    TileColorResolver.linkColor(
                                        slotRawValue: entry?.linkColor))
                                Text("Folder color")
                                if entry?.linkColorIsAuto == false {
                                    Text("edited")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                                Spacer(minLength: 8)
                                Text(linkColorBinding.wrappedValue?.label
                                     ?? automaticLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
/// A dot in the tile's real board color. Drawn rather than an SF Symbol so it
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
/// A pushed list rather than a menu because the color is the point, and a menu
/// renders its option icons monochrome. Here each row owns its own swatch, so a
/// therapist picks the color they can see.
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
                     + "Choose a type to override it — the tile's color follows.")
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

// MARK: - Folder color picker

/// Choose what color a page link draws in.
///
/// Mirrors `PartOfSpeechPickerList` deliberately — same shape, same "Automatic
/// (X)" first row, same rule that clearing back to Automatic is how an override
/// is undone. A caregiver meets both of these in the same sheet, and two
/// pickers that answer similar questions differently is a worse cost than the
/// duplication.
///
/// **It offers slots, not colors.** A swatch grid would let someone pick a green
/// that means nothing, and the folder would then stop following the child's
/// palette — the same reasoning that made `TileEntry.linkColor` store a slot
/// rather than a hex. Every swatch here is drawn through the active palette, so
/// what a caregiver sees is what that child will see.
struct LinkColorPickerList: View {
    @Binding var selection: TileColorSlot?
    let automatic: TileColorSlot?
    let destination: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(nil, label: automaticLabel,
                    color: TileColorResolver.color(for: automatic ?? .wayfinding))
            } footer: {
                Text("Automatic colors this folder like the words on \"\(destination)\", "
                     + "and follows that page if it changes. Choose a color to pin it.")
            }

            Section("Navigation") {
                row(.wayfinding, label: TileColorSlot.wayfinding.label,
                    color: TileColorResolver.color(for: .wayfinding))
            }

            Section("Word type") {
                ForEach(PartOfSpeech.display) { pos in
                    row(.partOfSpeech(pos), label: pos.label,
                        color: TileColorResolver.color(for: pos))
                }
            }
        }
        .navigationTitle("Folder Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var automaticLabel: String {
        guard let automatic else { return "Automatic" }
        return "Automatic (\(automatic.label))"
    }

    @ViewBuilder
    private func row(_ value: TileColorSlot?, label: String, color: Color) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack(spacing: 10) {
                partOfSpeechSwatch(color, size: 14)
                Text(label).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}
