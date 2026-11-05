// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageSpreadsheetView.swift
//  claudeBlast
//
//  The page editor's Grid mode: a page as a spreadsheet of cells.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

/// A page edited as a spreadsheet: every cell of the board grid is addressable,
/// and a cell is filled by typing it (see `BoardCell` for the grammar).
///
/// ## Why a formula bar, not a field in the cell
///
/// A cell is a picture the size of a thumbnail, and a cell like
/// `starfish, animal > tide_pools` does not fit in one. The text is edited in a
/// bar over the grid, as in Numbers, with the suggestions under it; the cell
/// shows the tile it will become.
///
/// ## Nothing reflows
///
/// The page is a fixed grid (`PageCells`), so every change touches only the
/// cells it names. A tile dragged to a gap moves there and leaves a gap; one
/// dropped on a word swaps with it; a block lands only on empty cells. A child
/// who has learned where `want` is never has to find it again because a
/// caregiver tidied the page.
///
/// ## Keyboard
///
/// Arrows move; Shift-arrows select a block; Tab and Shift-Tab go across;
/// Return edits, and in an edit commits and goes to the next cell across,
/// wrapping to the next row; typing starts an edit
/// with that character; Delete empties the selection; Escape cancels. ⌘C ⌘X ⌘V
/// copy, cut and paste cells as tab-separated text, the same as a
/// spreadsheet's; ⌘A selects every word; ⌘F searches the word well. In an edit, the arrows walk the
/// suggestions (← → as they run, ↑ ↓ too) and Tab takes one; with no
/// suggestions showing, ← → move the caret.
///
/// Every key arrives through the formula bar's field, which stays first
/// responder for as long as the grid is on screen: when no cell is being
/// edited it moves the selection, and when one is it edits. SwiftUI focus on
/// the grid itself was tried first and lost the keyboard to every tap.
///
/// ## Touch
///
/// A tap on a word opens Tile Settings — art, class, link — whose Edit Cell
/// comes back to type a different word there. A tap on an empty cell selects
/// it, a second tap edits it. Tapping another cell during an edit commits it
/// (Cancel drops it). The on-screen keyboard then stays up
/// from cell to cell — typing in the selected cell starts it — until Cancel
/// or the caregiver lowers it. Press and drag moves a tile,
/// or the whole selection's words when the tile is part of it: dropped on a
/// cell's middle it moves or swaps, on its left edge it goes in front and the
/// run shifts into its gap. In landscape the word well (`WordWellView`) sits to
/// the left; its words drop the same way. Select (in the ⋯ menu)
/// turns taps into adding and removing cells from the selection. Each cell's
/// menu carries what the selection can do: visibility, cut, copy, paste, clear.
///
/// Edits go through `tiles`, so each change is one step of the page editor's
/// undo.
struct PageSpreadsheetView: View {
    @Bindable var scene: BlasterScene
    @Binding var tiles: [TileEntry]
    let lookup: [String: TileModel]
    /// BlasterAI 60's pages, for links to them. Empty when editing it.
    let systemPages: [PageSpec]
    let cells: PageCells
    /// The system row drawn over each screen; empty when not inherited.
    let chrome: [TileEntry]
    var previewLevel: Int = 0
    var onProperties: (String) -> Void = { _ in }
    /// Opens the word picker; its words go into empty cells from this index.
    var onAddWords: (Int) -> Void = { _ in }
    var onKeepReview: (TileModel) -> Void = { _ in }
    var onRemoveReviewed: (TileModel) -> Void = { _ in }
    /// Bumped by Tile Settings' Edit: type the selected cell's text, keyboard up.
    var editRequest: Int = 0
    /// A sheet is over the editor: the formula bar lets go of focus, or the
    /// keyboard comes up behind Tile Settings.
    var isCovered: Bool = false

    @Environment(\.modelContext) private var modelContext
    /// Handed to the drag preview, which draws outside this view's hierarchy
    /// and so without its environment; a tile face reached for it and trapped.
    @Environment(TileImageResolver.self) private var resolver

    @State private var selected = PageCells.Cell(screen: 0, row: 0, col: 0)
    /// Cells selected besides the cursor's; empty means the cursor alone.
    @State private var selection: Set<Int> = []
    /// Where a Shift-arrow block started.
    @State private var anchor: Int?
    /// Taps add and remove cells instead of moving the cursor.
    @State private var isSelecting = false
    /// The cell's text while it is edited; nil when not editing.
    @State private var draft: String?
    /// The on-screen keyboard stays up from cell to cell: Return or a tap on
    /// another cell commits and leaves it up, so the next cell is typed
    /// straight away, as with a hardware keyboard. Cancel, or lowering the
    /// keyboard, ends the run.
    @State private var keyboardRun = false
    @State private var error: String?
    @State private var highlighted = 0
    /// Screens shown beyond those the page fills, so a new screen can be typed into.
    @State private var extraScreens = 0
    /// Bumped to hand the keyboard back to the formula bar after a tap.
    @State private var focusToken = 0
    /// Bumped by ⌘F to put the cursor in the well's search field.
    @State private var wellSearchToken = 0
    @AppStorage("pageEditorWellVisible") private var wellVisible = true
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Where the well goes: beside the grid on a landscape iPad or a wide Mac
    /// window, above it on a portrait iPad (the grid keeps its 10×6 there,
    /// with room to spare below the keyboard's reach), nowhere on a phone.
    private enum WellPlacement { case side, top, none }
    private func wellPlacement(_ size: CGSize) -> WellPlacement {
        guard hSizeClass == .regular else { return .none }
        return size.width > size.height * 1.15 ? .side : .top
    }
    /// The cell a drag is over, and whether it is over the cell's leading
    /// edge (insert in front) rather than its middle (move or swap).
    @State private var dropTarget: Int?
    @State private var dropInserts = false
    /// Filled cells a refused move would have covered, outlined until the next change.
    @State private var blocked: Set<Int> = []
    /// A level chosen on a board without levels, waiting on "turn them on?".
    @State private var pendingLevel: Int?

    private let spacing: CGFloat = 6
    private static let dragPrefix = "blaster-cell:"
    /// A word dragged from the well, as cell text.
    static let textPrefix = "blaster-text:"
    private static let starterLevelCount = 5

    private var screens: Int { cells.screenCount(tiles) + extraScreens }
    private var selectedIndex: Int { cells.index(of: selected) }
    /// What an action applies to: the selection, else the cursor's cell.
    private var targets: Set<Int> { selection.isEmpty ? [selectedIndex] : selection }

