// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoverageGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// The words behind one coverage row, laid out as tiles — reached ones bright,
/// untouched ones dimmed in place.
///
/// ## Why the untouched tiles keep their space
///
/// Hiding them, or listing only the unused ones, would answer "which words" and
/// lose "where". Left in position and dimmed, the shape of the neglect becomes
/// visible: an untouched bottom row or right-hand column is a *reaching*
/// problem, and a scatter of gaps is a vocabulary one. Those want opposite
/// responses — move the tiles, or change them — and no percentage distinguishes
/// them.
///
/// ## A page is drawn on the board's own grid
///
/// A page is laid out exactly as the board lays it out: the scene's designed
/// grid (10 × 6 on BlasterAI 60), the system row on top, spacers and concealed cells
/// holding their places, broken into screens where the board breaks it. It used
/// to reflow the words to fit, which kept their order but not their places —
/// and on a fixed grid a place is the thing a child learns. A dimmed corner
/// should be the corner.
///
/// A part of speech has no position on the board at all, so its words are
/// alphabetical and the layout reading simply does not apply — the grid is
/// then just a legible list.
struct CoverageGridView: View {
    let title: String
    /// In display order. For a page, its pressable cells in page order.
    let keys: [String]
    let usedKeys: Set<String>
    /// The page as the board draws it. Nil for a part of speech.
    var board: Board? = nil

    /// One page's cells and the grid they are drawn on.
    struct Board {
        /// Every cell in page order, spacers and concealed cells included.
        let entries: [TileEntry]
        let grid: (cols: Int, rows: Int)
        /// The system row over every screen; empty when the scene has none.
        var chrome: [TileEntry] = []
    }

    private var isPositional: Bool { board != nil }

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    private var lookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The board's own width, so a word is about the size it is on the board.
    /// A phone cannot fit ten readable tiles, so there it is as many as fit.
    private var columns: [GridItem] {
        sizeClass == .compact
            ? [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 4)]
            : Array(repeating: GridItem(.flexible(), spacing: 4), count: PageTemplate.cols)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let board {
                    boardScreens(board)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(keys, id: \.self) { key in
                            cell(for: key)
                        }
                    }
                }

                if !footnote.isEmpty {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var header: some View {
        let used = keys.filter { usedKeys.contains($0) }.count
        // Split by function, not by length.
        //
        // Whatever governs *how to read* the grid has to arrive before it. On a
        // long page the note underneath is a scroll away, so a caregiver forms a
        // reading, reaches the caveat, and has to unform it — and the caveat
        // most worth having is precisely the one that says the arrangement means
        // less than it looks like it does.
        //
        // What stays below is the part you act on after looking, which is a
        // genuine footnote. See `footnote`.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(used) of \(keys.count) used")
                    .font(.headline.monospacedDigit())
                Text(keys.isEmpty ? "" : "· \(Int((Double(used) / Double(keys.count) * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(readingNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// How to read the grid. Above it, always.
    private var readingNote: String {
        if let board {
            return "Dimmed tiles have never been pressed on this page, folders included. Drawn on the board's own \(board.grid.cols) × \(board.grid.rows) grid, with Home in the corner."
        }
        return "Dimmed words have never been pressed. Listed alphabetically — a part of speech can appear anywhere within a scene."
    }

    // MARK: - Board layout

    /// The cells the board would draw: retired and unreviewed words, spacers
    /// and concealed cells all keep their place, empty. Same rule as the board.
    private func drawn(_ board: Board) -> [TileEntry] {
        TileEntry.holdingHiddenCells(board.entries) { lookup[$0]?.isHiddenFromChild == true }
    }

    @ViewBuilder
    private func boardScreens(_ board: Board) -> some View {
        // Row 1 of every screen is the system row, as on the board.
        let perScreen = max(1, board.grid.cols * board.grid.rows - (board.chrome.isEmpty ? 0 : board.grid.cols))
        let screens = drawn(board).chunked(into: perScreen)
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4),
                                count: board.grid.cols)
        ForEach(Array(screens.enumerated()), id: \.offset) { index, cells in
            VStack(alignment: .leading, spacing: 6) {
                if screens.count > 1 {
                    Text("Screen \(index + 1) of \(screens.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(Array(board.chrome.prefix(board.grid.cols).enumerated()), id: \.offset) { _, entry in
                        boardCell(entry)
                            .allowsHitTesting(false)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, entry in
                        boardCell(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func boardCell(_ entry: TileEntry) -> some View {
        if entry.isEmptyCell {
            Color.clear.aspectRatio(1, contentMode: .fit)
        } else {
            styledTile(entry, isUsed: usedKeys.contains(entry.key))
        }
    }

    /// One tile drawn the way the board draws it. Shared by both layouts: a
    /// part of speech has no place on the board, but its words still have their
    /// colours, and the label reads far better in its band than as grey text.
    @ViewBuilder
    private func styledTile(_ entry: TileEntry, isUsed: Bool) -> some View {
        let tile = lookup[entry.key]
        let isLink = !entry.link.isEmpty
        let accent = isLink
            ? TileColorResolver.linkColor(slotRawValue: entry.linkColor, isAudible: entry.isAudible)
            : TileColorResolver.color(for: tile)
        // Drawn the way the board draws it — art on white, the word in a
        // band of its Fitzgerald color, folders badged — because that is the
        // picture a caregiver and an SLP already carry of the board. The
        // scrim lies over the whole tile, colour included, so an unpressed
        // cell still reads as *that* cell, only quieter.
        ZStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    TileImageView(key: tile?.bundleImage ?? entry.key,
                                  wordClass: tile?.wordClass ?? "")
                        .padding(1)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                    if isLink {
                        let badge = TileColorResolver.marker(on: accent)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 8))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(TileColorResolver.label(on: badge), badge)
                            .padding(2)
                    }
                }
                Text(tile?.displayName ?? entry.key)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(TileColorResolver.label(on: accent))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
            }
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if !isUsed {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemBackground).opacity(0.62))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile?.displayName ?? entry.key)\(isLink ? ", folder" : ""), \(isUsed ? "used" : "never used")")
    }

    private func cell(for key: String) -> some View {
        styledTile(TileEntry(key: key), isUsed: usedKeys.contains(key))
    }

    /// What to do about it, once you have looked. A real footnote.
    ///
    /// Rows and corners are real again: the grid is the board's, not a reflow.
    private var footnote: String {
        let unused = keys.count - keys.filter { usedKeys.contains($0) }.count
        guard unused > 0 else {
            return isPositional
                ? "Every tile here has been used at least once."
                : "Every word here has been used at least once."
        }
        guard isPositional else { return "" }
        return "A dimmed row, column or corner usually means that part of the page is hard to reach, rather than the wrong words. A dimmed folder is a page nobody opens from here."
    }
}
