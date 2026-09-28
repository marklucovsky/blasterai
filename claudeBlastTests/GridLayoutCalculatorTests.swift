// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridLayoutCalculatorTests.swift
//  claudeBlastTests
//

import Testing
import CoreGraphics
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct GridLayoutCalculatorTests {

    /// iPad mini portrait, in points.
    private let miniPortrait = CGSize(width: 744, height: 1133)
    /// iPhone 16e portrait — the narrowest current phone.
    private let phonePortrait = CGSize(width: 393, height: 852)

    private func spec(_ screen: CGSize,
                      step: Int = 0,
                      scale: CGFloat = 1) -> GridLayoutSpec {
        GridLayoutCalculator.compute(screenSize: screen,
                                     geo: CGSize(width: screen.width,
                                                 height: screen.height - 200),
                                     userStep: step,
                                     textScale: scale)
    }

    // MARK: - The label band

    /// The label is a caption for a picture, so it tracks the picture's size.
    ///
    /// Compared with a tolerance because 100 * 0.14 is 14.000000000000002 in
    /// binary floating point, and a test that reads as arithmetic should not
    /// fail on the representation.
    @Test func labelTracksTileWidthWithinItsBand() {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
        #expect(near(GridLayoutCalculator.labelFontSize(forTile: 40), 9))    // floor
        #expect(near(GridLayoutCalculator.labelFontSize(forTile: 100), 14))  // 0.14x
        #expect(near(GridLayoutCalculator.labelFontSize(forTile: 200), 16))  // ceiling
    }

    /// The whole point of the change: a caregiver who turned text up sees
    /// bigger labels on the board, not a board that ignores the setting.
    @Test func labelHonoursTextScale() {
        let normal = GridLayoutCalculator.labelFontSize(forTile: 85)
        let large  = GridLayoutCalculator.labelFontSize(forTile: 85, scale: 2)
        #expect(large > normal)
        #expect(large == normal * 2)
    }

    /// A scale below 1 is not a licence to shrink below the legible band —
    /// the band's floor exists for the child, who is not the one who changed
    /// the setting.
    @Test func textScaleNeverShrinksTheLabel() {
        let normal = GridLayoutCalculator.labelFontSize(forTile: 85)
        #expect(GridLayoutCalculator.labelFontSize(forTile: 85, scale: 0.5) == normal)
    }

    /// Past roughly half the picture's width a label has stopped captioning and
    /// started competing, so the ceiling is relative to the tile.
    @Test func labelCannotOvergrowItsTile() {
        let tiny = GridLayoutCalculator.labelFontSize(forTile: 64, scale: 5)
        #expect(tiny <= 64 * 0.42)
    }

    // MARK: - Flow-through to the grid

    /// Bigger labels mean taller cells, and taller cells mean fewer rows. This
    /// is the response the app owes a caregiver who turned text up: the board
    /// changes, rather than the label being quietly clipped.
    @Test func largerTextYieldsFewerRows() {
        let normal = spec(miniPortrait)
        let large  = spec(miniPortrait, scale: 2.5)
        #expect(large.labelFontSize > normal.labelFontSize)
        #expect(large.rows < normal.rows)
        #expect(large.perPage < normal.perPage)
    }

    /// Only the *rows* give way. Tile size is the one thing the caregiver
    /// dialled in deliberately, so text scale must not quietly override it.
    @Test func textScaleLeavesTileSizeAlone() {
        let normal = spec(miniPortrait)
        let large  = spec(miniPortrait, scale: 2.5)
        #expect(large.tileSize == normal.tileSize)
        #expect(large.cols == normal.cols)
    }

    /// A phone has the least height to give, so it is where this is most
    /// likely to collapse. It must still produce a usable board.
    @Test func phoneStillRendersRowsAtAccessibilitySizes() {
        let large = spec(phonePortrait, scale: 3)
        #expect(large.rows >= 1)
        #expect(large.cols >= 1)
        #expect(large.labelHeight == GridLayoutCalculator.labelHeight(forFont: large.labelFontSize))
    }

    /// Default behaviour is unchanged — the scale parameter defaults to 1, so
    /// every existing call site keeps the layout it had.
    @Test func defaultScaleMatchesExplicitOne() {
        let implicit = GridLayoutCalculator.compute(
            screenSize: miniPortrait,
            geo: CGSize(width: 744, height: 933),
            userStep: 0)
        let explicit = spec(miniPortrait, scale: 1)
        #expect(implicit == explicit)
    }

    // MARK: - Column parity across the iPad sizes

    /// An 11" Pro and a 13" Pro, landscape, with the sentence tray taken off
    /// the top — the geometry the board actually gets.
    private func landscapeBoard(_ screen: CGSize, step: Int = 0) -> GridLayoutSpec {
        GridLayoutCalculator.compute(
            screenSize: screen,
            geo: CGSize(width: max(screen.width, screen.height),
                        height: min(screen.width, screen.height) - 134),
            userStep: step)
    }

    private let iPad11 = CGSize(width: 834, height: 1210)
    private let iPad13 = CGSize(width: 1032, height: 1376)

    /// **The same board should reach the same way on both iPads.**
    ///
    /// Tile position is motor planning: a child learns where a word *is*. When
    /// the 13" laid out 14 columns against the 11"'s 12, every row after the
    /// first held different words on the two devices, and a home page whose
    /// links fill the top row exactly on one wrapped on the other.
    ///
    /// Column parity is the property worth pinning. Row count legitimately
    /// differs — the 13" is taller and shows more of the same board, which is
    /// what a bigger screen should do.
    @Test func bothIPadSizesAgreeOnColumnCount() {
        #expect(landscapeBoard(iPad11).cols == landscapeBoard(iPad13).cols)
    }

    /// The 13" gets there by starting one density tick roomier, not by being
    /// special-cased into a column count. If either base is retuned, the
    /// relationship survives; a hard-coded 12 would not.
    @Test func largeIPadStartsOneTickRoomier() {
        let eleven = landscapeBoard(iPad11).tileSize
        let thirteen = landscapeBoard(iPad13).tileSize
        #expect(thirteen > eleven)
        // 1.12 per tick, with slack for the width-fitting that follows.
        #expect(thirteen / eleven > 1.05)
        #expect(thirteen / eleven < 1.20)
    }

    /// **The mini reaches the same way too.**
    ///
    /// At a base of 88 the mini fit 13 columns at 79pt — 0.4pt inside the
    /// bottom of its acceptance band — and 13×5 out-counted 12×5, so every tile
    /// after the first row sat one place off from the other iPads.
    ///
    /// Rows are pinned as well, because they are what the fix could have cost:
    /// wider tiles are taller cells, and a mini that dropped to four rows would
    /// push the 59-tile home page onto a second screen. Five is what the
    /// simulator measured at 92.
    @Test func miniMatchesTheOtherIPadsColumnCount() {
        let mini = landscapeBoard(miniPortrait)
        #expect(mini.cols == landscapeBoard(iPad11).cols)
        #expect(mini.rows == 5)
    }

    /// The mini's base is still smaller than the 11"'s — parity comes from
    /// tuning it, not from sharing one.
    ///
    /// Compared at *identical* geometry, so the only variable is the device
    /// class. An earlier version of this test handed each device its own
    /// screen and asserted the mini got fewer columns; that failed, and
    /// correctly — given a 1133pt-wide canvas the mini's smaller base fits
    /// *more* columns, not fewer. Column count is a property of the canvas,
    /// and the thing the device class actually decides is tile size.
    @Test func miniKeepsItsOwnSmallerBase() {
        let geo = CGSize(width: 1133, height: 610)
        func tile(_ screen: CGSize) -> CGFloat {
            GridLayoutCalculator.compute(screenSize: screen, geo: geo, userStep: 0).tileSize
        }
        #expect(tile(miniPortrait) < tile(iPad11))
        #expect(tile(iPad11) < tile(iPad13))
    }

    // MARK: - Degenerate geometry

    /// A zero-height proposal happens during transitions. It must not return a
    /// label size that contradicts the scale in force.
    @Test func degenerateGeometryStillScalesItsLabel() {
        let s = GridLayoutCalculator.compute(screenSize: miniPortrait,
                                             geo: .zero,
                                             userStep: 0,
                                             textScale: 2)
        #expect(s.labelFontSize > GridLayoutCalculator.labelFontSize(forTile: 88))
        #expect(s.labelHeight == GridLayoutCalculator.labelHeight(forFont: s.labelFontSize))
    }
}
}