    var body: some View {
        GeometryReader { outer in
            let placement = wellPlacement(outer.size)
            let showsWell = placement != .none && wellVisible
            HStack(spacing: 0) {
                if showsWell, placement == .side {
                    well(compact: false)
                        // Room for three tiles with their labels across.
                        .frame(width: max(300, outer.size.width * 0.27))
                    Divider()
                }
                VStack(spacing: 0) {
                    formulaBar(hasWell: placement != .none)
                    Divider()
                    if showsWell, placement == .top {
                        // Over the grid, not under it: the keyboard rises from
                        // the bottom, and the well is where a search is typed.
                        well(compact: true)
                            .frame(height: min(340, outer.size.height * 0.34))
                        Divider()
                    }
                    GeometryReader { geo in
                        ScrollViewReader { proxy in
                            ScrollView {
                                grid(width: geo.size.width - 32)
                                    .padding(16)
                            }
                            .onChange(of: selected) { proxy.scrollTo(selected, anchor: nil) }
                            // The keyboard rising, the suggestion strip opening
                            // or the bars hiding all shrink or move the grid:
                            // bring the cursor's cell back into view once the
                            // new layout has landed — scrolling in the same pass
                            // scrolls against the old one and misses.
                            .onChange(of: geo.size.height) {
                                DispatchQueue.main.async {
                                    withAnimation { proxy.scrollTo(selected, anchor: nil) }
                                }
                            }
                            .onChange(of: draft == nil) {
                                DispatchQueue.main.async { proxy.scrollTo(selected, anchor: nil) }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: editRequest) { editFromSettings() }
        // Undo can take away the screen the cursor was on.
        .onChange(of: tiles) {
            let last = screens * cells.perScreen - 1
            if selectedIndex > last { selected = cells.cell(at: last) }
            selection = selection.filter { $0 <= last }
        }
        .alert("Give this board levels?", isPresented: Binding(
            get: { pendingLevel != nil }, set: { if !$0 { pendingLevel = nil } })) {
            Button("Turn On \(Self.starterLevelCount) Levels") {
                if let level = pendingLevel {
                    scene.setRevealLevelCount(Self.starterLevelCount)
                    try? modelContext.save()
                    setVisibility(concealed: false, level: level)
                }
                pendingLevel = nil
            }
            Button("Cancel", role: .cancel) { pendingLevel = nil }
        } message: {
            Text("Levels let a board start small and grow. Words you show from a "
                 + "higher level stay in place as empty cells until the board "
                 + "reaches it. The board starts at its top level, so nothing "
                 + "disappears until you step it down.")
        }
    }

    private func well(compact: Bool) -> some View {
        WordWellView(lookup: lookup, scenePages: scene.pages, systemPages: systemPages,
                     sceneID: scene.sceneID,
                     onPage: Set(tiles.filter { !$0.isSpacer }.map(\.key)),
                     searchFocusToken: wellSearchToken,
                     onPlace: { placeAtCursor($0) },
                     onDone: { focusToken += 1 },
                     dragPrefix: Self.textPrefix,
                     isCompact: compact)
    }

    // MARK: - Formula bar

    private func formulaBar(hasWell: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if hasWell {
                    Button { wellVisible.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel(wellVisible ? "Hide words" : "Show words")
                }
                if showsSelectionBar {
                    // Always visible while it exists, and one tap to end it:
                    // a forgotten selection rides along on the next drag.
                    Button { deselect(); isSelecting = false } label: {
                        Label("\(selection.count) selected", systemImage: "xmark.circle.fill")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear the selection of \(selection.count) cells")
                } else {
                    Text(address(selected))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 64, alignment: .leading)
                }
                CellTextField(text: draftBinding,
                              placeholder: "word · word, class · word > page · > page",
                              isEditing: draft != nil,
                              showsKeyboard: keyboardRun,
                              arrowsChoose: draft != nil && !suggestions.isEmpty,
                              focusToken: focusToken,
                              isSuspended: isCovered,
                              onKey: key,
                              onType: { typed in
                                  if let draft { self.draft = draft + typed } else { beginEdit(with: typed) }
                                  error = nil
                                  highlighted = 0
                              },
                              onClear: { clear(targets) },
                              onRaise: { keyboardRun = true },
                              onLowered: keyboardLowered)
                    .frame(height: 34)
                    // The field stays first responder underneath (hardware keys
                    // still reach it); a selection shows what it can do instead.
                    .opacity(showsSelectionBar ? 0 : 1)
                    .overlay(alignment: .leading) {
                        if showsSelectionBar { selectionBar }
                    }
                if draft != nil {
                    Button("Cancel") { cancelEdit(); keyboardRun = false }
                        .font(.subheadline)
                } else {
                    if isSelecting {
                        Button("Done") { isSelecting = false }
                            .font(.subheadline.weight(.semibold))
                    }
                    pageMenu
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if draft != nil, !suggestions.isEmpty {
                suggestionStrip
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// A selection of cells, in the bar rather than behind ⋯: the old editor's
    /// actions sat on the selection, and going back to a menu for each was the
    /// step too many.
    private var showsSelectionBar: Bool {
        draft == nil && (selection.count > 1 || (isSelecting && !selection.isEmpty))
    }

    private var selectionBar: some View {
        let filled = selection.filter { cells.entry(at: $0, in: tiles) != nil }
        return ViewThatFits(in: .horizontal) {
            selectionButtons(filled, labelled: true)
            selectionButtons(filled, labelled: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func selectionButtons(_ filled: Set<Int>, labelled: Bool) -> some View {
        HStack(spacing: 8) {
            Menu { visibilityItems(filled) } label: {
                barLabel("Visibility", "eye", labelled)
            }
            .disabled(filled.isEmpty)
            Button { cut(selection) } label: { barLabel("Cut", "scissors", labelled) }
                .disabled(filled.isEmpty)
            Button { copy(selection) } label: { barLabel("Copy", "doc.on.doc", labelled) }
                .disabled(filled.isEmpty)
            Button(role: .destructive) { clear(selection) } label: {
                barLabel("Clear", "xmark.square", labelled)
            }
            .tint(.red)
            .disabled(filled.isEmpty)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func barLabel(_ title: String, _ icon: String, _ labelled: Bool) -> some View {
        if labelled { Label(title, systemImage: icon) } else {
            Image(systemName: icon).accessibilityLabel(title)
        }
    }

    /// What the selection, or the whole page, can do — the touch way to every
    /// keyboard command.
    private var pageMenu: some View {
        Menu {
            Button { onAddWords(selectedIndex) } label: {
                Label("Add Words…", systemImage: "plus.square.on.square")
            }
            Divider()
            Button { isSelecting.toggle() } label: {
                Label(isSelecting ? "Stop Selecting" : "Select Cells", systemImage: "checkmark.circle")
            }
            Button { selectAll() } label: { Label("Select All", systemImage: "square.grid.3x3.fill") }
            if !selection.isEmpty {
                Button { deselect() } label: { Label("Deselect", systemImage: "square.dashed") }
            }
            Divider()
            selectionActions(targets)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("Cell actions")
    }

    /// Visibility, clipboard and clear, for `indices`. Shared by the ⋯ menu
    /// and each cell's own menu.
    @ViewBuilder
    private func selectionActions(_ indices: Set<Int>) -> some View {
        let filled = indices.filter { cells.entry(at: $0, in: tiles) != nil }
        if !filled.isEmpty {
            Menu { visibilityItems(filled) } label: {
                Label("Visibility", systemImage: "eye")
            }
            if filled.count == 1, let entry = cells.entry(at: filled.first!, in: tiles),
               let wordClass = lookup[entry.key]?.wordClass, !wordClass.isEmpty {
                Button { selectClass(wordClass) } label: {
                    Label("Select All \(wordClass.capitalized)", systemImage: "square.stack.3d.up")
                }
            }
        }
        Button { cut(indices) } label: { Label("Cut", systemImage: "scissors") }
            .disabled(filled.isEmpty)
        Button { copy(indices) } label: { Label("Copy", systemImage: "doc.on.doc") }
            .disabled(filled.isEmpty)
        Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
        if !filled.isEmpty {
            Button(role: .destructive) { clear(indices) } label: {
                Label(filled.count == 1 ? "Clear Cell" : "Clear \(filled.count) Cells", systemImage: "xmark.square")
            }
        }
    }

    /// Shown always, from a level, or concealed — for the ⋯ menu, a cell's
    /// menu and the selection bar.
    @ViewBuilder
    private func visibilityItems(_ filled: Set<Int>) -> some View {
        Button { setVisibility(concealed: false, level: 0, at: filled) } label: {
            Label("Always Shown", systemImage: "eye")
        }
        Section("Show From Level") {
            ForEach(Array(offeredLevels), id: \.self) { level in
                Button("Level \(level)") {
                    if scene.revealLevelCount > 0 {
                        setVisibility(concealed: false, level: level, at: filled)
                    } else {
                        selection = filled
                        pendingLevel = level
                    }
                }
            }
        }
        Button { setVisibility(concealed: true, level: nil, at: filled) } label: {
            Label("Concealed", systemImage: "eye.slash")
        }
    }

    private var offeredLevels: ClosedRange<Int> {
        2...(scene.revealLevelCount > 0 ? max(scene.revealLevelCount, 2) : Self.starterLevelCount)
    }

    /// The bar shows the selected cell's text until an edit starts.
    private var draftBinding: Binding<String> {
        Binding(
            get: { draft ?? cellText(selectedIndex) },
            set: { text in
                draft = text
                error = nil
                highlighted = 0
            }
        )
    }

    private var suggestionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { i, suggestion in
                        Button { accept(suggestion) } label: {
                            suggestionLabel(suggestion)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(i == highlighted ? Color.accentColor.opacity(0.18) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(i == highlighted ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
            }
            // The highlighted suggestion stays in view as the arrows walk the strip.
            .onChange(of: highlighted) { withAnimation { proxy.scrollTo(highlighted, anchor: .center) } }
        }
    }

    @ViewBuilder
    private func suggestionLabel(_ suggestion: CellSuggestion) -> some View {
        switch suggestion {
        case .word(let key):
            VStack(spacing: 2) {
                PageTileCell(tile: lookup[key]!, isAudible: true)
                    .frame(width: 64)
                Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        case .page(let key, let isSystem):
            Label(isSystem ? "BlasterAI › \(PageNaming.displayName(key))"
                           : (scene.page(withKey: key)?.title ?? key),
                  systemImage: isSystem ? "square.grid.3x3.fill" : "folder")
                .font(.subheadline)
                .padding(.horizontal, 8).padding(.vertical, 6)
        case .newPage(let key):
            Label("New page \u{201C}\(PageNaming.displayName(key))\u{201D}", systemImage: "folder.badge.plus")
                .font(.subheadline)
                .padding(.horizontal, 8).padding(.vertical, 6)
        case .wordClass(let name):
            let color = TileColorResolver.color(for: VocabularyClasses.known(name)?.defaultPartOfSpeech)
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 11, height: 11)
                Text(name.capitalized).font(.subheadline)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.18)))
        }
    }

    private var suggestions: [CellSuggestion] {
        CellSuggestion.suggestions(for: draft ?? "", lookup: lookup,
                                   scenePages: scene.pages, systemPages: systemPages)
    }

    // MARK: - Grid

    private func grid(width: CGFloat) -> some View {
        let side = max(40, (width - spacing * CGFloat(cells.cols - 1)) / CGFloat(cells.cols))
        let columns = Array(repeating: GridItem(.fixed(side), spacing: spacing), count: cells.cols)
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<screens, id: \.self) { screen in
                VStack(alignment: .leading, spacing: 8) {
                    if screens > 1 {
                        Text("Screen \(screen + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(chrome.prefix(cells.cols).enumerated()), id: \.offset) { _, entry in
                            entryView(entry)
                                .opacity(entry.isEmptyCell ? 0 : 0.4)
                                .allowsHitTesting(false)
                        }
                        ForEach(0..<cells.perScreen, id: \.self) { i in
                            let cell = cells.cell(at: screen * cells.perScreen + i)
                            cellView(cell, side: side).id(cell)
                        }
                    }
                }
            }
            Button {
                extraScreens += 1
                select(PageCells.Cell(screen: screens - 1, row: 0, col: 0))
            } label: {
                Label("Add a Screen", systemImage: "plus.rectangle.on.rectangle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: PageCells.Cell, side: CGFloat) -> some View {
        let index = cells.index(of: cell)
        let entry = cells.entry(at: index, in: tiles)
        let isCursor = cell == selected
        let isInSelection = selection.contains(index)
        ZStack {
            if isCursor, let draft, let preview = previewEntry(draft) {
                entryView(preview).opacity(0.7)
            } else if let entry {
                entryView(entry)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .overlay {
            if isInSelection {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The stock multi-select mark: an empty ring on every cell while
            // selecting, filled with a check on the chosen ones.
            if isInSelection || isSelecting {
                Image(systemName: isInSelection ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: max(14, side * 0.22), weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isInSelection ? Color.accentColor : Color.black.opacity(0.15))
                    .background {
                        // White rim on the chosen check so it reads on any tile colour.
                        if isInSelection { Circle().fill(.white).padding(-1.5) }
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(outline(index: index, isCursor: isCursor, isInSelection: isInSelection),
                              lineWidth: isCursor || (dropTarget == index && !dropInserts)
                                || blocked.contains(index) ? 3 : 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { tap(cell) }
        .modifier(DragSource(payload: entry == nil || draft != nil ? nil : Self.dragPrefix + String(index)) {
            if let entry { entryView(entry).frame(width: 72).environment(resolver) }
        })
        .overlay(alignment: .leading) {
            if dropTarget == index, dropInserts {
                Capsule().fill(Color.green).frame(width: 5)
                    .offset(x: -(spacing / 2 + 2.5))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.plainText], delegate: CellDropDelegate(
            index: index,
            side: side,
            onUpdate: { inserts in dropTarget = index; dropInserts = inserts },
            onExit: { if dropTarget == index { dropTarget = nil } },
            onDrop: { text, inserts in drop(text, at: index, inserting: inserts) }))
        .contextMenu {
            let menuTargets = isInSelection ? targets : [index]
            if menuTargets.count == 1, let entry, lookup[entry.key] != nil {
                Button { onProperties(entry.key) } label: {
                    Label("Properties", systemImage: "slider.horizontal.3")
                }
            }
            selectionActions(menuTargets)
        }
        .accessibilityLabel(address(cell) + ": " + (entry.map { cellText(index: index, $0) } ?? "empty"))
    }

    private func outline(index: Int, isCursor: Bool, isInSelection: Bool) -> Color {
        if blocked.contains(index) { return .red }
        if dropTarget == index, !dropInserts { return .green }
        // While selecting, the checks say what is chosen; a cursor ring on an
        // unchosen cell would read as chosen too.
        if isCursor, !isSelecting || draft != nil { return error == nil ? .accentColor : .orange }
        return isInSelection ? .accentColor : .clear
    }

    @ViewBuilder
    private func entryView(_ entry: TileEntry) -> some View {
        if entry.isSpacer {
            Color.clear.aspectRatio(1, contentMode: .fit)
        } else if let tile = lookup[entry.key] {
            PageTileCell(tile: tile, link: entry.link, linkColor: entry.linkColor,
                         isAudible: entry.isAudible, isConcealed: entry.isConcealed,
                         revealLevel: scene.revealLevelCount > 0 ? entry.revealLevel : 0,
                         isAbovePreview: previewLevel > 0 && entry.isAboveLevel(previewLevel))
                .overlay(alignment: .bottomTrailing) {
                    TileReviewBadge(tile: tile,
                                    onKeep: { onKeepReview(tile) },
                                    onRemove: { onRemoveReviewed(tile) })
                }
        } else {
            // A word that will be made on commit, or a key nothing resolves.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text(entry.key.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
        }
    }

    /// What the cell will hold if `text` is committed, for the live preview.
    private func previewEntry(_ text: String) -> TileEntry? {
        guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                                      scenePages: scene.pages,
                                                      systemPages: systemPages) else { return nil }
        return plan.entry
    }

    // MARK: - Text

    private func cellText(_ index: Int) -> String {
        guard let entry = cells.entry(at: index, in: tiles) else { return "" }
        return cellText(index: index, entry)
    }

    private func cellText(index: Int, _ entry: TileEntry) -> String {
        BoardCell.format(entry, cover: BoardCell.covers(scenePages: scene.pages, systemPages: systemPages,
                                                        isSystemScene: scene.isDefault))
    }

    /// "R2 C3": rows counted as the board counts them, the system row as row 1.
    private func address(_ cell: PageCells.Cell) -> String {
        let row = cell.row + 1 + (chrome.isEmpty ? 0 : 1)
        let base = "R\(row) C\(cell.col + 1)"
        return screens > 1 ? "\(cell.screen + 1)·\(base)" : base
    }

    private func address(_ index: Int) -> String { address(cells.cell(at: index)) }

    // MARK: - Selection

    private func tap(_ cell: PageCells.Cell) {
        let index = cells.index(of: cell)
        // Tapping away from an edit keeps it, as a spreadsheet does; Cancel
        // is there to drop it. One that cannot be made yet (`pony` with no
        // class) stays open with its error instead of being lost.
        if draft != nil {
            guard cell != selected else { keyboardRun = true; return }
            guard commit(thenMove: (0, 0)) else { return }
        }
        if isSelecting {
            // Only what is tapped: the cell the cursor happened to be on
            // when Select began is not part of it.
            if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
            selected = cell
            focusToken += 1
        } else if let entry = cells.entry(at: index, in: tiles), !entry.isSpacer,
                  lookup[entry.key] != nil {
            // A word is inspected, not retyped: its art, class and link are in
            // Tile Settings, whose Edit comes back here to change the word.
            select(cell)
            onProperties(entry.key)
        } else if cell == selected, selection.isEmpty {
            beginEdit(with: nil)
        } else {
            select(cell)
        }
    }

    /// Tile Settings' Edit: the cell's text, ready to change.
    private func editFromSettings() {
        focusToken += 1
        beginEdit(with: nil)
    }

    private func select(_ cell: PageCells.Cell) {
        if draft != nil { cancelEdit() }
        selected = cell
        deselect()
        focusToken += 1
    }

    private func deselect() {
        selection = []
        anchor = nil
        error = nil
        blocked = []
    }

    private func selectAll() {
        selection = Set(tiles.indices.filter { cells.entry(at: $0, in: tiles) != nil })
        anchor = nil
    }

    private func selectClass(_ wordClass: String) {
        selection = Set(tiles.indices.filter {
            guard let entry = cells.entry(at: $0, in: tiles) else { return false }
            return lookup[entry.key]?.wordClass == wordClass
        })
        anchor = nil
    }

    private func move(_ dRow: Int, _ dCol: Int) {
        selected = cells.moving(selected, rowBy: dRow, colBy: dCol, screens: screens)
        deselect()
    }

    /// Shift-arrows: grow the block from where it started to the cursor.
    private func extend(_ dRow: Int, _ dCol: Int) {
        let start = anchor ?? selectedIndex
        selected = cells.moving(selected, rowBy: dRow, colBy: dCol, screens: screens)
        selection = cells.span(from: start, to: selectedIndex)
        anchor = start
        error = nil
    }

    // MARK: - Editing

    private func beginEdit(with text: String?) {
        PerfSignposts.signposter.emitEvent("cell.edit")
        keyboardRun = true
        selection = []
        anchor = nil
        draft = text ?? cellText(selectedIndex)
        error = nil
        highlighted = 0
    }

    private func cancelEdit() {
        draft = nil
        error = nil
    }

    /// The caregiver put the keyboard away: the edit is kept, as a tap away
    /// keeps it. One that cannot be made stays open with its error; a tap on
    /// the bar or the cell brings the keyboard back to finish it.
    private func keyboardLowered() {
        keyboardRun = false
        if draft != nil { commit(thenMove: (0, 0)) }
    }

    /// Commits the draft; on success moves by `thenMove` and returns to the
    /// grid. False when the draft cannot be made and the edit stays open.
    @discardableResult
    private func commit(thenMove: (Int, Int)) -> Bool {
        guard let text = draft else { move(thenMove.0, thenMove.1); return true }
        if text == cellText(selectedIndex) {
            draft = nil
            move(thenMove.0, thenMove.1)
            return true
        }
        switch BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                 scenePages: scene.pages, systemPages: systemPages) {
        case .error(let message):
            error = message
            return false
        case .plan(let plan):
            let old = cells.entry(at: selectedIndex, in: tiles)
            let entry = BoardCell.commit(plan, replacing: old, in: scene,
                                         systemPages: systemPages,
                                         lookup: lookup, context: modelContext)
            apply(cells.setting(entry.isSpacer ? nil : entry, at: selectedIndex, in: tiles))
            draft = nil
            move(thenMove.0, thenMove.1)
            return true
        }
    }

    /// Writes the page in one undoable step, keeping any screens added but
    /// not yet filled on view.
    private func apply(_ updated: [TileEntry]) {
        guard updated != tiles else { return }
        let shown = screens
        tiles = updated
        extraScreens = max(0, shown - cells.screenCount(updated))
        blocked = []
    }

    private func clear(_ indices: Set<Int>) {
        apply(indices.reduce(tiles) { cells.setting(nil, at: $1, in: $0) })
    }

    /// The text names words and pages that exist (or a word being made).
    private func resolvesToExisting(_ text: String) -> Bool {
        if case .plan(let plan) = BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                                   scenePages: scene.pages, systemPages: systemPages) {
            return plan.newPage == nil
        }
        return false
    }

    private func accept(_ suggestion: CellSuggestion) {
        draft = suggestion.applied(to: draft ?? "")
        highlighted = 0
        error = nil
    }

    /// `lookup` plus any word `texts` name that the store has and it lacks.
    ///
    /// The well's New word and Paste List make words and hand their keys
    /// straight back; `lookup` comes from the editor's query and does not have
    /// them until the next render, so they failed as "No word" and never
    /// landed.
    private func lookupIncludingNew(_ texts: [String]) -> [String: TileModel] {
        var result = lookup
        for text in texts {
            guard case .cell(.existing(let name), _) = BoardCell.parse(text) else { continue }
            let key = TileModel.normalizeKey(name)
            guard result[key] == nil else { continue }
            let descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == key })
            if let tile = try? modelContext.fetch(descriptor).first { result[key] = tile }
        }
        return result
    }

    // MARK: - Visibility

    private func setVisibility(concealed: Bool, level: Int?, at indices: Set<Int>? = nil) {
        var next = tiles
        for index in indices ?? targets where cells.entry(at: index, in: next) != nil {
            next[index].isConcealed = concealed
            if let level { next[index].revealLevel = level }
        }
        apply(next)
    }

    // MARK: - Moving and the clipboard

    /// A drop. A cell from this grid moves, with the selection's words when
    /// it is part of it; a word from the well is placed; anything else is text
    /// and pastes. `inserting`: dropped on the cell's leading edge, so it goes
    /// in front and the run shifts into its gap (`PageCells.inserting`).
    ///
    /// **Only words move.** A selection's empty cells came along with a
    /// Shift-arrow block; they carry nothing, and their landing cells must not
    /// block or shape the move.
    private func drop(_ item: String, at target: Int, inserting: Bool) {
        dropTarget = nil
        if item.hasPrefix(Self.textPrefix) {
            place(String(item.dropFirst(Self.textPrefix.count)), at: target, inserting: inserting)
            return
        }
        guard item.hasPrefix(Self.dragPrefix), let source = Int(item.dropFirst(Self.dragPrefix.count)) else {
            paste(item, at: target)
            return
        }
        let picked: Set<Int> = selection.contains(source) ? selection : [source]
        let sources = picked.filter { cells.entry(at: $0, in: tiles) != nil }
        guard !sources.isEmpty else { return }
        if inserting {
            guard !sources.contains(target) else { return }
            let entries = sources.sorted().compactMap { cells.entry(at: $0, in: tiles) }
            finishMove(cells.inserting(entries, before: target, removing: sources, in: tiles), at: target)
            return
        }
        switch cells.moving(sources, anchor: source, to: target, in: tiles) {
        case .success(let moved):
            finishMove(moved, at: target)
        case .failure(.occupied(let cellsInTheWay)):
            blocked = Set(cellsInTheWay)
            error = "Those cells have words in them: "
                + cellsInTheWay.prefix(4).map { address($0) }.joined(separator: ", ")
                + (cellsInTheWay.count > 4 ? "…" : "") + ". Nothing was moved. "
                + "Drop on a cell's left edge to insert in front instead."
        case .failure(.offGrid):
            error = "That would push the selection off the edge of the page. Nothing was moved."
        }
    }

    /// A finished move ends the selection: the next drag starts from what is
    /// under the finger, not from cells chosen for the last one.
    private func finishMove(_ moved: [TileEntry], at target: Int) {
        apply(moved)
        selected = cells.cell(at: target)
        deselect()
        isSelecting = false
        focusToken += 1
    }

    /// Places cell text — a word from the well — at `target`: in front of it
    /// when inserting, else over it.
    private func place(_ text: String, at target: Int, inserting: Bool) {
        switch BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                 scenePages: scene.pages, systemPages: systemPages) {
        case .error(let message):
            error = message
        case .plan(let plan):
            let old = inserting ? nil : cells.entry(at: target, in: tiles)
            let entry = BoardCell.commit(plan, replacing: old, in: scene, systemPages: systemPages,
                                         lookup: lookup, context: modelContext)
            guard !entry.isSpacer else { return }
            apply(inserting ? cells.inserting([entry], before: target, in: tiles)
                            : cells.setting(entry, at: target, in: tiles))
            selected = cells.cell(at: target)
            deselect()
            focusToken += 1
        }
    }

    /// Words from the well go into empty cells from the cursor, in order, as
    /// one undoable step, and the cursor steps past the last one — so tapping
    /// words in turn fills a row. All or nothing: a word that does not
    /// resolve stops the lot and says which.
    private func placeAtCursor(_ texts: [String]) {
        guard draft == nil, !texts.isEmpty else { return }
        let lookup = lookupIncludingNew(texts)
        var plans: [BoardCell.Plan] = []
        for text in texts {
            switch BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                     scenePages: scene.pages, systemPages: systemPages) {
            case .error(let message):
                error = "\(text): \(message). Nothing was placed."
                return
            case .plan(let plan):
                if !plan.entry.isSpacer { plans.append(plan) }
            }
        }
        let entries = plans.map {
            BoardCell.commit($0, replacing: nil, in: scene, systemPages: systemPages,
                             lookup: lookup, context: modelContext)
        }
        let start = selectedIndex
        let placed = cells.placing(entries, intoEmptyFrom: start, in: tiles)
        // The cell after the last one filled: the first index the placing
        // reached past `start` that was empty before.
        var last = start
        var remaining = entries.count
        while remaining > 0 {
            if cells.entry(at: last, in: tiles) == nil { remaining -= 1 }
            last += 1
        }
        apply(placed)
        deselect()
        selected = cells.cell(at: min(last, (screens + 1) * cells.perScreen - 1))
        focusToken += 1
    }

    private func copy(_ indices: Set<Int>) {
        UIPasteboard.general.string = BoardCell.tsv(cells.rectangle(indices).map { row in
            row.map { indices.contains($0) ? cellText($0) : "" }
        })
    }

    private func cut(_ indices: Set<Int>) {
        copy(indices)
        clear(indices)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        paste(text, at: cells.rectangle(targets).first?.first ?? selectedIndex)
    }

    /// Pastes tab-separated cells with their top-left at `target`, as a
    /// spreadsheet does: it writes over what is there. All or nothing — one
    /// cell that does not resolve stops the paste and says which.
    @discardableResult
    private func paste(_ text: String, at target: Int) -> Bool {
        let rows = BoardCell.rows(fromTSV: text)
        var plans: [[BoardCell.Plan?]] = []
        for (r, row) in rows.enumerated() {
            var planned: [BoardCell.Plan?] = []
            for (c, cell) in row.enumerated() {
                switch BoardCell.resolve(BoardCell.parse(cell), lookup: lookup,
                                         scenePages: scene.pages, systemPages: systemPages) {
                case .error(let message):
                    error = "\(address(target + r * cells.cols + c)): \(message). Nothing was pasted."
                    return false
                case .plan(let plan):
                    planned.append(plan.entry.isSpacer ? nil : plan)
                }
            }
            plans.append(planned)
        }
        let entries: [[TileEntry?]] = plans.enumerated().map { r, row in
            row.enumerated().map { c, plan in
                plan.map {
                    BoardCell.commit($0, replacing: cells.entry(at: target + r * cells.cols + c, in: tiles),
                                     in: scene, systemPages: systemPages,
                                     lookup: lookup, context: modelContext)
                }
            }
        }
        let result = cells.pasting(entries, at: target, in: tiles)
        apply(result.tiles)
        selected = cells.cell(at: target)
        // What was pasted stays selected, so it can be dragged on at once.
        let width = min(rows.map(\.count).max() ?? 1, cells.cols - cells.column(target))
        let corner = target + (rows.count - 1) * cells.cols + max(0, width - 1)
        selection = corner == target ? [] : cells.span(from: target, to: corner)
        error = result.dropped > 0
            ? "\(result.dropped) cell\(result.dropped == 1 ? "" : "s") fell off the right edge and were not pasted."
            : nil
        return true
    }

    // MARK: - Keys

    /// One key from the formula bar. Returns false to let the field have it.
    private func key(_ key: CellTextField.Key) -> Bool {
        guard draft != nil else {
            switch key {
            case .up: move(-1, 0)
            case .down: move(1, 0)
            case .left: move(0, -1)
            case .right: move(0, 1)
            case .shiftUp: extend(-1, 0)
            case .shiftDown: extend(1, 0)
            case .shiftLeft: extend(0, -1)
            case .shiftRight: extend(0, 1)
            case .tab: move(0, 1)
            case .backTab: move(0, -1)
            case .enter: beginEdit(with: nil)
            case .escape:
                guard !selection.isEmpty || isSelecting else { return false }
                deselect()
                isSelecting = false
            case .copy: copy(targets)
            case .cut: cut(targets)
            case .paste: paste()
            case .selectAll: selectAll()
            case .find:
                guard wellVisible else { wellVisible = true; wellSearchToken += 1; return true }
                wellSearchToken += 1
            }
            return true
        }
        let count = suggestions.count
        switch key {
        // The strip runs across, so ← and → walk it; ↑ and ↓ do too.
        case .left, .up:
            guard count > 0 else { return false }
            highlighted = max(highlighted - 1, 0)
        case .right, .down:
            guard count > 0 else { return false }
            highlighted = min(highlighted + 1, count - 1)
        case .escape:
            cancelEdit()
            keyboardRun = false
        case .tab:
            if count > 0, highlighted < count,
               suggestions[highlighted].applied(to: draft ?? "") != draft {
                accept(suggestions[highlighted])
            } else {
                commit(thenMove: (0, 1))
            }
        case .backTab:
            commit(thenMove: (0, -1))
        case .enter:
            // A half-typed word or page takes the highlighted suggestion
            // first, so `go > pl` ⏎ opens Places rather than making page "pl".
            // A new page is then an explicit choice: the last suggestion.
            if let text = draft, !resolvesToExisting(text), highlighted < count {
                let suggestion = suggestions[highlighted]
                accept(suggestion)
                // A class fills in and waits: `pony` ⏎ shows `pony, people`
                // for a look before a word is made with the first class offered.
                if suggestion.isWordClass, !text.contains(",") { return true }
            }
            // Across, then on to the next row: a page is filled a row at a time.
            commit(thenMove: (0, 1))
        case .find:
            cancelEdit()
            wellVisible = true
            wellSearchToken += 1
        case .shiftUp, .shiftDown, .shiftLeft, .shiftRight, .copy, .cut, .paste, .selectAll:
            // The field's own text editing has these while a cell is edited.
            return false
        }
        return true
    }
}

/// Makes a filled cell draggable; an empty one (nil payload) is only a target.
private struct DragSource<Preview: View>: ViewModifier {
    let payload: String?
    @ViewBuilder var preview: () -> Preview

    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload) { preview() }
        } else {
            content
        }
    }
}

/// A completion for the cell being typed: a word for the left of `>`, a page
/// for the right.
enum CellSuggestion: Hashable {
    case word(String)
    case page(String, isSystem: Bool)
    case newPage(String)
    /// A class for a word not in the vocabulary: `pony` → `pony, animal`.
    case wordClass(String)

    static let limit = 8

    /// What to suggest for `text`. Nothing for a new word (`word, class`), which
    /// is being made, not found.
    static func suggestions(for text: String, lookup: [String: TileModel],
                            scenePages: [PageSpec], systemPages: [PageSpec]) -> [CellSuggestion] {
        if let arrow = text.firstIndex(of: ">") {
            var query = text[text.index(after: arrow)...].trimmingCharacters(in: .whitespaces)
            var systemOnly = false
            if query.lowercased().hasPrefix(BoardCell.systemMarker) {
                systemOnly = true
                query = String(query.dropFirst(BoardCell.systemMarker.count))
            }
            return pages(matching: query, scenePages: systemOnly ? [] : scenePages,
                         systemPages: systemPages, allowNew: !systemOnly)
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty {
            // `pony, an` — the class being typed.
            let typed = parts[1].lowercased()
            if VocabularyClasses.known(typed)?.isCaregiverSelectable == true { return [] }
            let classes = VocabularyClasses.caregiverSelectable.map(\.name)
            let matching = typed.isEmpty ? classes : classes.filter { $0.hasPrefix(typed) }
                + classes.filter { !$0.hasPrefix(typed) && $0.contains(typed) }
            return matching.map { .wordClass($0) }
        }
        let query = WordFinder.normalize(text)
        guard !query.isEmpty, parts.count == 1 else { return [] }
        let words: [CellSuggestion] = lookup.values
            .filter { PageLink.targetPage(forKey: $0.key) == nil && !$0.isHiddenFromChild }
            .compactMap { tile in WordFinder.rank(of: query, in: tile).map { (tile, $0) } }
            .sorted { ($0.1, $0.0.key.count, $0.0.key) < ($1.1, $1.0.key.count, $1.0.key) }
            .prefix(limit)
            .map { .word($0.0.key) }
        // Not a word yet: the next thing it needs is a class.
        guard BoardCell.existingWord(parts[0], lookup: lookup) == .missing else { return words }
        return words + VocabularyClasses.caregiverSelectable.map { .wordClass($0.name) }
    }

    var isWordClass: Bool {
        if case .wordClass = self { return true }
        return false
    }

    private static func pages(matching query: String, scenePages: [PageSpec],
                              systemPages: [PageSpec], allowNew: Bool) -> [CellSuggestion] {
        let q = WordFinder.normalize(query)
        func matches(_ page: PageSpec) -> Bool {
            q.isEmpty || page.key.contains(BoardCell.pageKey(query))
                || WordFinder.normalize(page.title).contains(q)
        }
        let own = scenePages.filter(matches).map { CellSuggestion.page($0.key, isSystem: false) }
        let system = systemPages.filter(matches).map { CellSuggestion.page($0.key, isSystem: true) }
        var result = Array((own + system).prefix(limit))
        let key = BoardCell.pageKey(query)
        if allowNew, !key.isEmpty, !scenePages.contains(where: { $0.key == key }) {
            result.append(.newPage(key))
        }
        return result
    }

    /// `text` with this suggestion in place of the side being typed.
    func applied(to text: String) -> String {
        let arrow = text.firstIndex(of: ">")
        let lhs = arrow.map { String(text[..<$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        switch self {
        case .word(let key):
            guard let arrow else { return key }
            return key + " " + text[arrow...]
        case .page(let key, let isSystem):
            let page = (isSystem ? BoardCell.systemMarker : "") + key
            return lhs.isEmpty ? "> \(page)" : "\(lhs) > \(page)"
        case .newPage(let key):
            return lhs.isEmpty ? "> \(key)" : "\(lhs) > \(key)"
        case .wordClass(let name):
            let side = arrow.map { String(text[..<$0]) } ?? text
            let word = side.split(separator: ",", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return "\(word), \(name)" + (arrow.map { " " + text[$0...] } ?? "")
        }
    }
}

/// The formula bar's field, and the grid's keyboard.
///
/// UIKit rather than `TextField` because a focused `UITextField` consumes the
/// arrows, Tab and Escape before SwiftUI's `onKeyPress` sees them; key commands
/// that take priority over the system behaviour get them first.
///
/// It takes first responder when it appears and whenever `focusToken`
/// changes, never on every update, so a sheet's own field (Rename) is not
/// fought for.
struct CellTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEditing: Bool
    /// The on-screen keyboard is up. Wider than `isEditing`: it stays up
    /// between edits while the caregiver fills cell after cell.
    var showsKeyboard: Bool
    /// ← and → walk the suggestions instead of moving the caret.
    var arrowsChoose: Bool = false
    var focusToken: Int
    /// Covered by a sheet: not first responder, so its keyboard cannot rise
    /// there. Focus comes back when the sheet goes.
    var isSuspended: Bool = false
    enum Key {
        case up, down, left, right, shiftUp, shiftDown, shiftLeft, shiftRight
        case tab, backTab, escape, enter, copy, cut, paste, selectAll, find
    }
    /// Returns false to let the field have the key (← → move the caret in an edit).
    var onKey: (Key) -> Bool
    /// Typing while not editing: the text that starts the edit.
    var onType: (String) -> Void
    /// Delete while not editing.
    var onClear: () -> Void
    /// A tap on the bar during an edit whose keyboard was put away.
    var onRaise: () -> Void
    /// The caregiver lowered the on-screen keyboard.
    var onLowered: () -> Void

    func makeUIView(context: Context) -> KeyedTextField {
        let field = KeyedTextField()
        field.showsSoftwareKeyboard(showsKeyboard)
        field.placeholder = placeholder
        field.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                           weight: .regular)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .next
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: KeyedTextField, context: Context) {
        context.coordinator.parent = self
        field.onKey = onKey
        field.onRaise = onRaise
        field.onLowered = onLowered
        field.isEditingCell = isEditing && !arrowsChoose
        field.isEditingText = isEditing
        // After the update, for the same reason as resigning below: the swap
        // raises or hides the keyboard, and its notifications set state.
        if field.wantsKeyboard != showsKeyboard {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                let wanted = coordinator.parent.showsKeyboard   // the latest, not this update's
                if field.wantsKeyboard != wanted { field.showsSoftwareKeyboard(wanted) }
            }
        }
        if field.text != text { field.text = text }
        if isSuspended {
            if !field.isSuspended {
                field.isSuspended = true
                context.coordinator.wasSuspended = true
                // Not inside the update: resigning posts the keyboard's
                // notifications synchronously, and state set from them during
                // an update is an AttributeGraph cycle (the editor hung).
                DispatchQueue.main.async {
                    if field.isFirstResponder { field.resignFirstResponder() }
                }
            }
            return
        }
        field.isSuspended = false
        if context.coordinator.wasSuspended || context.coordinator.focusToken != focusToken
            || field.window == nil {
            context.coordinator.wasSuspended = false
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                if !field.isFirstResponder { field.becomeFirstResponder() }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CellTextField
        var focusToken: Int?
        var wasSuspended = false
        init(parent: CellTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            guard !parent.isEditing else { return true }
            if string.isEmpty { parent.onClear() } else { parent.onType(string) }
            return false
        }

        func textField(_ textField: UITextField, editMenuForCharactersIn range: NSRange,
                       suggestedActions: [UIMenuElement]) -> UIMenu? {
            (textField as? KeyedTextField)?.isQuiet == true ? UIMenu(children: []) : nil
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            _ = parent.onKey(.enter)
            return false
        }
    }

    final class KeyedTextField: UITextField, UIGestureRecognizerDelegate {
        var onKey: ((Key) -> Bool)?
        var isEditingCell = false
        /// A cell is being typed: ⌘C ⌘X ⌘V ⌘A and Shift-arrows are the
        /// field's own text editing, not cell commands.
        var isEditingText = false

        /// The field is first responder whenever the grid is on screen, so
        /// the grid hears the arrows. Left alone that holds the on-screen
        /// keyboard up all the time, over most of the page, on an iPad with
        /// no hardware keyboard. An empty input view keeps it down until a
        /// cell is being edited; a hardware keyboard's keys still arrive.
        /// A tap on the bar edits the cell — the touch way in, now that the
        /// field holding focus no longer means a keyboard is showing.
        ///
        /// A recognizer, not `touchesEnded`: the text field's own gestures
        /// cancel the touch more often than not, and the override missed taps.
        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            addGestureRecognizer(tap)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(_:)),
                                                   name: UIResponder.keyboardDidShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
                                                   name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// The tap that starts an edit is not one asking for Select / Paste:
        /// the field was already first responder, so UIKit offers its menu.
        private var quietUntil = Date.distantPast
        var isQuiet: Bool { Date() < quietUntil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if !isEditingText { quietUntil = Date().addingTimeInterval(0.8) }
            super.touchesBegan(touches, with: event)
        }

        @objc private func tapped() {
            if !isFirstResponder { becomeFirstResponder() }
            if !isEditingText {
                quietUntil = Date().addingTimeInterval(0.6)
                _ = onKey?(.enter)
            } else if !wantsKeyboard {
                onRaise?()
            }
        }

        var onRaise: (() -> Void)?
        var onLowered: (() -> Void)?
        /// What `showsSoftwareKeyboard` last asked for.
        private(set) var wantsKeyboard = false
        /// The on-screen keyboard, not a hardware keyboard's shortcut bar.
        private var softKeyboardUp = false

        /// Hidden while still wanted: the caregiver lowered it. Hiding it
        /// ourselves clears `wantsKeyboard` first, so that is not mistaken
        /// for the caregiver's doing.
        @objc private func keyboardWillHide() {
            defer { softKeyboardUp = false }
            // Put away for a sheet, not by the caregiver: the run goes on
            // when the sheet closes.
            guard !isSuspended else { return }
            if wantsKeyboard, softKeyboardUp { onLowered?() }
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            isQuiet ? false : super.canPerformAction(action, withSender: sender)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func showsSoftwareKeyboard(_ show: Bool) {
            wantsKeyboard = show
            inputView = show ? nil : UIView(frame: .zero)
            inputAssistantItem.leadingBarButtonGroups = []
            inputAssistantItem.trailingBarButtonGroups = []
            if isFirstResponder { reloadInputViews() }
            if show, isFirstResponder, keyboardShow == nil {
                keyboardShow = PerfSignposts.signposter.beginInterval("keyboard.show")
            }
        }

        /// From asking for the on-screen keyboard to its being fully up: what
        /// the caregiver waits through after the tap that starts an edit.
        private var keyboardShow: OSSignpostIntervalState?

        @objc private func keyboardDidShow(_ note: Notification) {
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            softKeyboardUp = (frame?.height ?? 0) > 150
            guard let state = keyboardShow else { return }
            PerfSignposts.signposter.endInterval("keyboard.show", state)
            keyboardShow = nil
        }

        /// Under a sheet: refuses focus, including the async grabs queued
        /// before the sheet arrived.
        var isSuspended = false

        override var canBecomeFirstResponder: Bool { !isSuspended && super.canBecomeFirstResponder }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { DispatchQueue.main.async { self.becomeFirstResponder() } }
        }

        override var keyCommands: [UIKeyCommand]? {
            var commands: [(String, UIKeyModifierFlags, Selector)] = [
                (UIKeyCommand.inputUpArrow, [], #selector(up)),
                (UIKeyCommand.inputDownArrow, [], #selector(down)),
                ("\t", [], #selector(tab)),
                ("\t", .shift, #selector(backTab)),
                (UIKeyCommand.inputEscape, [], #selector(escape)),
                ("f", .command, #selector(findInWell)),
            ]
            // In an edit with nothing to choose, ← and → move the caret.
            if !isEditingCell {
                commands += [(UIKeyCommand.inputLeftArrow, UIKeyModifierFlags(), #selector(left)),
                             (UIKeyCommand.inputRightArrow, UIKeyModifierFlags(), #selector(right))]
            }
            if !isEditingText {
                commands += [
                    (UIKeyCommand.inputUpArrow, .shift, #selector(shiftUp)),
                    (UIKeyCommand.inputDownArrow, .shift, #selector(shiftDown)),
                    (UIKeyCommand.inputLeftArrow, .shift, #selector(shiftLeft)),
                    (UIKeyCommand.inputRightArrow, .shift, #selector(shiftRight)),
                    ("c", .command, #selector(copyCells)),
                    ("x", .command, #selector(cutCells)),
                    ("v", .command, #selector(pasteCells)),
                    ("a", .command, #selector(selectAllCells)),
                ]
            }
            return commands.map { input, modifiers, action in
                let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }

        @objc private func up() { _ = onKey?(.up) }
        @objc private func down() { _ = onKey?(.down) }
        @objc private func left() { _ = onKey?(.left) }
        @objc private func right() { _ = onKey?(.right) }
        @objc private func tab() { _ = onKey?(.tab) }
        @objc private func backTab() { _ = onKey?(.backTab) }
        @objc private func escape() { _ = onKey?(.escape) }
        @objc private func shiftUp() { _ = onKey?(.shiftUp) }
        @objc private func shiftDown() { _ = onKey?(.shiftDown) }
        @objc private func shiftLeft() { _ = onKey?(.shiftLeft) }
        @objc private func shiftRight() { _ = onKey?(.shiftRight) }
        @objc private func copyCells() { _ = onKey?(.copy) }
        @objc private func cutCells() { _ = onKey?(.cut) }
        @objc private func pasteCells() { _ = onKey?(.paste) }
        @objc private func selectAllCells() { _ = onKey?(.selectAll) }
        @objc private func findInWell() { _ = onKey?(.find) }
    }
}

/// A cell as a drop target. The leading quarter inserts in front; the rest
/// moves or swaps. A delegate rather than `dropDestination` because the zone
/// has to follow the finger while the drag is over the cell.
private struct CellDropDelegate: DropDelegate {
    let index: Int
    let side: CGFloat
    let onUpdate: (Bool) -> Void
    let onExit: () -> Void
    let onDrop: (String, Bool) -> Void

    private func inserts(_ info: DropInfo) -> Bool { info.location.x < side * 0.25 }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onUpdate(inserts(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { onExit() }

    func performDrop(info: DropInfo) -> Bool {
        let inserting = inserts(info)
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String else { return }
            DispatchQueue.main.async { onDrop(text, inserting) }
        }
        return true
    }
}
