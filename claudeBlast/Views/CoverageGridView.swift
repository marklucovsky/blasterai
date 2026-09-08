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
/// Order therefore matters, and differs by what is being opened. A page carries
/// its own order, which is what the child actually sees. A part of speech has no
/// position on the board at all, so its words are alphabetical and the layout
/// reading above simply does not apply — the grid is then just a legible list.
struct CoverageGridView: View {
    let title: String
    /// In display order. For a page, the page's own order.
    let keys: [String]
    let usedKeys: Set<String>
    /// Whether `keys` carries real board positions, which decides if the layout
    /// is worth reading anything into.
    var isPositional: Bool = true

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    private var lookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 68, maximum: 96), spacing: 8)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        cell(for: key)
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
    ///
    /// Neither line depends on width, because reflow does not: the child's own
    /// board reflows to fill whatever screen it is on. There is no faithful
    /// layout on a big screen and an unfaithful one on a small screen — order
    /// holds everywhere and wrapping is decided everywhere, so saying so once
    /// is both simpler and more accurate than apologising for the phone.
    private var readingNote: String {
        let legend = "Dimmed words have never been pressed."
        return isPositional
            ? legend + " Listed in page order — relative placement is correct, but the ultimate layout reflows to fill available screen real estate."
            : legend + " Listed alphabetically — a part of speech can appear anywhere within a scene."
    }

    @ViewBuilder
    private func cell(for key: String) -> some View {
        let isUsed = usedKeys.contains(key)
        let tile = lookup[key]
        VStack(spacing: 3) {
            ZStack {
                // The word key, not the art key. `TileImageResolver` follows
                // `bundleImage` itself, so an aliased word (`him` → `he`, a page
                // link → `packcover_<slug>`) resolves without the caller knowing.
                TileImageView(key: key, wordClass: tile?.wordClass ?? "")
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        TileColorResolver.color(for: tile).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                if !isUsed {
                    // A scrim rather than `.opacity` on the tile: the veil reads
                    // as something laid OVER a tile that is still there, which is
                    // the point — the word has not gone away, it has gone unused.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground).opacity(0.62))
                }
            }
            Text(tile?.value ?? key)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isUsed ? .primary : .tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile?.value ?? key), \(isUsed ? "used" : "never used")")
    }

    /// What to do about it, once you have looked. A real footnote.
    ///
    /// Phrased as a run of neighbours rather than "a whole row or column",
    /// which is what it used to say. Reflow moves the wrap point, so a row is
    /// not a stable thing to point at — but relative order survives, so a
    /// stretch of adjacent words going untouched still means what it always
    /// meant.
    private var footnote: String {
        let unused = keys.count - keys.filter { usedKeys.contains($0) }.count
        guard unused > 0 else {
            return "Every word here has been used at least once."
        }
        guard isPositional else { return "" }
        return "A run of neighbouring words all dimmed usually means that stretch of the page is hard to reach, rather than the wrong words."
    }
}
