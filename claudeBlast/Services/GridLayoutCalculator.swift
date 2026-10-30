// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridLayoutCalculator.swift
//  claudeBlast
//

import CoreGraphics
import Foundation
import UIKit

/// Result of computing a tile-grid layout for a given page in a given geometry.
struct GridLayoutSpec: Equatable {
    /// Rendered width (and height) of one tile's image area, in points.
    /// The grid uses `cols` columns `.fixed()` at this width — not flexible,
    /// which would stretch a height-limited tile back to the full width.
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
    /// Space between columns, and the margin at each side of the grid.
    ///
    /// Normally 6 between and 16 at the edges. When the grid is narrower than
    /// the screen — a height-limited layout like the phone's 2×4 — the spare
    /// width is shared equally between the edges and the gaps, so two columns
    /// sit evenly across the screen rather than bunched in the middle with
    /// wide empty margins.
    var horizontalSpacing: CGFloat = 6
    var horizontalPadding: CGFloat = 16
    /// One slot of the control rail (`ControlRail`): a tile wide on the side
    /// rail, and as tall as the bottom one. 0 when there is no rail.
    var railSlot: CGFloat = 0
    /// A bottom rail slot's width: a tile, or less when the slots would not
    /// fit across. Its height (`railSlot`) can be more, to keep a half-height
    /// control a whole touch target.
    var railSlotWidth: CGFloat = 0
    /// A square-look tile's height when it is shorter than `tileSize` wide:
    /// a phone on its side, whose ten columns would otherwise leave a band of
    /// screen either side of a grid bound by its height. Nil: square.
    var tileHeight: CGFloat? = nil

    var perPage: Int { cols * rows }
}

/// Where the control rail sits, which decides what room it takes from the grid.
enum RailPlacement: Equatable {
    case none
    /// iPad landscape: a column one tile wide at the right of the grid.
    case side
    /// iPad portrait and iPhone: a row under the grid of `slots` slots, a tile
    /// wide at most. `pairs` when a slot holds two controls over/under, which
    /// sets a floor on its height (`GridLayoutCalculator.minTarget`).
    case bottom(slots: Int, pairs: Bool = false)
}

/// The three board layouts a device can show, as fixed grids.
///
/// ## Why fixed grids rather than a density slider
///
/// The motor-planning claim — a child learns where a word *is* — only holds if
/// the grid is something a board is designed against. A density computed from
/// tile size gave a different grid on each device and each step: "Roomy" was 11
/// columns on one iPad and 12 on another, and the phone's steps jumped about
/// (4×5 to 2×4 in one tap). A board author could not design for any of it.
///
/// So a layout is a grid, pinned in both directions: Standard is 10×6 on every
/// iPad and 4×6 on every iPhone, with the same positions and the same page
/// breaks. Row 1 is the system row (`BoardChrome`); every other cell is a word
/// or a folder, with the controls on a rail outside the grid. Tile size follows
/// from the screen; spare space becomes margin, never an extra column or row.
///
/// Nothing is denser than Standard. Denser boards were possible and were
/// dropped on purpose: more, smaller pictures over-stimulate, and the grids
/// they produced did not look good on a phone either.
///
/// The grids are defined for the orientation each device is designed around —
/// iPad landscape, iPhone portrait. Turned the other way, the board falls back
/// to sizing tiles to match (see `GridLayoutCalculator.compute`), and makes no
/// motor-planning promise there.
enum BoardLayout: String, CaseIterable, Identifiable {
    case standard, large, largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .large:    return "Large"
        case .largest:  return "Largest"
        }
    }

    /// The grid on a device of this kind, in its designed orientation, with
    /// the system row as its first row. (Mark 2026-10-27: iPad 10×6, and the
    /// larger layouts 8 and 6 wide with four and three rows of words.)
    ///
    /// On a grid narrower than the ten folders, the system row scrolls.
    func grid(phone: Bool) -> (cols: Int, rows: Int) {
        switch (self, phone) {
        case (.standard, false): return (10, 6)
        case (.large, false):    return (8, 5)
        case (.largest, false):  return (6, 4)
        case (.standard, true):  return (4, 6)
        case (.large, true):     return (3, 5)
        case (.largest, true):   return (2, 5)
        }
    }

    /// "iPad 10×4 · iPhone 3×4" — what this layout is on each kind of device.
    var gridsDescription: String {
        let pad = grid(phone: false), phone = grid(phone: true)
        return "iPad \(pad.cols)×\(pad.rows) · iPhone \(phone.cols)×\(phone.rows)"
    }

    /// The setting as stored, falling back to the density stepper it replaced.
    ///
    /// The stepper ran -3…3 around Auto. Everything at or below Auto is
    /// Standard (the denser steps no longer exist), Roomy and Roomier are
    /// Large, Roomiest is Largest.
    static func current(_ defaults: UserDefaults = .standard) -> BoardLayout {
        if let raw = defaults.string(forKey: AppSettingsKey.boardLayout),
           let layout = BoardLayout(rawValue: raw) {
            return layout
        }
        return fromLegacyStep(defaults.integer(forKey: AppSettingsKey.tileSizeStep))
    }

    static func fromLegacyStep(_ step: Int) -> BoardLayout {
        switch step {
        case ...0:  return .standard
        case 1, 2:  return .large
        default:    return .largest
        }
    }
}

