// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridLayoutCalculatorTests.swift
//  claudeBlastTests
//

import Testing
import CoreGraphics
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct GridLayoutCalculatorTests {

    /// iPad mini portrait, in points.
    private let miniPortrait = CGSize(width: 744, height: 1133)
    /// iPhone 16e portrait — the narrowest current phone.
    private let phonePortrait = CGSize(width: 393, height: 852)

    private func spec(_ screen: CGSize,
                      layout: BoardLayout = .standard,
                      scale: CGFloat = 1) -> GridLayoutSpec {
        GridLayoutCalculator.compute(screenSize: screen,
                                     geo: CGSize(width: screen.width,
                                                 height: screen.height - 200),
                                     layout: layout,
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
            geo: CGSize(width: 744, height: 933))
        let explicit = spec(miniPortrait, scale: 1)
        #expect(implicit == explicit)
    }

    // MARK: - Column parity across the iPad sizes

    /// An 11" Pro and a 13" Pro, landscape, with the sentence tray taken off
    /// the top — the geometry the board actually gets.
    private func landscapeBoard(_ screen: CGSize,
                                layout: BoardLayout = .standard) -> GridLayoutSpec {
        GridLayoutCalculator.compute(
            screenSize: screen,
            geo: CGSize(width: max(screen.width, screen.height),
                        height: min(screen.width, screen.height) - 134),
            layout: layout)
    }

    /// An iPhone 17 board, portrait, as measured on the simulator.
    private func iPhone17Board(_ layout: BoardLayout = .standard) -> GridLayoutSpec {
        GridLayoutCalculator.compute(screenSize: CGSize(width: 402, height: 874),
                                     geo: CGSize(width: 402, height: 674),
                                     layout: layout)
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
    /// Rows are pinned too. The 13" could fit a sixth row, and used to show
    /// one — which moved every page break, so word 61 was on page 1 of one iPad
    /// and page 2 of the other. Its extra height is now spacing.
    @Test func bothIPadSizesAgreeOnColumnCount() {
        #expect(landscapeBoard(iPad11).cols == landscapeBoard(iPad13).cols)
        #expect(landscapeBoard(iPad11).rows == landscapeBoard(iPad13).rows)
    }

    /// The bigger screen's room goes into bigger tiles, not more of them.
    @Test func largeIPadGetsBiggerTilesNotMoreOfThem() {
        let eleven = landscapeBoard(iPad11).tileSize
        let thirteen = landscapeBoard(iPad13).tileSize
        #expect(thirteen > eleven)
        #expect(thirteen / eleven < 1.25)
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

    /// The per-device base sizes still matter off the designed orientation,
    /// where the board sizes tiles rather than pinning a grid.
    ///
    /// Compared at *identical* geometry, so the only variable is the device
    /// class. A portrait canvas, because in landscape every iPad now pins the
    /// same 12 columns and the base no longer enters into it.
    @Test func miniKeepsItsOwnSmallerBase() {
        let geo = CGSize(width: 744, height: 1000)
        func tile(_ screen: CGSize) -> CGFloat {
            GridLayoutCalculator.compute(screenSize: screen, geo: geo).tileSize
        }
        #expect(tile(miniPortrait) < tile(iPad11))
        #expect(tile(iPad11) < tile(iPad13))
    }

    // MARK: - Board layouts

    /// The whole point: a layout is the same grid on every device of a kind.
    @Test func everyLayoutIsExactOnEveryDevice() {
        for layout in BoardLayout.allCases {
            let pad = layout.grid(phone: false), phone = layout.grid(phone: true)
            for board in [landscapeBoard(miniPortrait, layout: layout),
                          landscapeBoard(iPad11, layout: layout),
                          landscapeBoard(iPad13, layout: layout)] {
                #expect(board.cols == pad.cols && board.rows == pad.rows,
                        "\(layout): \(board.cols)×\(board.rows)")
            }
            for board in [spec(phonePortrait, layout: layout), iPhone17Board(layout)] {
                #expect(board.cols == phone.cols && board.rows == phone.rows,
                        "\(layout): \(board.cols)×\(board.rows)")
            }
        }
    }

    /// Mark's choice of grids, pinned so a retune is deliberate.
    @Test func theGridsAreTheChosenOnes() {
        #expect(BoardLayout.allCases.map { $0.gridsDescription } == [
            "iPad 12×5 · iPhone 4×5",
            "iPad 10×4 · iPhone 3×4",
            "iPad 9×4 · iPhone 2×4",
        ])
    }

    @Test func largerLayoutsMakeBiggerTiles() {
        for board in [{ (l: BoardLayout) in self.landscapeBoard(self.iPad11, layout: l) },
                      { (l: BoardLayout) in self.iPhone17Board(l) }] {
            let sizes = BoardLayout.allCases.map { board($0).tileSize }
            #expect(sizes == sizes.sorted() && Set(sizes).count == sizes.count, "\(sizes)")
        }
    }

    /// Off the designed orientation the board sizes tiles, and a larger layout
    /// still means larger tiles.
    @Test func otherOrientationStillScalesWithLayout() {
        let sizes = BoardLayout.allCases.map { spec(miniPortrait, layout: $0).tileSize }
        #expect(sizes == sizes.sorted() && Set(sizes).count == sizes.count, "\(sizes)")
    }

    /// The stepper this replaced: Auto and everything denser become Standard,
    /// Roomy and Roomier Large, Roomiest Largest.
    @Test func legacyDensityStepsMapOnce() {
        #expect((-3...0).map(BoardLayout.fromLegacyStep) == [.standard, .standard, .standard, .standard])
        #expect(BoardLayout.fromLegacyStep(1) == .large)
        #expect(BoardLayout.fromLegacyStep(2) == .large)
        #expect(BoardLayout.fromLegacyStep(3) == .largest)
    }

    @Test func aChosenLayoutWinsOverTheLegacyStep() {
        let suite = "GridLayoutCalculatorTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        #expect(BoardLayout.current(d) == .standard)
        d.set(3, forKey: AppSettingsKey.tileSizeStep)
        #expect(BoardLayout.current(d) == .largest)
        d.set(BoardLayout.large.rawValue, forKey: AppSettingsKey.boardLayout)
        #expect(BoardLayout.current(d) == .large)
    }

    // MARK: - Home over Back

    /// When Back shares Home's cell, each half must still be a reasonable
    /// target. 44pt is Apple's minimum, and every layout on every device
    /// clears it — Standard is the densest there is.
    @Test func splitHomeCellHalvesClearTheTouchMinimum() {
        for l in BoardLayout.allCases {
            let boards = [landscapeBoard(miniPortrait, layout: l), landscapeBoard(iPad11, layout: l),
                          landscapeBoard(iPad13, layout: l), spec(phonePortrait, layout: l),
                          iPhone17Board(l)]
            for board in boards {
                let cell = board.tileSize + board.labelHeight
                #expect(HomeGridCell.halfHeight(cellHeight: cell) >= 44,
                        "\(l): \(board.cols)×\(board.rows) at \(Int(board.tileSize))pt")
            }
        }
    }

    // MARK: - Degenerate geometry

    /// A zero-height proposal happens during transitions. It must not return a
    /// label size that contradicts the scale in force.
    @Test func degenerateGeometryStillScalesItsLabel() {
        let s = GridLayoutCalculator.compute(screenSize: miniPortrait,
                                             geo: .zero,
                                             textScale: 2)
        #expect(s.labelFontSize > GridLayoutCalculator.labelFontSize(forTile: 88))
        #expect(s.labelHeight == GridLayoutCalculator.labelHeight(forFont: s.labelFontSize))
    }
}
}
