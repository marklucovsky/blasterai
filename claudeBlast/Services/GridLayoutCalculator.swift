// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridLayoutCalculator.swift
//  claudeBlast
//

import CoreGraphics
import Foundation

/// Result of computing a tile-grid layout for a given page in a given geometry.
struct GridLayoutSpec: Equatable {
    /// Rendered width (and height) of one tile's image area, in points.
    /// LazyVGrid will produce tiles at this size when used with the
    /// `cols`-count `.flexible()` columns array.
    let tileSize: CGFloat
    /// Font size for the label below each tile, in points.
    let labelFontSize: CGFloat
    /// Total vertical space the label takes (font + margin), in points.
    let labelHeight: CGFloat
    /// Column count for the grid.
    let cols: Int
    /// Row count that fits on one page at this tile size.
    let rows: Int
    /// Inter-row spacing for LazyVGrid — boosted above the base 6pt to
    /// consume vertical dead space so the grid fills the page.
    let verticalSpacing: CGFloat

    var perPage: Int { cols * rows }
}

/// Pure-Swift calculator that picks a tile size + column count for the tile grid.
///
/// Algorithm:
/// 1. Compute the user's preferred tile size from form factor × stepper tick.
/// 2. Sweep candidate column counts. For each, the rendered tile width is
///    `(availW - (cols-1)*spacing) / cols` and the row count that fits is
///    `floor((availH + spacing) / (cellH + spacing))`.
/// 3. Keep only candidates whose tile width is within ±1 tick (≈12%) of the
///    preferred size — close enough that the user perceives the chosen size
///    as the one they dialed in.
/// 4. Pick the candidate with the highest capacity (cols × rows). Ties go to
///    the candidate closest to preferred size. This "fits the last row"
///    when there is height slack at the user's preferred size.
///
/// The same (cols, rows, tileSize) is used on every page — sparse pages just
/// render with trailing empty space. One size per device/orientation.
enum GridLayoutCalculator {
    // Layout chrome
    private static let hPad: CGFloat = 32   // 16pt side padding × 2
    private static let vPad: CGFloat = 8
    private static let spacing: CGFloat = 6

    // Form-factor base sizes (the "auto" tile size at userStep=0).
    // Device class is detected from the screen's shorter dimension so
    // orientation doesn't change the classification.
    private static let phoneMinDimMax: CGFloat = 600     // < 600pt → phone
    private static let iPadMiniMinDimMax: CGFloat = 800  // 600–800 → iPad mini, ≥800 → larger iPad
    private static let phoneBaseSize: CGFloat = 85
    private static let iPadMiniBaseSize: CGFloat = 88
    private static let iPadBaseSize: CGFloat = 99

    // Hard bounds for tile size in any geometry / tick combination
    private static let minTileSize: CGFloat = 64
    private static let maxTileSize: CGFloat = 160

    /// Per-tick multiplicative step. ±1 tick = ±12% tile size.
    private static let tickMultiplier: Double = 1.12

    /// Maximum extra inter-row spacing added to consume vertical slack.
    private static let maxRowSpacingBoost: CGFloat = 14

