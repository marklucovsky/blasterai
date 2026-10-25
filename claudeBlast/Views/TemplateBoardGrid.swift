// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TemplateBoardGrid.swift
//  claudeBlast
//
//  A page laid out on the page scheme, drawn on the board's own 12 × 5 grid
//  with Home in cell 0, so a caregiver previewing it sees each word where the
//  child will find it. Shared by the scene and page previews.
//

import SwiftUI

struct TemplateBoardGrid<Cell: View>: View {
    /// Cells 1…n, as `PagePlacer.place` returns them.
    let page: PageSpec
    @ViewBuilder let cell: (TileEntry) -> Cell

    var body: some View {
        let cells = page.tiles + Array(repeating: TileEntry.spacer(),
                                       count: max(0, PageTemplate.cols * PageTemplate.rows - 1
                                                  - page.tiles.count))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                 count: PageTemplate.cols), spacing: 6) {
            Image(systemName: "house.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
            ForEach(Array(cells.enumerated()), id: \.offset) { _, entry in
                if entry.isSpacer {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                } else {
                    cell(entry)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }
}
