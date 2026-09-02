// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardPDFRenderer.swift
//  claudeBlast
//
//  A board, printed. Paper AAC is a parallel rendering of the same vocabulary,
//  not a fallback for when the tech isn't available — both practitioners we have
//  contact with deliver laminated paper alongside every electronic deployment.
//  See docs/localization-impact.md §8.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Naming

/// A page key is a lowercase identifier (`play_activities`); a person reading a
/// printed sheet needs "Play Activities". Several call sites already do this
/// inline — this is the version print and pack export share.
enum PageNaming {
    static func displayName(_ pageKey: String) -> String {
        pageKey.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Paper

/// Sizes in points (72/inch), stated portrait. Both are offered because a
/// meaningful share of users are outside the US, and A4 changes every number in
/// the layout.
struct PaperSize: Equatable, Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Portrait dimensions. Callers use `size(in:)`; nothing assumes an orientation.
    let portraitSize: CGSize

    static let usLetter = PaperSize(id: "us_letter", displayName: "US Letter",
                                    portraitSize: CGSize(width: 612, height: 792))
    static let a4 = PaperSize(id: "a4", displayName: "A4",
                              portraitSize: CGSize(width: 595, height: 842))

    static let all: [PaperSize] = [.usLetter, .a4]

    func size(in orientation: PrintOrientation) -> CGSize {
        switch orientation {
        case .portrait: return portraitSize
        case .landscape: return CGSize(width: portraitSize.height, height: portraitSize.width)
        }
    }
}

/// Which way up the sheet prints.
///
/// **An explicit choice, never the device's orientation.** A PDF is a document,
/// not a screen: taking its shape from how the caregiver happened to be holding
/// the iPad would make the same board export differently on two runs, and would
/// surprise anyone who exported one-handed on a phone.
enum PrintOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }
}

// MARK: - Options

/// Which tiles print. Empty/false everywhere means "everything on the page".
struct BoardPrintFilter: Equatable {
    /// Only these word classes. Empty means all.
    var wordClasses: Set<String> = []
    /// Only tiles that speak when tapped — drops navigation chrome.
    var audibleOnly = false
    /// Only caregiver-authored words.
    var customOnly = false

    var isActive: Bool { !wordClasses.isEmpty || audibleOnly || customOnly }
}

struct BoardPrintOptions: Equatable {
    var paper: PaperSize = .usLetter
    var orientation: PrintOrientation = .portrait
    /// The density knob. Rows are derived, never set: fixing columns and letting
    /// rows fall out of the paper height keeps tiles square on every paper size
    /// and orientation, without a second control that can contradict the first.
    ///
    /// Zero means "whatever suits this sheet" — see `defaultColumns`. A caregiver
    /// who has not touched the stepper gets a sensible grid whichever way the
    /// paper turns.
    var columns: Int = 0
    /// Dashed guides around every cell, for scissors. The PECS case is this plus
    /// a low density — a setting, not a separate layout.
    var cutLines = false
    var filter = BoardPrintFilter()

    /// A tile larger than this outruns the 512 px source art and visibly softens.
    static let maxTileInches: CGFloat = 3.0
    /// The smallest cell the automatic default will choose.
    ///
    /// Calibrated against a commercial laminated core board, which runs **nine
    /// cells across a landscape sheet** — about 1.05" each, 63 to a page. An
    /// earlier 1.5" floor here was guesswork and put that density out of reach
    /// entirely; a core board is meant to be dense, because its whole value is
    /// having the vocabulary in front of the child at once.
    ///
    /// Small is not the same as soft: at 1" a tile still prints near 500 DPI
    /// from 512 px art. Only *large* tiles outrun the source.
    static let minTileInches: CGFloat = 1.0
    static let maxColumns = 14

    /// The fewest columns that still keep a tile under `maxTileInches`.
    ///
    /// **Derived, not a constant.** Landscape US Letter is 10 inches wide, where
    /// three columns yields 3.3-inch tiles — past the very limit this floor
    /// exists to enforce. A hardcoded 3 is right for portrait Letter by
    /// coincidence and wrong the moment the sheet turns or the paper changes.
    var minColumns: Int {
        SheetLayout.fewestColumns(fitting: Self.maxTileInches,
                                  paper: paper, orientation: orientation)
    }