    /// - Parameter textScale: the reader's Dynamic Type multiplier, 1.0 at the
    ///   default setting. Passed in rather than read from the environment so
    ///   this stays a pure function; `TileGridView` gets it from
    ///   `UIFontMetrics`, which is the system's own answer rather than a table
    ///   of guesses.
    ///
    ///   The board honours it. A caregiver evaluating this app is often the one
    ///   who turned text up system-wide, and a board that ignored that would be
    ///   telling them what it thinks of their settings. Labels grow, cells grow
    ///   with them, and fewer tiles fit a page — the tile *size* they dialled in
    ///   is preserved, because that is the setting they chose deliberately.
    static func compute(screenSize: CGSize,
                        geo: CGSize,
                        userStep: Int,
                        textScale: CGFloat = 1) -> GridLayoutSpec {
        let screenMin = min(screenSize.width, screenSize.height)
        let base: CGFloat = {
            if screenMin < phoneMinDimMax { return phoneBaseSize }
            if screenMin < iPadMiniMinDimMax { return iPadMiniBaseSize }
            return iPadBaseSize
        }()
        let scaled = CGFloat(Double(base) * pow(tickMultiplier, Double(userStep)))
        let pref = max(minTileSize, min(maxTileSize, scaled))

        let availW = max(0, geo.width - hPad)
        let availH = max(0, geo.height - vPad)

        guard availW > 0 && availH > 0 else {
            return GridLayoutSpec(
                tileSize: pref,
                labelFontSize: labelFontSize(forTile: pref, scale: textScale),
                labelHeight: labelFontSize(forTile: pref, scale: textScale) + 2,
                cols: 1, rows: 1, verticalSpacing: spacing
            )
        }

        // Accept any tile width within one tick of the user's preference —
        // they should perceive the chosen size as "the one they dialed in."
        let minAcceptable = max(minTileSize, pref / CGFloat(tickMultiplier))
        let maxAcceptable = min(maxTileSize, pref * CGFloat(tickMultiplier))

        var best: (cols: Int, rows: Int, tileW: CGFloat, capacity: Int)?

        // Upper bound 30 covers any plausible device width / minTileSize ratio.
        for cols in 1...30 {
            let tileW = renderTile(forCols: cols, availW: availW)
            guard tileW >= minAcceptable && tileW <= maxAcceptable else { continue }

            let cellH = tileW + labelFontSize(forTile: tileW, scale: textScale) + 2
            let rows = max(1, Int((availH + spacing) / (cellH + spacing)))
            let capacity = cols * rows

            let isBetter: Bool
            if let cur = best {
                isBetter = capacity > cur.capacity ||
                    (capacity == cur.capacity && abs(tileW - pref) < abs(cur.tileW - pref))
            } else {
                isBetter = true
            }
            if isBetter { best = (cols, rows, tileW, capacity) }
        }

        // Fallback if no column count landed in the band (very narrow widths):
        // honor the preferred size directly.
        let result: (cols: Int, rows: Int, tileW: CGFloat, capacity: Int) = {
            if let b = best { return b }
            let cols = colsForTile(pref, availW: availW)
            let tileW = renderTile(forCols: cols, availW: availW)
            let cellH = tileW + labelFontSize(forTile: tileW, scale: textScale) + 2
            let rows = max(1, Int((availH + spacing) / (cellH + spacing)))
            return (cols, rows, tileW, cols * rows)
        }()

        let labelF = labelFontSize(forTile: result.tileW, scale: textScale)
        let cellH = result.tileW + labelF + 2

        // Distribute vertical slack as inter-row spacing, capped so gaps
        // don't get loose. Any remaining slack stays at the bottom of the
        // page rather than being absorbed into the grid.
        let usedAtMinSpacing = CGFloat(result.rows) * cellH + CGFloat(result.rows - 1) * spacing
        let slack = max(0, availH - usedAtMinSpacing)
        let extraPerGap = result.rows > 1 ? slack / CGFloat(result.rows - 1) : 0
        let vSpacing = spacing + min(maxRowSpacingBoost, extraPerGap)

        let spec = GridLayoutSpec(
            tileSize: result.tileW,
            labelFontSize: labelF,
            labelHeight: labelF + 2,
            cols: result.cols,
            rows: result.rows,
            verticalSpacing: vSpacing
        )

        #if DEBUG
        print("[GridLayout] screen=\(Int(screenSize.width))×\(Int(screenSize.height)) geo=\(Int(geo.width))×\(Int(geo.height)) step=\(userStep) pref=\(Int(pref)) → tile=\(Int(spec.tileSize)) cols=\(spec.cols) rows=\(spec.rows) cap=\(spec.perPage) vGap=\(Int(spec.verticalSpacing))")
        #endif

        return spec
    }

    // MARK: - Helpers

    private static func colsForTile(_ tile: CGFloat, availW: CGFloat) -> Int {
        max(1, Int((availW + spacing) / (tile + spacing)))
    }

    private static func renderTile(forCols cols: Int, availW: CGFloat) -> CGFloat {
        guard cols > 0 else { return availW }
        return (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
    }

    /// Label font tracks tile width, stays in a legible band, and then honours
    /// the reader's Dynamic Type setting on top of that.
    ///
    /// The ceiling is relative to the tile rather than absolute: a label is a
    /// caption for a picture, and past roughly half the picture's width it has
    /// stopped captioning and started competing. At ordinary tile sizes the
    /// ceiling never binds — an 85pt tile allows 35pt of label, and even the
    /// largest accessibility setting asks for less than that — so it exists to
    /// keep small tiles sane, not to overrule the reader.
    static func labelFontSize(forTile tile: CGFloat, scale: CGFloat = 1) -> CGFloat {
        let base = max(9, min(16, tile * 0.14))
        return min(base * max(1, scale), max(base, tile * 0.42))
    }
}
