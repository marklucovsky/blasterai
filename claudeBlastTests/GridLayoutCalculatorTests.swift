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