    /// The densest grid still above `minTileInches` — the core-board end of the
    /// range.
    var maxUsefulColumns: Int {
        let usable = (minColumns...Self.maxColumns).filter { columns in
            SheetLayout.cellWidth(columns: columns, paper: paper, orientation: orientation)
                >= Self.minTileInches * 72
        }
        return usable.last ?? minColumns
    }

    /// The default, given how many tiles the board's biggest page actually holds.
    ///
    /// **Density should answer to the content, not only the paper.** A page of
    /// fourteen words printed at core-board density is fourteen stamps in the
    /// corner of a mostly blank sheet; the same density is exactly right for a
    /// hundred-word `describe` page. So the default is the *largest* tile that
    /// still gets the biggest page onto one sheet, and only when nothing does
    /// does it fall back to the densest usable grid.
    ///
    /// Rows make this non-obvious: they change in steps, so a slightly smaller
    /// tile can buy a whole extra row.
    func defaultColumns(fittingLargestPage tileCount: Int) -> Int {
        let range = minColumns...max(minColumns, maxUsefulColumns)
        if tileCount > 0 {
            for columns in range {
                let layout = SheetLayout.compute(paper: paper, orientation: orientation,
                                                 columns: columns)
                if layout.perSheet >= tileCount { return columns }
            }
        }
        return range.upperBound
    }

    /// Paper-only fallback for callers with no content in hand.
    var defaultColumns: Int { maxUsefulColumns }

    /// The count actually used. Because the floor moves with paper and
    /// orientation, a density chosen in portrait is re-clamped rather than
    /// carried into landscape where it would print soft.
    var resolvedColumns: Int {
        let requested = columns > 0 ? columns : defaultColumns
        return min(max(requested, minColumns), Self.maxColumns)
    }
}

// MARK: - Layout

/// The geometry of one sheet, derived from paper + density.
struct SheetLayout: Equatable {
    let columns: Int
    let rows: Int
    /// The whole card — label band and picture together. This is what a
    /// caregiver cuts out and laminates, so it is what "tile size" means.
    let cellSize: CGSize
    /// The square picture inside the card.
    let imageSide: CGFloat
    /// The label band across the top of the card.
    let labelBand: CGFloat
    let contentOrigin: CGPoint
    let contentSize: CGSize
    let paper: PaperSize
    let orientation: PrintOrientation

    /// The sheet's own dimensions, already turned.
    var paperSize: CGSize { paper.size(in: orientation) }

    var perSheet: Int { columns * rows }

    /// Printed width of one card, in inches — the laminating-pouch number.
    var tileInches: Double { Double(cellSize.width) / 72.0 }

    /// Effective resolution of the picture, given 512 px source art.
    ///
    /// Only *large* tiles are a resolution problem. A dense board prints
    /// sharper, not softer, which is why the density guard is a floor on columns
    /// rather than a ceiling.
    var effectiveDPI: Double {
        imageSide > 0 ? 512.0 / (Double(imageSide) / 72.0) : 0
    }

    static let margin: CGFloat = 36          // 0.5"
    static let headerHeight: CGFloat = 34
    static let footerHeight: CGFloat = 20
    static let gutter: CGFloat = 6

    /// Card padding and label band, both proportional so a 1" core-board cell and
    /// a 2.5" PECS card are the same object at different sizes.
    static func cardPadding(cellWidth: CGFloat) -> CGFloat { max(1.5, cellWidth * 0.045) }
    static func labelBand(cellWidth: CGFloat) -> CGFloat { max(7, cellWidth * 0.21) }

    /// How short a card may get relative to its width. Measured off a commercial
    /// core board, whose cells run about 1.11" x 0.89".
    static let minCardAspect: CGFloat = 0.78