/// The grid a scene was designed for: a kind of device and a layout on it.
///
/// A board's word positions are only stable on the grid it was authored
/// against, so a scene can say which one that is — `"ipad-10x6"`, `"phone-2x5"`.
/// One device kind, not one per kind: a 10×6 board cannot keep its positions
/// at 4×5, so "Standard everywhere" would promise something it cannot keep.
///
/// Stored on `BlasterScene.designedFor` as `rawValue`; empty means undeclared.
struct DesignedLayout: Hashable, Identifiable {
    let phone: Bool
    let layout: BoardLayout

    var id: String { rawValue }

    var grid: (cols: Int, rows: Int) { layout.grid(phone: phone) }

    /// `"ipad-10x6"`. Spelled with the grid rather than the layout name so the
    /// file says what it means even if a layout is ever retuned.
    var rawValue: String {
        "\(phone ? "phone" : "ipad")-\(grid.cols)x\(grid.rows)"
    }

    /// `"iPad 10×6"`.
    var title: String {
        "\(phone ? "iPhone" : "iPad") \(grid.cols)×\(grid.rows)"
    }

    init(phone: Bool, layout: BoardLayout) {
        self.phone = phone
        self.layout = layout
    }

    /// Nil for empty or unrecognised — an unknown grid from a newer file is
    /// treated as undeclared rather than guessed at.
    init?(rawValue: String) {
        guard let match = Self.all.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = match
    }

    /// Every declarable grid: the iPad ones, then the iPhone ones.
    static let all: [DesignedLayout] =
        [false, true].flatMap { phone in BoardLayout.allCases.map { DesignedLayout(phone: phone, layout: $0) } }
}

