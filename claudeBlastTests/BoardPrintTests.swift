// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardPrintTests.swift
//  claudeBlastTests
//
//  Sheet layout and pagination for the printable board.
//

import Testing
import SwiftData
import Foundation
import CoreGraphics
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct BoardPrintTests {

    private func page(_ key: String, _ count: Int) -> PageSpec {
        PageSpec(key: key, tiles: (0..<count).map { TileEntry(key: "\(key)_\($0)") })
    }

    // MARK: - Pagination

    /// The rule the whole renderer is built around.
    @Test("A board page never shares a sheet with another board page")
    func pagesNeverShareASheet() {
        // Two pages that would comfortably fit together on one sheet.
        let sheets = BoardPagination.paginate([page("home", 3), page("food", 3)], perSheet: 16)

        #expect(sheets.count == 2)
        #expect(sheets[0].pageKey == "home")
        #expect(sheets[1].pageKey == "food")
        for sheet in sheets {
            #expect(Set(sheet.tiles.map { $0.key.split(separator: "_").first! }).count == 1)
        }
    }

    @Test("A large board page runs onto as many sheets as it needs")
    func largePageSpansSheets() {
        let sheets = BoardPagination.paginate([page("describe", 104)], perSheet: 16)

        #expect(sheets.count == 7)                       // 104 / 16 → 6 full + 1
        #expect(sheets.map(\.tiles.count).reduce(0, +) == 104)
        #expect(sheets.last?.tiles.count == 8)
    }

    /// Numbered within the board page, so one sheet can be reprinted without
    /// renumbering the set.
    @Test("Continuation sheets are numbered within their board page")
    func continuationNumberingIsPerPage() {
        let sheets = BoardPagination.paginate([page("home", 3), page("describe", 40)], perSheet: 16)

        #expect(sheets[0].caption == "Home")             // single sheet → no counter
        #expect(sheets[1].caption == "Describe · 1 of 3")
        #expect(sheets[2].caption == "Describe · 2 of 3")
        #expect(sheets[3].caption == "Describe · 3 of 3")
    }

    @Test("Page keys are title-cased for print")
    func pageNamesAreReadable() {
        let sheets = BoardPagination.paginate([page("play_activities", 2)], perSheet: 16)
        #expect(sheets[0].caption == "Play Activities")
    }

    /// The printed set mirrors the board's structure; silently dropping a page
    /// the caregiver can see in the editor would make the two disagree.
    @Test("An empty board page still gets one sheet")
    func emptyPageStillPrints() {
        let sheets = BoardPagination.paginate([page("home", 2), page("empty", 0)], perSheet: 16)

        #expect(sheets.count == 2)
        #expect(sheets[1].pageKey == "empty")
        #expect(sheets[1].tiles.isEmpty)
        #expect(sheets[1].sheetCount == 1)
    }

    @Test("A page that exactly fills a sheet does not spill onto a second")
    func exactFitDoesNotAddASheet() {
        let sheets = BoardPagination.paginate([page("home", 16)], perSheet: 16)
        #expect(sheets.count == 1)
        #expect(sheets[0].sheetCount == 1)
    }

    // MARK: - Layout

    @Test("Three columns on portrait US Letter gives ~2.4-inch tiles")
    func letterAtThreeColumns() {
        let layout = SheetLayout.compute(paper: .usLetter, orientation: .portrait, columns: 3)

        #expect(abs(layout.tileInches - 2.4) < 0.15)
        #expect(layout.columns == 3)
        #expect(layout.effectiveDPI > 190)
    }

    @Test("Landscape turns the sheet")
    func landscapeSwapsDimensions() {
        let portrait = SheetLayout.compute(paper: .usLetter, orientation: .portrait, columns: 5)
        let landscape = SheetLayout.compute(paper: .usLetter, orientation: .landscape, columns: 5)

        #expect(portrait.paperSize == CGSize(width: 612, height: 792))
        #expect(landscape.paperSize == CGSize(width: 792, height: 612))
        // Same columns on a shorter sheet: wider cells, fewer rows.
        #expect(landscape.cellSize.width > portrait.cellSize.width)
        #expect(landscape.rows < portrait.rows)
    }

    /// A card may be shorter than it is wide, but never taller — past square it
    /// is mostly empty padding.
    @Test("Cards stay within the aspect band, and the picture fits inside")
    func cardAspectIsBounded() {
        for paper in PaperSize.all {
            for orientation in PrintOrientation.allCases {
                let options = BoardPrintOptions(paper: paper, orientation: orientation)
                for columns in options.minColumns...options.maxUsefulColumns {
                    let l = SheetLayout.compute(paper: paper, orientation: orientation,
                                                columns: columns)
                    let where_ = "\(paper.displayName) \(orientation.label) at \(columns)"
                    #expect(l.cellSize.height <= l.cellSize.width + 0.01, "\(where_) taller than wide")
                    #expect(l.imageSide > 0, "\(where_) no room for a picture")
                    #expect(l.imageSide <= l.cellSize.height - l.labelBand + 0.01, "\(where_) picture overflows card")
                }
            }
        }
    }

    /// The floor is derived from the printable width, not hardcoded — a constant
    /// 3 is right for portrait Letter by coincidence and wrong the moment the
    /// sheet turns. Landscape Letter is 10 inches wide, where 3 columns would
    /// give 3.3-inch tiles.
    @Test("The column floor moves with paper and orientation")
    func columnFloorIsDerived() {
        let portrait = BoardPrintOptions(paper: .usLetter, orientation: .portrait)
        let landscape = BoardPrintOptions(paper: .usLetter, orientation: .landscape)

        #expect(portrait.minColumns == 3)
        #expect(landscape.minColumns > portrait.minColumns)

        // The floor it rejects really would have been too big.
        let tooFew = SheetLayout.cellWidth(columns: portrait.minColumns - 1,
                                           paper: .usLetter, orientation: .portrait) / 72
        #expect(tooFew > BoardPrintOptions.maxTileInches)
    }

    /// Density answers to the content, not only the paper: a fourteen-word page
    /// printed at core-board density is fourteen stamps on a blank sheet.
    @Test("The default gives the largest tile that still fits the page on one sheet")
    func defaultFitsThePageOnOneSheet() {
        for paper in PaperSize.all {
            for orientation in PrintOrientation.allCases {
                let options = BoardPrintOptions(paper: paper, orientation: orientation)
                let where_ = "\(paper.displayName) \(orientation.label)"

                for count in [6, 14, 30, 63] {
                    let columns = options.defaultColumns(fittingLargestPage: count)
                    let layout = SheetLayout.compute(paper: paper, orientation: orientation,
                                                     columns: columns)
                    #expect(columns >= options.minColumns, "\(where_) at \(count)")
                    // Fits on one sheet — or, when the sheet physically cannot
                    // hold that many cells at a usable size, went as dense as it
                    // is allowed to. A4 is narrower than Letter, so 63 cells at
                    // 1" genuinely does not fit on it.
                    #expect(layout.perSheet >= count || columns == options.maxUsefulColumns,
                            "\(where_): \(count) tiles, chose \(columns) columns holding \(layout.perSheet)")

                    // And it is the *largest* such tile — one column fewer would
                    // not have fitted.
                    if columns > options.minColumns {
                        let looser = SheetLayout.compute(paper: paper, orientation: orientation,
                                                         columns: columns - 1)
                        #expect(looser.perSheet < count, "\(where_): \(columns) is denser than needed for \(count)")
                    }
                }
            }
        }
    }

    /// A commercial laminated core board runs nine cells across a landscape
    /// sheet, ~1.05" each. An earlier 1.5" floor put that out of reach — a core
    /// board is meant to be dense.
    @Test("Real core-board density is reachable")
    func coreBoardDensityIsReachable() {
        let options = BoardPrintOptions(paper: .usLetter, orientation: .landscape)
        #expect(options.maxUsefulColumns >= 9)

        let layout = SheetLayout.compute(paper: .usLetter, orientation: .landscape, columns: 9)
        #expect(abs(layout.tileInches - 1.11) < 0.15)
        // The reference board fits 63 cells on this sheet; so must we.
        #expect(layout.perSheet >= 63, "9x\(layout.rows) = \(layout.perSheet)")
        // Dense prints sharper, not softer.
        #expect(layout.effectiveDPI > 400)
    }

    @Test("A page too big for any one sheet falls back to the densest usable grid")
    func oversizePageUsesDensestGrid() {
        let options = BoardPrintOptions(paper: .usLetter, orientation: .portrait)
        #expect(options.defaultColumns(fittingLargestPage: 5000) == options.maxUsefulColumns)
    }

    @Test("Every automatic density keeps cells at a usable size")
    func automaticDensityStaysUsable() {
        for paper in PaperSize.all {
            for orientation in PrintOrientation.allCases {
                let options = BoardPrintOptions(paper: paper, orientation: orientation)
                for count in [6, 14, 30, 63, 200] {
                    let layout = SheetLayout.compute(
                        paper: paper, orientation: orientation,
                        columns: options.defaultColumns(fittingLargestPage: count))
                    let where_ = "\(paper.displayName) \(orientation.label) at \(count)"
                    #expect(layout.tileInches >= Double(BoardPrintOptions.minTileInches) - 0.01, "\(where_)")
                    #expect(layout.tileInches <= Double(BoardPrintOptions.maxTileInches), "\(where_)")
                }
            }
        }
    }

    /// Denser is sharper, so the guard is a floor on columns rather than a
    /// ceiling — the opposite of what a resolution limit usually implies.
    @Test("Every reachable density stays legible, on every sheet")
    func densityFloorKeepsArtSharp() {
        for paper in PaperSize.all {
            for orientation in PrintOrientation.allCases {
                let options = BoardPrintOptions(paper: paper, orientation: orientation)
                #expect(BoardPrintOptions(paper: paper, orientation: orientation, columns: 1)
                            .resolvedColumns == options.minColumns)
                #expect(BoardPrintOptions(paper: paper, orientation: orientation, columns: 99)
                            .resolvedColumns == BoardPrintOptions.maxColumns)

                for columns in options.minColumns...BoardPrintOptions.maxColumns {
                    let layout = SheetLayout.compute(paper: paper, orientation: orientation,
                                                     columns: columns)
                    let where_ = "\(paper.displayName) \(orientation.label) at \(columns)"
                    #expect(layout.tileInches <= Double(BoardPrintOptions.maxTileInches), "\(where_)")
                    #expect(layout.effectiveDPI >= 150, "\(where_)")
                }
            }
        }
    }

    @Test("Denser grids fit strictly more tiles per sheet")
    func densityIncreasesCapacity() {
        for orientation in PrintOrientation.allCases {
            let options = BoardPrintOptions(paper: .usLetter, orientation: orientation)
            var previous = 0
            for columns in options.minColumns...BoardPrintOptions.maxColumns {
                let layout = SheetLayout.compute(paper: .usLetter, orientation: orientation,
                                                 columns: columns)
                #expect(layout.perSheet > previous, "\(orientation.label) at \(columns) columns")
                previous = layout.perSheet
            }
        }
    }

    @Test("Every paper and orientation produces a usable grid")
    func everySheetLaysOut() {
        for paper in PaperSize.all {
            for orientation in PrintOrientation.allCases {
                let options = BoardPrintOptions(paper: paper, orientation: orientation)
                let layout = SheetLayout.compute(paper: paper, orientation: orientation,
                                                 columns: options.resolvedColumns)
                #expect(layout.rows >= 2, "\(paper.displayName) \(orientation.label)")
                #expect(layout.perSheet >= 10, "\(paper.displayName) \(orientation.label)")
            }
        }
    }

    // MARK: - Filters

    @Test("Filters apply before pagination, so sheet counts reflect what prints")
    func filtersChangeSheetCount() {
        TestStore.reset()
        let context = TestStore.container.mainContext

        var lookup: [String: TileModel] = [:]
        for index in 0..<20 {
            let tile = TileModel(key: "w\(index)",
                                 value: "w\(index)",
                                 wordClass: index < 5 ? "food" : "actions")
            tile.isSystem = true
            context.insert(tile)
            lookup[tile.key] = tile
        }
        let spec = PageSpec(key: "home", tiles: (0..<20).map { TileEntry(key: "w\($0)") })

        var filter = BoardPrintFilter()
        filter.wordClasses = ["food"]
        let filtered = BoardPagination.filtered([spec], filter: filter, tileLookup: lookup)

        #expect(filtered[0].tiles.count == 5)
        #expect(BoardPagination.paginate(filtered, perSheet: 9).count == 1)
        #expect(BoardPagination.paginate([spec], perSheet: 9).count == 3)
    }

    @Test("Audible-only drops navigation tiles")
    func audibleOnlyDropsNavigation() {
        TestStore.reset()
        let context = TestStore.container.mainContext

        let word = TileModel(key: "eat", value: "eat", wordClass: "actions")
        let link = TileModel(key: "page_food", value: "Food", wordClass: PageLink.wordClass)
        context.insert(word); context.insert(link)

        let spec = PageSpec(key: "home", tiles: [
            TileEntry(key: "eat", link: "", isAudible: true),
            TileEntry(key: "page_food", link: "food", isAudible: false),
        ])

        var filter = BoardPrintFilter()
        filter.audibleOnly = true
        let filtered = BoardPagination.filtered([spec], filter: filter,
                                                tileLookup: ["eat": word, "page_food": link])

        #expect(filtered[0].tiles.map(\.key) == ["eat"])
    }

    // MARK: - Rendering

    /// The bundled board is the worst case: 493 words, pages defined by class
    /// expansion, fifteen sheets.
    ///
    /// It first rendered at **41 MB** — `UIImage.draw(in:)` inside a PDF context
    /// embeds a losslessly-compressed bitmap at the image's full 512², once per
    /// placement, however small the tile is on the page. Downsampling to the
    /// printed size and embedding JPEG took the same document to under 4 MB.
    ///
    /// The budget below is deliberately loose: it is guarding against a return to
    /// per-placement bitmaps, not policing a few kilobytes.
    @Test("The whole default board stays a sendable size")
    func defaultBoardPDFStaysSmall() async throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        _ = BootstrapLoader.loadDefaultVocabulary(context: context)
        try context.save()

        let scenes = try context.fetch(FetchDescriptor<BlasterScene>())
        let scene = try #require(scenes.first { $0.isDefault } ?? scenes.first)
        let tiles = try context.fetch(FetchDescriptor<TileModel>())
        let lookup = Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        var options = BoardPrintOptions()
        options.columns = options.defaultColumns(
            fittingLargestPage: scene.pages.map(\.tiles.count).max() ?? 0)
        let layout = SheetLayout.compute(paper: options.paper, orientation: options.orientation,
                                         columns: options.resolvedColumns)
        let sheets = BoardPagination.paginate(scene.pages, perSheet: layout.perSheet).count

        let data = try await BoardPDFRenderer.render(pages: scene.pages, scene: scene,
                                           tileLookup: lookup, options: options,
                                           imageSet: .classic,
                                           resolver: TileImageResolver())

        let perSheet = data.count / max(1, sheets)
        #expect(perSheet < 800_000,
                "\(sheets) sheets, \(data.count / 1_048_576) MB — \(perSheet / 1024) KB per sheet")
        // Sanity: it did render the pictures, not just the frames.
        #expect(data.count > 200_000)
    }

    @Test("Rendering produces a real PDF with one page per sheet")
    func renderProducesAPDFPerSheet() async throws {
        TestStore.reset()
        let context = TestStore.container.mainContext

        var lookup: [String: TileModel] = [:]
        for index in 0..<20 {
            let tile = TileModel(key: "w\(index)", value: "word \(index)", wordClass: "actions")
            context.insert(tile)
            lookup[tile.key] = tile
        }
        let scene = BlasterScene(name: "Print Me", homePageKey: "home")
        scene.pages = [
            PageSpec(key: "home", tiles: (0..<20).map { TileEntry(key: "w\($0)") }),
            PageSpec(key: "food", tiles: [TileEntry(key: "w0")]),
        ]
        context.insert(scene)
        try context.save()

        // The densest grid this sheet allows, so the 20-tile page is forced to
        // spill and the second page still starts fresh.
        var options = BoardPrintOptions()
        options.columns = BoardPrintOptions.maxColumns
        let layout = SheetLayout.compute(paper: options.paper,
                                         orientation: options.orientation,
                                         columns: options.resolvedColumns)
        let sheets = BoardPagination.paginate(scene.pages, perSheet: layout.perSheet)

        let data = try await BoardPDFRenderer.render(pages: scene.pages, scene: scene,
                                           tileLookup: lookup, options: options,
                                           imageSet: .classic,
                                           resolver: TileImageResolver())

        #expect(!data.isEmpty)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == sheets.count)
        // Two board pages, so never fewer than two sheets however dense the grid.
        #expect(sheets.count >= 2)
        #expect(Set(sheets.map(\.pageKey)) == ["home", "food"])
    }
}
}