    /// Width of one cell at `columns` columns, in points.
    static func cellWidth(columns: Int, paper: PaperSize, orientation: PrintOrientation) -> CGFloat {
        guard columns > 0 else { return 0 }
        let contentW = paper.size(in: orientation).width - margin * 2
        return (contentW - gutter * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// The fewest columns whose tile fits within `inches`.
    static func fewestColumns(fitting inches: CGFloat,
                              paper: PaperSize,
                              orientation: PrintOrientation) -> Int {
        let limit = inches * 72
        for columns in 1...BoardPrintOptions.maxColumns
        where cellWidth(columns: columns, paper: paper, orientation: orientation) <= limit {
            return columns
        }
        return BoardPrintOptions.maxColumns
    }

    static func compute(paper: PaperSize,
                        orientation: PrintOrientation = .portrait,
                        columns rawColumns: Int) -> SheetLayout {
        let paperSize = paper.size(in: orientation)
        let floor = fewestColumns(fitting: BoardPrintOptions.maxTileInches,
                                  paper: paper, orientation: orientation)
        let columns = min(max(rawColumns, floor), BoardPrintOptions.maxColumns)

        let contentX = margin
        let contentY = margin + headerHeight
        let contentW = paperSize.width - margin * 2
        let contentH = paperSize.height - margin * 2 - headerHeight - footerHeight

        let cellW = (contentW - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        let padding = cardPadding(cellWidth: cellW)
        let band = labelBand(cellWidth: cellW)

        // Cards may be shorter than they are wide, and that is what makes real
        // board density reachable.
        //
        // Forcing a square card — a full-width picture with the label band added
        // on top — makes every card ~1.15x taller than wide, and the rows it
        // costs are the difference between 45 cells on a landscape sheet and 63.
        // A commercial core board's cells are about 1.11" x 0.89"; letting the
        // card compress toward the sheet reproduces that grid exactly.
        //
        // Rows are taken first, then the height is divided evenly among them, so
        // the grid fills the page instead of leaving a band at the bottom.
        let minCardHeight = cellW * Self.minCardAspect
        // At least one row even on paper too short to hold one — the sheet then
        // overflows rather than dividing by zero or producing an empty document.
        let rows = max(1, Int((contentH + gutter) / (minCardHeight + gutter)))
        let evenHeight = (contentH - gutter * CGFloat(rows - 1)) / CGFloat(rows)
        // Never *taller* than square: past that the card is mostly empty padding.
        let cellH = min(cellW, evenHeight)

        // The picture is the largest square that fits under the label band.
        let imageSide = max(1, min(cellW - padding * 2, cellH - band - padding))

        return SheetLayout(columns: columns,
                           rows: rows,
                           cellSize: CGSize(width: cellW, height: cellH),
                           imageSide: imageSide,
                           labelBand: band,
                           contentOrigin: CGPoint(x: contentX, y: contentY),
                           contentSize: CGSize(width: contentW, height: contentH),
                           paper: paper,
                           orientation: orientation)
    }
}

// MARK: - Pagination

/// One physical piece of paper.
struct BoardSheet: Equatable {
    /// The board page this sheet belongs to.
    let pageKey: String
    /// 1-based position within that board page.
    let sheetIndex: Int
    /// How many sheets this board page takes in total.
    let sheetCount: Int
    let tiles: [TileEntry]

    /// "Describe · 3 of 12" — numbered **within** the board page, never as a
    /// running count across the scene, so one sheet can be reprinted without
    /// renumbering the set.
    var caption: String {
        let name = PageNaming.displayName(pageKey)
        return sheetCount > 1 ? "\(name) · \(sheetIndex) of \(sheetCount)" : name
    }
}

enum BoardPagination {

    /// Lay board pages out across sheets.
    ///
    /// The rule, and the only one that matters here: **a board page always
    /// begins on a fresh sheet, and never shares one with another board page.**
    /// It may run onto as many sheets as it needs — some pages resolve to 100+
    /// tiles by class expansion, so that is the common case rather than an edge.
    ///
    /// An empty board page still gets one sheet. The printed set is meant to
    /// mirror the board's structure, and silently dropping a page the caregiver
    /// can see in the editor would make the two disagree.
    static func paginate(_ pages: [PageSpec], perSheet: Int) -> [BoardSheet] {
        guard perSheet > 0 else { return [] }
        var sheets: [BoardSheet] = []

        for page in pages {
            let chunks: [[TileEntry]] = page.tiles.isEmpty
                ? [[]]
                : stride(from: 0, to: page.tiles.count, by: perSheet).map {
                    Array(page.tiles[$0 ..< min($0 + perSheet, page.tiles.count)])
                }
            for (offset, chunk) in chunks.enumerated() {
                sheets.append(BoardSheet(pageKey: page.key,
                                         sheetIndex: offset + 1,
                                         sheetCount: chunks.count,
                                         tiles: chunk))
            }
        }
        return sheets
    }

    /// Apply the caregiver's filters before pagination, so sheet counts reflect
    /// what will actually print.
    static func filtered(_ pages: [PageSpec],
                         filter: BoardPrintFilter,
                         tileLookup: [String: TileModel]) -> [PageSpec] {
        guard filter.isActive else { return pages }
        return pages.map { page in
            var copy = page
            copy.tiles = page.tiles.filter { entry in
                guard let tile = tileLookup[entry.key] else { return false }
                if !filter.wordClasses.isEmpty, !filter.wordClasses.contains(tile.wordClass) { return false }
                if filter.audibleOnly, !entry.isAudible { return false }
                if filter.customOnly, tile.isSystem { return false }
                return true
            }
            return copy
        }
    }
}

// MARK: - Renderer

/// Tile pictures, sized and encoded for embedding in a PDF.
///
/// ## Why this exists
///
/// `UIImage.draw(in:)` inside a PDF context hands CoreGraphics a bitmap, which it
/// embeds losslessly at the image's full pixel size — regardless of how small the
/// image is on the page. At 512² that is roughly 50 KB per *placement*, and a
/// board is hundreds of placements: the 493-word default board came to **41 MB**
/// across 15 sheets, which is slow to open, slow to print, and impossible to send.
///
/// Two changes fix it, and both are things a printer would want anyway:
///
/// 1. **Downsample to the printed size.** A 1-inch tile needs 200 pixels at 200
///    DPI, not 512. Nothing is lost that ink could have shown.
/// 2. **Embed JPEG rather than a bitmap.** A `CGImage` backed by a JPEG data
///    provider is written into the PDF as DCTDecode — the original bytes, no
///    re-compression by CoreGraphics.
///
/// Together they take the same board to a few megabytes.
@MainActor
private final class PrintImageCache {
    /// Print resolution. 200 DPI is past the point where more pixels change what
    /// comes out of a consumer printer, and it is the figure the 2.5-inch tile
    /// decision was made against.
    static let targetDPI: CGFloat = 200
    /// Never upscale past the source art.
    static let sourcePixels: CGFloat = 512

    private var cache: [String: CGImage] = [:]
    private let resolver: TileImageResolver

    init(resolver: TileImageResolver) { self.resolver = resolver }

    /// A JPEG-backed image for `key`, sized for a tile `pointSize` points wide.
    func image(for key: String, in set: ImageSetID, pointSize: CGFloat) -> CGImage? {
        let pixels = min(Self.sourcePixels, max(48, (pointSize / 72) * Self.targetDPI))
        let bucket = Int(ceil(pixels / 32) * 32)      // reuse across near-equal sizes
        let id = "\(set.rawValue):\(key):\(bucket)"
        if let hit = cache[id] { return hit }
        guard let source = resolver.resolved(key, in: set) else { return nil }
        guard let made = Self.encode(source, pixels: CGFloat(bucket)) else { return nil }
        cache[id] = made
        return made
    }

    /// Encode every distinct picture up front, yielding between them.
    ///
    /// The drawing pass itself is quick — it composites pictures that are already
    /// encoded — but it runs inside `UIGraphicsPDFRenderer.pdfData`, a
    /// synchronous closure with nowhere to await. Doing the expensive half here
    /// lets the whole board report progress and stay responsive, and leaves the
    /// blocking part brief.
    func warm(keys: [String], in set: ImageSetID, pointSize: CGFloat,
              progress: @MainActor (Int, Int) -> Void) async throws {
        var seen = Set<String>()
        let unique = keys.filter { seen.insert($0).inserted }
        progress(0, unique.count)
        for (index, key) in unique.enumerated() {
            try Task.checkCancellation()
            _ = image(for: key, in: set, pointSize: pointSize)
            progress(index + 1, unique.count)
            await Task.yield()
        }
    }

    private static func encode(_ image: UIImage, pixels: CGFloat) -> CGImage? {
        let side = min(pixels, max(image.size.width, image.size.height))
        let size = CGSize(width: side, height: side)

        // Composited onto white, because JPEG carries no alpha. The shipped art is
        // already opaque, and paper is white, so this changes nothing that prints —
        // but it makes the outcome the same for a transparent tile instead of
        // leaving the alpha channel to be interpreted as black.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let fitted = aspectFit(image.size, in: CGRect(origin: .zero, size: size))
            image.draw(in: fitted)
        }

        guard let jpeg = flattened.jpegData(compressionQuality: 0.82),
              let provider = CGDataProvider(data: jpeg as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The largest rect with `size`'s aspect ratio that fits inside `bounds`.
    static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2,
                      y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

@MainActor
enum BoardPDFRenderer {

    /// Render a scene, or a single page of one, to PDF.
    ///
    /// Art is drawn straight into the PDF context from `ExportArtResolver` —
    /// never serialized to PNG on the way. A printed sheet has to agree with what
    /// the child sees on the board, so it follows the same photo → set →
    /// backfill resolution order, against whichever set the caller names.
    static func render(pages: [PageSpec],
                       scene: BlasterScene,
                       tileLookup: [String: TileModel],
                       options: BoardPrintOptions,
                       imageSet: ImageSetID,
                       resolver: TileImageResolver,
                       progress: @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> Data {
        let images = PrintImageCache(resolver: resolver)
        let layout = SheetLayout.compute(paper: options.paper,
                                         orientation: options.orientation,
                                         columns: options.resolvedColumns)
        let visible = BoardPagination.filtered(pages, filter: options.filter, tileLookup: tileLookup)
        let sheets = BoardPagination.paginate(visible, perSheet: layout.perSheet)

        try await images.warm(keys: sheets.flatMap { $0.tiles.map(\.key) },
                              in: imageSet, pointSize: layout.imageSide,
                              progress: progress)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: scene.name.isEmpty ? "Blaster Board" : scene.name,
            kCGPDFContextCreator as String: "Blaster",
        ]
        let bounds = CGRect(origin: .zero, size: layout.paperSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        return renderer.pdfData { ctx in
            for sheet in sheets {
                ctx.beginPage()
                draw(sheet: sheet, scene: scene, layout: layout, options: options,
                     tileLookup: tileLookup, imageSet: imageSet, images: images)
            }
        }
    }

    // MARK: - One sheet

    private static func draw(sheet: BoardSheet,
                             scene: BlasterScene,
                             layout: SheetLayout,
                             options: BoardPrintOptions,
                             tileLookup: [String: TileModel],
                             imageSet: ImageSetID,
                             images: PrintImageCache) {
        drawHeader(sheet: sheet, scene: scene, layout: layout)

        for (index, entry) in sheet.tiles.enumerated() {
            let column = index % layout.columns
            let row = index / layout.columns
            let x = layout.contentOrigin.x + CGFloat(column) * (layout.cellSize.width + SheetLayout.gutter)
            let y = layout.contentOrigin.y + CGFloat(row) * (layout.cellSize.height + SheetLayout.gutter)
            draw(entry: entry,
                 in: CGRect(origin: CGPoint(x: x, y: y), size: layout.cellSize),
                 layout: layout, options: options, scene: scene,
                 tileLookup: tileLookup, imageSet: imageSet, images: images)
        }

        drawFooter(scene: scene, layout: layout)
    }

    private static func drawHeader(sheet: BoardSheet, scene: BlasterScene, layout: SheetLayout) {
        let title = sheet.caption
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.black,
        ]
        let origin = CGPoint(x: SheetLayout.margin, y: SheetLayout.margin)
        (title as NSString).draw(at: origin, withAttributes: attrs)

        if !scene.name.isEmpty {
            let sub: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray,
            ]
            let width = (scene.name as NSString).size(withAttributes: sub).width
            (scene.name as NSString).draw(
                at: CGPoint(x: layout.paperSize.width - SheetLayout.margin - width, y: SheetLayout.margin + 3),
                withAttributes: sub)
        }
    }

    /// Attribution rides on **every** sheet, not just the first.
    ///
    /// A printed artifact circulates independently of the app and gets separated
    /// from its cover — a single laminated page ends up on a fridge with no
    /// indication of where the pictures came from. It needs its attribution more
    /// than the screen does, not less.
    private static func drawFooter(scene: BlasterScene, layout: SheetLayout) {
        let text = scene.attribution
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7),
            .foregroundColor: UIColor.gray,
        ]
        let y = layout.paperSize.height - SheetLayout.margin - SheetLayout.footerHeight + 6
        (text as NSString).draw(
            in: CGRect(x: SheetLayout.margin, y: y,
                       width: layout.paperSize.width - SheetLayout.margin * 2,
                       height: SheetLayout.footerHeight),
            withAttributes: attrs)
    }

    private static func draw(entry: TileEntry,
                             in cell: CGRect,
                             layout: SheetLayout,
                             options: BoardPrintOptions,
                             scene: BlasterScene,
                             tileLookup: [String: TileModel],
                             imageSet: ImageSetID,
                             images: PrintImageCache) {
        let card = cell
        let tile = tileLookup[entry.key]
        let navigates = !entry.link.isEmpty

        if options.cutLines {
            let path = UIBezierPath(rect: cell.insetBy(dx: -SheetLayout.gutter / 2,
                                                       dy: -SheetLayout.gutter / 2))
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 0.5
            UIColor.lightGray.setStroke()
            path.stroke()
        }

        // The printed tile is the app's tile.
        //
        // It used to be a bare picture with a caption under it — no frame, no
        // tint, nothing to say where one tile stopped and the next began. That
        // reads as a contact sheet, not a board, and it throws away the
        // wordClass colour a child and caregiver have already learned on screen.
        // The card, its tint, its border and the link indicator all mirror
        // `TileView.tileCard` so the laminated sheet and the iPad agree.
        let radius = max(3, card.width * 0.09)
        let border = max(1.0, card.width * 0.028)
        let padding = SheetLayout.cardPadding(cellWidth: card.width)
        let accent = navigates
            ? UIColor.systemBlue
            : UIColor(TileColorResolver.color(for: tile?.wordClass ?? ""))

        let cardPath = UIBezierPath(roundedRect: card, cornerRadius: radius)
        accent.withAlphaComponent(0.14).setFill()
        cardPath.fill()

        // Label across the top, inside the card.
        //
        // It used to sit outside and underneath, which made a contact sheet of
        // captioned pictures rather than a board of tiles. Every commercial AAC
        // board puts the word above the picture inside the same bordered cell,
        // and for a good reason: a finger resting on the tile covers the picture
        // and not the word.
        let label = tile?.displayName.isEmpty == false
            ? tile!.displayName
            : PageNaming.displayName(entry.key)
        let labelSize = max(5, layout.labelBand * 0.62)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: labelSize, weight: .semibold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: centered,
        ]
        (label as NSString).draw(
            in: CGRect(x: card.minX + 2, y: card.minY + (layout.labelBand - labelSize * 1.2) / 2,
                       width: card.width - 4, height: labelSize * 1.25),
            withAttributes: labelAttrs)

        // Clip the art to the card so a picture with its own painted background
        // cannot square off the rounded corners.
        UIGraphicsGetCurrentContext()?.saveGState()
        cardPath.addClip()

        // Centered horizontally: the card is usually wider than the square
        // picture, so anchoring left leaves a tinted gutter down one side of
        // every cell on the sheet.
        let artRect = CGRect(x: card.midX - layout.imageSide / 2,
                             y: card.minY + layout.labelBand,
                             width: layout.imageSide, height: layout.imageSide)
        if let cg = images.image(for: entry.key, in: imageSet, pointSize: layout.imageSide),
           let ctx = UIGraphicsGetCurrentContext() {
            // CoreGraphics draws images bottom-up; a UIKit PDF context is
            // top-down, so the y axis is flipped for the duration of the draw.
            // (`UIImage.draw` hides this, but it is what embeds the oversized
            // bitmap this cache exists to avoid.)
            ctx.saveGState()
            ctx.translateBy(x: artRect.minX, y: artRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: artRect.size))
            ctx.restoreGState()
        }

        // A link becomes a printed *reference to a board page by name* — never a
        // sheet number. The target spans however many sheets its density
        // requires, and that count shifts the moment the caregiver reprints at a
        // different density, so a number would be wrong on the next run.
        //
        // On screen this is a corner arrow badge, because a tap already takes you
        // there. Paper has no tap: the destination has to be legible, or the
        // reader is holding a card that says "go somewhere" but not where. So the
        // badge grows into a strip carrying the page name — same blue, same
        // meaning, inside the card rather than floating beneath it.
        if navigates {
            let target = entry.link == "<home>" ? scene.homePageKey : entry.link
            let stripHeight = max(7, card.width * 0.19)
            let strip = CGRect(x: card.minX, y: card.maxY - stripHeight,
                               width: card.width, height: stripHeight)
            UIColor.systemBlue.withAlphaComponent(0.92).setFill()
            UIBezierPath(rect: strip).fill()

            let text = "→ " + PageNaming.displayName(target)
            let size = max(5, stripHeight * 0.55)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered,
            ]
            (text as NSString).draw(
                in: strip.insetBy(dx: 2, dy: max(0, (stripHeight - size * 1.2) / 2)),
                withAttributes: attrs)
        }
        UIGraphicsGetCurrentContext()?.restoreGState()

        accent.withAlphaComponent(0.75).setStroke()
        let borderPath = UIBezierPath(roundedRect: card.insetBy(dx: border / 2, dy: border / 2),
                                      cornerRadius: radius)
        borderPath.lineWidth = border
        borderPath.stroke()
    }

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}
