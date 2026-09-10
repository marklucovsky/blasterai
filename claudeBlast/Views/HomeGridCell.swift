// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  HomeGridCell.swift
//  claudeBlast
//
//  The Home control, as the first cell of every page of every board.
//

import SwiftUI
import UIKit

/// Home, pinned to grid position 0 on **every** page of every board.
///
/// ## Why it lives in the grid
///
/// Putting navigation in the board is what AAC systems do — TouchChat, LAMP,
/// Proloquo2Go and CoughDrop all place navigation cells among the words. The
/// reason is motor planning: a target that never moves can be learned as a
/// gesture rather than found by reading. LAMP is built entirely on that idea.
///
/// It was previously a chrome button in the tray, which meant it changed size
/// between single-word and sentence mode and competed with the tray for the
/// crowded top strip. As cell 0 it is the same size and the same place on every
/// page, including pages 2, 3 and 4 of a long board — the case that used to
/// scroll Home out of reach entirely.
///
/// ## Why it does not look like a tile
///
/// Every other cell in the grid produces speech. Home does not. Styling it like
/// vocabulary would teach the child that it *is* vocabulary — and the data model
/// already draws this line (`isAudible` / `link`, with `navigation` as its own
/// word class). So it deliberately reads as chrome: no word label, no tile art,
/// a plain glyph on a neutral surface.
///
/// It keeps the **full cell** though. The touch target has to stay as large as
/// every other target on the board; only its meaning is different, not its
/// reachability.
struct HomeGridCell: View {
    /// False when the board is already showing its home page. The cell stays in
    /// place — that is the entire point of a fixed position — but dims and stops
    /// responding to taps, exactly as the old chrome Home button did. A control
    /// that is present but visibly inert reads better than one that vanishes,
    /// and it keeps the grid geometry identical on every page.
    ///
    /// The long-press is **always** live: the caregiver menu has to be reachable
    /// from the home page too, which is where a caregiver most often is.
    let isEnabled: Bool

    /// Tap: back to the board's home page, scrolled to its first display page.
    let action: () -> Void
    /// Long-press: the caregiver menu. Carried over from the old chrome Home
    /// button, which is where caregivers already reach for it.
    let onOpenMenu: () -> Void

    /// Matches the label metrics the surrounding tiles use, so the cell's glyph
    /// scales with the board's density instead of staying a fixed size on a
    /// board of 90 tiles.
    let labelFontSize: CGFloat

    @State private var isPressed = false

    private var glyphSize: CGFloat { max(22, labelFontSize * 2.6) }

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            // Mirrors TileView's structure — a square card with a label beneath
            // — so the square lines up with the tile images across the row.
            // Without the reserved label space the cell centres against the
            // tile's *full* height and hangs visibly low.
            VStack(spacing: 0) {
                // The glyph sits in the square region, where every neighbour's
                // picture sits, so the row of images lines up across the board.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "house.fill")
                            .font(.system(size: glyphSize, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.65))
                    )

                // Empty stand-in for the tile label: reserves the same height so
                // every row aligns, without labelling Home as a word. The
                // padding has to match `TileView`'s label band exactly or Home
                // sits high by twice it — the band is not just a font any more.
                Text(" ")
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GridLayoutCalculator.labelBandPadding)
                    .accessibilityHidden(true)
            }
            // The card covers the label band too, so Home is the same height as
            // the tiles rather than a short square with dead space under it.
            // Its shape and radius are `TileView`'s: Home is chrome, but chrome
            // that is visibly the same *kind of object* as the words around it.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemGray4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(isPressed && isEnabled ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        // Same reason as `TileView`: a zero-distance drag claims the touch
        // before the scroll view can pan. Home sits in the same scrolling grid
        // as every other cell, so it carries the same obligation not to eat the
        // gesture — being one cell, it simply never showed the fault alone.
        .buttonStyle(HomePressButtonStyle(isPressed: $isPressed))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onOpenMenu() }
        )
        .accessibilityLabel("Home")
        .accessibilityHint(isEnabled
                           ? "Goes to the first page of this board"
                           : "Already on the home page")
    }
}

/// Plain button that reports its pressed state outward, so the scale can live
/// on the view rather than inside the style. Mirrors `TileView`'s; both are
/// file-private, which is the only reason there are two.
private struct HomePressButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