/// Pure-Swift calculator that picks a tile size + column count for the tile grid.
///
/// In a device's designed orientation the grid comes from `BoardLayout` and only
/// the tile size is computed: the largest tile that gives every column and
/// every row. Turned the other way, the board sizes tiles instead:
///
/// Algorithm (other orientation):
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
    /// Between the grid and the control rail: a little more than the tiles'
    /// own gap, so the rail reads as a separate strip of controls.
    static let railGap: CGFloat = 6

    /// The smallest touch target the rail draws, half-height controls included:
    /// Apple's 44pt minimum. A pair of them on the bottom rail is two of these
    /// and a gap tall, even where a tile is shorter — about 38pt halves in iPad
    /// portrait and 29pt on a phone before this floor.
    static let minTarget: CGFloat = 44

    /// Vertical padding above and below the word in its colored label band.
    ///
    /// The label used to sit on the page background under the card, and 2pt of
    /// margin was enough to keep it off the corner. It now sits *on* the tile's
    /// own color, which makes it part of the card rather than a caption beneath
    /// one — and a word touching the edge of a colored band reads as clipped.
    ///
    /// It is public and used by `TileView` because the cell
    /// height computed here and the height those actually draw have to be the
    /// same number. They were the same literal `2` in five places before.
    static let labelBandPadding: CGFloat = 3

    /// Total height of the label band for a given font size: the height the
    /// label's line actually draws, plus its padding.
    ///
    /// It used to be the point size, which is not the height of a line of text
    /// — a 16pt semibold line is about 19pt tall. Every cell drew ~3pt taller
    /// than this said it would. Auto always had slack to hide it; a fixed grid
    /// that fills the height did not, and the phone's 2×4 clipped its bottom row.
    static func labelHeight(forFont font: CGFloat) -> CGFloat {
        UIFont.systemFont(ofSize: font, weight: .semibold).lineHeight.rounded(.up)
            + labelBandPadding * 2
    }

    /// The word's band inside a square tile (`TileLook.square`): its line and
    /// a point either side. Tighter than the classic band, because it is not
    /// under the picture but inside the same square, and every point it takes
    /// comes off the picture.
    static func squareLabelHeight(forFont font: CGFloat) -> CGFloat {
        UIFont.systemFont(ofSize: font, weight: .medium).lineHeight.rounded(.up) + 2
    }

    /// Space between tiles for a look: the square tiles sit 2pt apart, close
    /// enough to read as one board of colour.
    private static func spacing(_ look: TileLook) -> CGFloat {
        look == .square ? TileLayout.gap : spacing
    }

    /// A cell's height for a tile of width `tile`. The square tile carries its
    /// word inside the square; the classic one hangs it underneath.
    private static func cellHeight(_ tile: CGFloat, look: TileLook, textScale: CGFloat) -> CGFloat {
        look == .square
            ? tile
            : tile + labelHeight(forFont: labelFontSize(forTile: tile, scale: textScale))
    }

    // Form-factor base sizes (the "auto" tile size at userStep=0).
    // Device class is detected from the screen's shorter dimension so
    // orientation doesn't change the classification.
    private static let phoneMinDimMax: CGFloat = 600     // < 600pt → phone
    private static let iPadMiniMinDimMax: CGFloat = 800  // 600–800 → iPad mini
    /// ≥ 950pt on the short side → the 12.9"/13" class. An 11" Pro is 834.
    private static let iPadLargeMinDim: CGFloat = 950
    private static let phoneBaseSize: CGFloat = 85

    /// The mini's default, dialled when the grid was 12 wide so it landed on
    /// the 11"'s columns. The designed grid is pinned now; these only size
    /// tiles off the designed orientation.
    ///
    /// At 88 the acceptance band reached down to 78.6pt, and 13 columns fit at
    /// 79pt — inside by 0.4pt. 13×5 out-counted 12×5, so the mini laid out one
    /// column more than every other iPad and every tile after the first row sat
    /// one place off from where a child had learned it. The capacity rule was
    /// never asked whether the answer matched the other devices.
    ///
    /// 92 moves the band's floor to 82.1pt, which excludes 13 columns; 12 lands
    /// at ~86pt and still fits five rows in landscape, so the home page stays on
    /// one screen. Measured on the simulator before and after: 13×5 · 65/pg ·
    /// 79pt became 12×5 · 60/pg · 86pt. `miniMatchesTheOtherIPadsColumnCount`
    /// pins it.
    private static let iPadMiniBaseSize: CGFloat = 92
    private static let iPadBaseSize: CGFloat = 99

    /// The 13" default, and the reason it is not simply `iPadBaseSize`.
    ///
    /// Every iPad ≥ 800pt used to share one base, so the larger screen spent
    /// its extra width on *more columns* rather than bigger tiles: 14 across on
    /// a 13" against 12 on an 11". The board is the same board, so the row a
    /// child learns to reach for moves between devices — and a home page whose
    /// links fill the top row exactly on one iPad wraps on the other.
    ///
    /// Caregivers were already correcting this by hand; a 13" set to "Roomy"
    /// lands on the 11"'s 12 columns. This makes that the default instead of a
    /// discovery.
    ///
    /// The value is `iPadBaseSize * tickMultiplier` — exactly one density tick,
    /// not a fitted constant. The statement is "a 13" starts one step roomier
    /// than an 11"", which stays true if either number is ever retuned.
    ///
    /// The mini keeps its own smaller base, tuned to the same 12 columns.
    /// 11" is the standard both target.
    private static let iPadLargeBaseSize: CGFloat = 111  // 99 × 1.12, rounded

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
    ///
    /// - Parameter rail: room to leave for the control rail. The tile is sized
    ///   for the grid and the rail together, so the rail's slots are tiles.
    static func compute(screenSize: CGSize,
                        geo: CGSize,
                        layout: BoardLayout = .standard,
                        textScale: CGFloat = 1,
                        look: TileLook = .classic,
                        rail: RailPlacement = .none) -> GridLayoutSpec {
        let spacing = Self.spacing(look)
        let screenMin = min(screenSize.width, screenSize.height)
        let base: CGFloat = {
            if screenMin < phoneMinDimMax { return phoneBaseSize }
            if screenMin < iPadMiniMinDimMax { return iPadMiniBaseSize }
            if screenMin >= iPadLargeMinDim { return iPadLargeBaseSize }
            return iPadBaseSize
        }()
        let isPhone = screenMin < phoneMinDimMax
        // A phone on its side with the rail beside the board runs the iPad's
        // grid, scaled down — what other AAC apps do there (Mark 2026-10-29).
        // Every word is where it is on the iPad, so nothing bands or scrolls.
        let isPhoneLandscape = isPhone && rail == .side
        let grid = layout.grid(phone: isPhone && !isPhoneLandscape)
        // Off the designed orientation, a larger layout means larger tiles in
        // proportion: Large on an iPad is 10 columns where Standard is 12.
        let standardCols = BoardLayout.standard.grid(phone: isPhone).cols
        let scaled = base * CGFloat(standardCols) / CGFloat(grid.cols)
        let pref = max(minTileSize, min(maxTileSize, scaled))

        let availW = max(0, geo.width - hPad)
        let availH = max(0, geo.height - vPad)

        guard availW > 0 && availH > 0 else {
            let font = labelFontSize(forTile: pref, scale: textScale)
            return GridLayoutSpec(
                tileSize: pref,
                labelFontSize: font,
                labelHeight: look == .square ? squareLabelHeight(forFont: font) : labelHeight(forFont: font),
                cols: 1, rows: 1, verticalSpacing: spacing
            )
        }

        // The designed orientation: the grid is the layout's, exactly. An iPad
        // keeps its grid turned to portrait too, with the rail moved under it:
        // the words stay in their cells, only smaller (Mark 2026-10-27). A
        // board sized to the window instead had eight columns there, and every
        // word after the first row moved.
        let isDesignedOrientation = isPhoneLandscape
            || (isPhone ? availH > availW : (rail != .none || availW >= availH))
        if isDesignedOrientation {
            var tile = min(maxTileSize,
                           renderTile(forCols: grid.cols, availW: availW, spacing: spacing),
                           largestTile(fittingRows: grid.rows, availH: availH,
                                       textScale: textScale, look: look))
            switch rail {
            case .none:
                break
            case .side:
                // One more column, a little further off.
                tile = min(tile, renderTile(forCols: grid.cols + 1,
                                            availW: availW - (railGap - spacing), spacing: spacing))
            case .bottom(let slots, let pairs):
                tile = min(tile, largestTile(fittingRows: grid.rows,
                                             availH: availH - bottomRail(slots: slots, pairs: pairs, tile: tile,
                                                                         availW: availW) - railGap,
                                             textScale: textScale, look: look))
            }
            // A phone on its side: tiles as wide as the screen allows and as
            // tall as the rows allow, so the board fills it side to side as
            // Avaz's does there (Mark 2026-10-29). Only the square look,
            // whose tile is a band of colour; capped so a word still reads
            // as a tile rather than a strip.
            if isPhoneLandscape, look == .square {
                let wide = min(tile * 1.6, renderTile(forCols: grid.cols + 1,
                                                      availW: availW - (railGap - spacing), spacing: spacing))
                if wide > tile {
                    var spec = finish(cols: grid.cols, rows: grid.rows, tileW: wide,
                                      availH: availH, textScale: textScale,
                                      screenSize: screenSize, geo: geo, layout: layout, look: look, rail: rail)
                    spec.tileHeight = tile
                    return spec
                }
            }
            // A phone upright: the same, so the board runs edge to edge under
            // the tray and the system row instead of standing centred inside
            // them (Mark 2026-10-30). Only on the phone for now.
            if isPhone, !isPhoneLandscape, look == .square, case .bottom = rail {
                let wide = min(tile * 1.6, renderTile(forCols: grid.cols, availW: availW, spacing: spacing))
                if wide > tile {
                    var spec = finish(cols: grid.cols, rows: grid.rows, tileW: wide,
                                      availH: availH, textScale: textScale,
                                      screenSize: screenSize, geo: geo, layout: layout, look: look, rail: rail)
                    spec.tileHeight = tile
                    return spec
                }
            }
            return finish(cols: grid.cols, rows: grid.rows, tileW: tile,
                          availH: availH, textScale: textScale,
                          screenSize: screenSize, geo: geo, layout: layout, look: look, rail: rail)
        }

        // Accept any tile width within one tick of the user's preference —
        // they should perceive the chosen size as "the one they dialed in."
        let minAcceptable = max(minTileSize, pref / CGFloat(tickMultiplier))
        let maxAcceptable = min(maxTileSize, pref * CGFloat(tickMultiplier))

        var best: (cols: Int, rows: Int, tileW: CGFloat, capacity: Int)?

        // Upper bound 30 covers any plausible device width / minTileSize ratio.
        // The rail's room comes out of the height first: off the designed
        // orientation the board sizes tiles, and the rail is one more row.
        func usableH(_ tileW: CGFloat) -> CGFloat {
            if case .bottom(let slots, let pairs) = rail {
                return availH - bottomRail(slots: slots, pairs: pairs, tile: tileW, availW: availW) - railGap
            }
            return availH
        }
        let railW: CGFloat = rail == .side ? 1 : 0

        for cols in 1...30 {
            let tileW = renderTile(forCols: cols + Int(railW), availW: availW - railW * (railGap - spacing),
                                   spacing: spacing)
            guard tileW >= minAcceptable && tileW <= maxAcceptable else { continue }

            let cellH = cellHeight(tileW, look: look, textScale: textScale)
            let rows = max(1, Int((usableH(tileW) + spacing) / (cellH + spacing)))
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
            let cols = max(1, colsForTile(pref, availW: availW, spacing: spacing) - Int(railW))
            let tileW = renderTile(forCols: cols + Int(railW), availW: availW, spacing: spacing)
            let cellH = cellHeight(tileW, look: look, textScale: textScale)
            let rows = max(1, Int((usableH(tileW) + spacing) / (cellH + spacing)))
            return (cols, rows, tileW, cols * rows)
        }()

        // A larger layout takes the column count that keeps tiles at least
        // its size. The capacity rule above is Auto's, and at large sizes it
        // folds Large and Largest onto the same grid.
        if layout != .standard {
            let cols = max(1, colsForTile(pref, availW: availW, spacing: spacing) - Int(railW))
            let tileW = renderTile(forCols: cols + Int(railW), availW: availW, spacing: spacing)
            let cellH = cellHeight(tileW, look: look, textScale: textScale)
            let rows = max(1, Int((usableH(tileW) + spacing) / (cellH + spacing)))
            return finish(cols: cols, rows: rows, tileW: tileW,
                          availH: availH, textScale: textScale,
                          screenSize: screenSize, geo: geo, layout: layout, look: look, rail: rail)
        }
        return finish(cols: result.cols, rows: result.rows, tileW: result.tileW,
                      availH: availH, textScale: textScale,
                      screenSize: screenSize, geo: geo, layout: layout, look: look, rail: rail)
    }

    /// The bottom rail's height: as tall as its slots are wide, and tall
    /// enough for two whole touch targets when a slot holds a pair.
    private static func bottomRail(slots: Int, pairs: Bool, tile: CGFloat, availW: CGFloat) -> CGFloat {
        let width = bottomRailWidth(slots: slots, tile: tile, availW: availW)
        return pairs ? max(width, minTarget * 2 + TileLayout.gap) : width
    }

    /// A bottom rail slot's width: a tile, or narrower when `slots` of them
    /// would not fit across.
    private static func bottomRailWidth(slots: Int, tile: CGFloat, availW: CGFloat) -> CGFloat {
        min(tile, renderTile(forCols: max(1, slots), availW: availW, spacing: TileLayout.gap))
    }

    private static func finish(cols: Int, rows: Int, tileW: CGFloat,
                               availH: CGFloat, textScale: CGFloat,
                               screenSize: CGSize, geo: CGSize,
                               layout: BoardLayout, look: TileLook,
                               rail: RailPlacement = .none,
                               log: Bool = true) -> GridLayoutSpec {
        let spacing = Self.spacing(look)
        let result = (cols: cols, rows: rows, tileW: tileW)
        let availW = max(0, geo.width - hPad)
        let (railSlot, railSlotWidth): (CGFloat, CGFloat) = {
            switch rail {
            case .none: return (0, 0)
            case .side: return (tileW, tileW)
            case .bottom(let slots, let pairs):
                return (bottomRail(slots: slots, pairs: pairs, tile: tileW, availW: availW),
                        bottomRailWidth(slots: slots, tile: tileW, availW: availW))
            }
        }()
        // The grid's own width: the side rail stands beside it.
        let gridWidth = geo.width - (rail == .side ? railSlot + railGap : 0)
        let labelF = labelFontSize(forTile: result.tileW, scale: textScale)
        let cellH = cellHeight(result.tileW, look: look, textScale: textScale)

        // Distribute vertical slack as inter-row spacing, capped so gaps
        // don't get loose. Any remaining slack stays at the bottom of the
        // page rather than being absorbed into the grid.
        //
        // Not for the square look: its tiles are 2pt apart both ways, and a
        // board whose rows drift apart while its columns stay together stops
        // reading as one sheet of colour.
        let usedAtMinSpacing = CGFloat(result.rows) * cellH + CGFloat(result.rows - 1) * spacing
        let slack = max(0, availH - usedAtMinSpacing)
        let extraPerGap = result.rows > 1 && look == .classic ? slack / CGFloat(result.rows - 1) : 0
        let vSpacing = spacing + min(maxRowSpacingBoost, extraPerGap)

        // Spare width, shared equally between the edges and the gaps between
        // columns — but only once every gap would be at least the usual edge
        // margin. A grid that fills the width keeps 16 at the edges, 6 between.
        let even = (gridWidth - CGFloat(result.cols) * result.tileW) / CGFloat(result.cols + 1)
        let isEven = even >= hPad / 2 && rail == .none

        let spec = GridLayoutSpec(
            tileSize: result.tileW,
            labelFontSize: labelF,
            labelHeight: look == .square ? squareLabelHeight(forFont: labelF) : labelHeight(forFont: labelF),
            cols: result.cols,
            rows: result.rows,
            verticalSpacing: vSpacing,
            horizontalSpacing: isEven ? even : spacing,
            horizontalPadding: isEven ? even : hPad / 2,
            railSlot: railSlot,
            railSlotWidth: railSlotWidth
        )

        #if DEBUG
        if log { print("[GridLayout] screen=\(Int(screenSize.width))×\(Int(screenSize.height)) geo=\(Int(geo.width))×\(Int(geo.height)) layout=\(layout.rawValue) look=\(look.rawValue) slack=\(Int(slack)) → tile=\(Int(spec.tileSize)) cols=\(spec.cols) rows=\(spec.rows) cap=\(spec.perPage) vGap=\(Int(spec.verticalSpacing))") }
        #endif

        return spec
    }

    // MARK: - The rail

    /// One slot of the side rail. It spans the grid's height, a slot per row
    /// on a full grid; a large layout has fewer rows than the rail has slots,
    /// so its slots are shorter than a tile there.
    static func sideRailSlot(_ spec: GridLayoutSpec, slots: Int, cellHeight: CGFloat) -> CGSize {
        let height = CGFloat(spec.rows) * cellHeight + CGFloat(spec.rows - 1) * spec.verticalSpacing
        let slot = (height - CGFloat(slots - 1) * spec.verticalSpacing) / CGFloat(max(1, slots))
        return CGSize(width: spec.tileSize, height: min(slot, cellHeight))
    }

    // MARK: - Which grid

    /// Phone or iPad, by the screen's shorter side — the same test `compute`
    /// uses, so the two cannot disagree.
    static func isPhone(screenSize: CGSize) -> Bool {
        min(screenSize.width, screenSize.height) < phoneMinDimMax
    }

    /// The physical screen's size — deliberately not the window's. A Split
    /// View or Slide Over window on an iPad is narrow, but the device is still
    /// an iPad and its board keeps the iPad grid and tile tiers.
    ///
    /// Read through the app's window scene; `UIScreen.main` is deprecated as
    /// of iOS 26. Prefers the foreground scene, so an external display (a
    /// different scene role) never answers for the device itself.
    static var deviceScreenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.size ?? .zero
    }

    /// The layout the live board uses.
    ///
    /// A scene's declared grid wins on the kind of device it was designed for,
    /// unless this device has opted out (`honorSceneLayouts`) — a caregiver may
    /// want Large for a child with low vision whatever the author chose. On the
    /// other kind of device the declaration cannot be honoured and the device's
    /// own layout applies; Admin says so.
    static func liveLayout(designed: DesignedLayout?, isPhone: Bool,
                           deviceLayout: BoardLayout, honorSceneLayouts: Bool) -> BoardLayout {
        if honorSceneLayouts, let designed, designed.phone == isPhone { return designed.layout }
        return deviceLayout
    }

    /// The grid the scene preview and page editor show: the declared one,
    /// whatever device they run on — a phone board can be designed on an iPad.
    /// Undeclared, this device's own layout.
    static func authoringGrid(designed: DesignedLayout?, isPhone: Bool,
                              deviceLayout: BoardLayout) -> (cols: Int, rows: Int) {
        designed?.grid ?? deviceLayout.grid(phone: isPhone)
    }

    /// A given grid fitted into the space a view has, for the scene preview and
    /// page editor. `fitHeight: false` sizes by width only, for a view that
    /// scrolls vertically.
    static func compute(geo: CGSize, grid: (cols: Int, rows: Int),
                        fitHeight: Bool = true, textScale: CGFloat = 1,
                        look: TileLook = .classic) -> GridLayoutSpec {
        let availW = max(1, geo.width - hPad)
        let availH = max(1, geo.height - vPad)
        var tile = min(maxTileSize, renderTile(forCols: grid.cols, availW: availW, spacing: spacing(look)))
        if fitHeight {
            tile = min(tile, largestTile(fittingRows: grid.rows, availH: availH, textScale: textScale, look: look))
        }
        return finish(cols: grid.cols, rows: grid.rows, tileW: max(1, tile),
                      availH: fitHeight ? availH : .greatestFiniteMagnitude, textScale: textScale,
                      screenSize: geo, geo: geo, layout: .standard, look: look, log: false)
    }

    // MARK: - Helpers

    /// The largest tile whose cells stack `rows` deep in `availH`. Cell height
    /// is not linear in tile size (the label tracks the tile, within bounds),
    /// so this searches rather than solves.
    private static func largestTile(fittingRows rows: Int, availH: CGFloat,
                                    textScale: CGFloat, look: TileLook) -> CGFloat {
        let spacing = Self.spacing(look)
        func fits(_ t: CGFloat) -> Bool {
            let cell = cellHeight(t, look: look, textScale: textScale)
            return CGFloat(rows) * cell + CGFloat(rows - 1) * spacing <= availH
        }
        var lo: CGFloat = 1, hi: CGFloat = max(1, availH)
        guard fits(lo) else { return lo }
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if fits(mid) { lo = mid } else { hi = mid }
        }
        return lo
    }

    private static func colsForTile(_ tile: CGFloat, availW: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int((availW + spacing) / (tile + spacing)))
    }

    private static func renderTile(forCols cols: Int, availW: CGFloat, spacing: CGFloat) -> CGFloat {
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
