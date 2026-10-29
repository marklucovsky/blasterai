// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ColumnBandsTests.swift
//  claudeBlastTests
//
//  A ten-wide page on a four-wide phone: bands of columns, not re-wrapped rows.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct ColumnBandsTests {

    private func word(_ key: String) -> TileEntry { TileEntry(key: key, link: "", isAudible: true) }

    /// A 10×5 page with cell names "rRcC" (1-based), a blank column 5 and a
    /// folder only in r2c10 — the shape of Places.
    private func splitPage() -> [TileEntry] {
        (0..<50).map { i in
            let r = i / 10 + 1, c = i % 10 + 1
            if c == 5 { return .spacer() }
            if c == 10 { return r == 1 ? word("folder") : .spacer() }
            return word("r\(r)c\(c)")
        }
    }

    private func keys(_ screen: [TileEntry]) -> [String] {
        screen.map { $0.isSpacer ? "·" : $0.key }
    }

    /// Mark 2026-10-28: the phone scrolls 4-wide bands of the iPad page and
    /// skips empty columns, so a split page is its left block, its right block,
    /// then its folders.
    @Test func aSplitPageIsItsBlocksThenItsFolders() {
        let screens = ColumnBands.screens(splitPage(), sourceCols: 10, sourceRows: 5, cols: 4, rows: 5)
        #expect(screens.count == 3)
        #expect(Array(keys(screens[0]).prefix(4)) == ["r1c1", "r1c2", "r1c3", "r1c4"])
        #expect(Array(keys(screens[0]).suffix(4)) == ["r5c1", "r5c2", "r5c3", "r5c4"])
        #expect(Array(keys(screens[1]).prefix(4)) == ["r1c6", "r1c7", "r1c8", "r1c9"])
        // The folder column alone, in its row, padded out to the band's width.
        #expect(keys(screens[2]).prefix(4) == ["folder", "·", "·", "·"])
        #expect(screens.allSatisfy { $0.count == 20 })
    }

    /// Seasons: months three wide, a blank column, then the seasons two wide.
    /// The blank after the months stays in their band, so winter does not
    /// become the months' fourth column; only blanks before a band are skipped
    /// (Mark 2026-10-29).
    @Test func aNarrowClusterKeepsItsTrailingBreak() {
        let page: [TileEntry] = (0..<50).map { i in
            let r = i / 10 + 1, c = i % 10 + 1
            if c <= 3 { return word("m\(r)\(c)") }
            if c == 5 || c == 6 { return word("s\(r)\(c)") }
            if c == 10 && r == 5 { return word("folder") }
            return .spacer()
        }
        let screens = ColumnBands.screens(page, sourceCols: 10, sourceRows: 5, cols: 4, rows: 5)
        #expect(screens.count == 3)
        #expect(Array(keys(screens[0]).prefix(4)) == ["m11", "m12", "m13", "·"])
        #expect(Array(keys(screens[1]).prefix(4)) == ["s15", "s16", "·", "·"])
        #expect(keys(screens[2]).suffix(4) == ["folder", "·", "·", "·"])
    }

    /// A word hidden by the level keeps its column: only spacers are nothing.
    @Test func aConcealedColumnIsKept() {
        var page = splitPage()
        for r in 0..<5 { page[r * 10].isConcealed = true }
        let screens = ColumnBands.screens(page, sourceCols: 10, sourceRows: 5, cols: 4, rows: 5)
        #expect(keys(screens[0]).first == "r1c1")
    }

    /// A page shorter than a screen has no cells past its end to show.
    @Test func aShortPageHasNoEmptyScreens() {
        let page = (0..<7).map { word("w\($0)") }
        let screens = ColumnBands.screens(page, sourceCols: 10, sourceRows: 5, cols: 4, rows: 5)
        #expect(screens.count == 2)
        #expect(Array(keys(screens[1]).prefix(4)) == ["w4", "w5", "w6", "·"])
    }

    /// Only a grid narrower than the scene's is banded; the iPad keeps order.
    @Test func theDesignedGridIsNotBanded() {
        let page = splitPage()
        let screens = ColumnBands.board(page, designed: (10, 6), cols: 10, contentRows: 5, inherits: true)
        #expect(screens.count == 1)
        #expect(screens[0].map(\.key) == page.map(\.key))
        let phone = ColumnBands.board(page, designed: (10, 6), cols: 4, contentRows: 5, inherits: true)
        #expect(phone.count == 3)
    }
}
}
