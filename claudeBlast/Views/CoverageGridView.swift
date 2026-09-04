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

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var header: some View {
        let used = keys.filter { usedKeys.contains($0) }.count
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(used) of \(keys.count) used")
                .font(.headline.monospacedDigit())
            Text(keys.isEmpty ? "" : "· \(Int((Double(used) / Double(keys.count) * 100).rounded()))%")
                .foregroundStyle(.secondary)
            Spacer()
        }
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
                        wordClassColor(tile?.wordClass ?? "").opacity(0.12),
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

    private var footnote: String {
        let unused = keys.count - keys.filter { usedKeys.contains($0) }.count
        guard unused > 0 else {
            return "Every word here has been used at least once."
        }
        return isPositional
            ? "Dimmed words have never been pressed, shown where they sit on the page. A whole row or column dimmed usually means the tiles are hard to reach rather than the wrong words."
            : "Dimmed words have never been pressed. These are listed alphabetically — a part of speech has no position on the board, so there is no layout to read into the arrangement."
    }
}
