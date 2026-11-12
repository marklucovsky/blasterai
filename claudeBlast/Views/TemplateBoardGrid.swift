// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TemplateBoardGrid.swift
//  claudeBlast
//
//  A page laid out on the page scheme, drawn on the board's own 10 × 6 grid
//  with its navigation bar, so a caregiver previewing it sees each word where the
//  child will find it. Shared by the scene and page previews.
//

import SwiftUI

struct TemplateBoardGrid<Cell: View>: View {
    /// The page from r2c1 on, as `PagePlacer.place` returns it.
    let page: PageSpec
    /// The navigation bar drawn over it; BlasterAI 60's when nil.
    var navBar: [TileEntry]? = nil
    /// Where that bar sits.
    var placement: NavBarPlacement = .top
    @ViewBuilder let cell: (TileEntry) -> Cell

    var body: some View {
        let content = PageTemplate.cols * (PageTemplate.rows - 1)
        let bar = BoardChrome.padded(navBar ?? BoardChrome.row(inSystemScene: false), to: PageTemplate.cols)
        let cells = BoardChrome.arrange(
            content: page.tiles + Array(repeating: TileEntry.spacer(), count: max(0, content - page.tiles.count)),
            chrome: bar, placement: placement, perScreen: content)
        // The board's own gaps: the square tiles sit 2pt apart.
        let gap: CGFloat = TileLook.current() == .square ? TileLayout.gap : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap),
                                 count: PageTemplate.cols), spacing: gap) {
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
