// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A page laid out for a wider grid, cut into screens for a narrower one.
///
/// BlasterAI 60's pages are laid out ten wide, as two blocks of four either
/// side of an empty column 5 with the folders in columns 9–10 (Mark
/// 2026-10-27). Chunking that list four at a time on a phone scrambled every
/// row: a phone row took the end of one iPad row and the start of the next.
/// Cut it into bands of columns instead, and each phone screen is a block of
/// the iPad page as it was designed — rows still rows, clusters still
/// clusters — and the screens run band by band, left to right (Mark
/// 2026-10-28). A blank column where a band would start (the gap after a
/// four-wide cluster, an empty folder column) is skipped, so it costs no
/// screen; a blank inside a band is kept, so a narrower cluster keeps its
/// trailing break and the next cluster starts its own band.
///
/// Only spacers and cells past the end of the page count as nothing. A word
/// hidden by the board's level keeps its column, as it keeps its cell
/// everywhere else, so a phone screen does not change shape as the child's
/// level goes up.
enum ColumnBands {
    /// The child board's screens: bands of the designed page when this grid is
    /// narrower than the one the scene was laid out for, else the page in
    /// order, `perScreen` at a time.
    static func board(_ tiles: [TileEntry], designed: (cols: Int, rows: Int)?,
                      cols: Int, contentRows: Int, inherits: Bool) -> [[TileEntry]] {
        guard !tiles.isEmpty else { return [[]] }
        if let designed, designed.cols > cols {
            return screens(tiles, sourceCols: designed.cols,
                           sourceRows: max(1, designed.rows - (inherits ? 1 : 0)),
                           cols: cols, rows: contentRows)
        }
        return tiles.chunked(into: max(1, cols * contentRows))
    }

    /// Screens of `cols × rows` cells, row-major, cut from `tiles` laid out
    /// `sourceCols × sourceRows` to a screen. Each source screen is cut on its
    /// own. Short bands and windows are padded with spacers so every word sits
    /// at the reach its band gives it.
    static func screens(_ tiles: [TileEntry], sourceCols: Int, sourceRows: Int,
                        cols: Int, rows: Int) -> [[TileEntry]] {
        guard sourceCols > 0, sourceRows > 0, cols > 0, rows > 0 else { return [tiles] }
        let perSource = sourceCols * sourceRows
        var out: [[TileEntry]] = []
        for start in stride(from: 0, to: tiles.count, by: perSource) {
            let screen = Array(tiles[start..<min(start + perSource, tiles.count)])
            func at(_ r: Int, _ c: Int) -> TileEntry? {
                let i = r * sourceCols + c
                return i < screen.count ? screen[i] : nil
            }
            let isBlank = { (c: Int) in
                !(0..<sourceRows).contains { r in at(r, c).map { !$0.isSpacer } ?? false }
            }
            // A band starts at its first column with something in it and runs
            // `cols` columns from there, blank ones included: only the blanks
            // before a band are skipped. Collapsing every blank column pulled
            // the next cluster into a short one's gap — Seasons' three months
            // took winter as their fourth column (Mark 2026-10-29).
            var bands: [[Int]] = []
            var c = 0
            while c < sourceCols {
                if isBlank(c) { c += 1; continue }
                bands.append(Array(c..<min(c + cols, sourceCols)))
                c += cols
            }
            for band in bands {
                for top in stride(from: 0, to: sourceRows, by: rows) {
                    var cells: [TileEntry] = []
                    for r in top..<(top + rows) {
                        for j in 0..<cols {
                            let entry = j < band.count && r < sourceRows ? at(r, band[j]) : nil
                            cells.append(entry ?? .spacer())
                        }
                    }
                    if cells.contains(where: { !$0.isSpacer }) { out.append(cells) }
                }
            }
        }
        return out.isEmpty ? [[]] : out
    }
}
