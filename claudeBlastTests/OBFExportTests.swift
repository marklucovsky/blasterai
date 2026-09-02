// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OBFExportTests.swift
//  claudeBlastTests
//
//  Open Board Format export — the mapping, and the package.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct OBFExportTests {

    /// A scene with a home page that links onward, one linked page, and a mix of
    /// system and caregiver-authored words.
    private func makeScene(context: ModelContext) -> (BlasterScene, [String: TileModel]) {
        let eat = TileModel(key: "eat", value: "eat", wordClass: "actions")
        eat.isSystem = true
        let dumpling = TileModel(key: "dumpling", value: "dumpling", wordClass: "food")
        dumpling.isSystem = false
        let link = TileModel(key: PageLink.key(forPage: "food"),
                             value: "Food", wordClass: PageLink.wordClass)
        link.isSystem = true
        let silent = TileModel(key: "shh", value: "shh", wordClass: "social")
        silent.isSystem = true
        for tile in [eat, dumpling, link, silent] { context.insert(tile) }

        let scene = BlasterScene(name: "Dinner", descriptionText: "A test board",
                                 homePageKey: "home")
        scene.authorName = "Greta"
        scene.pages = [
            PageSpec(key: "home", tiles: [
                TileEntry(key: "eat", link: "", isAudible: true),
                TileEntry(key: link.key, link: "food", isAudible: false),
                TileEntry(key: "shh", link: "", isAudible: false),
            ]),
            PageSpec(key: "food", tiles: [
                TileEntry(key: "dumpling", link: "", isAudible: true),
                TileEntry(key: "eat", link: "<home>", isAudible: false),
            ]),
            // Deliberately has no way home of its own — the case the export has
            // to supply one for.
            PageSpec(key: "play", tiles: [
                TileEntry(key: "dumpling", link: "", isAudible: true),
            ]),
        ]
        context.insert(scene)
        try? context.save()

        return (scene, [eat.key: eat, dumpling.key: dumpling,
                        link.key: link, silent.key: silent])
    }

    // MARK: - Mapping

    @Test("Every page becomes a board")
    func pagesBecomeBoards() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let built = OBFExporter.boards(for: scene, tileLookup: lookup)

        #expect(built.boards.map { $0.ext_blasterai_page_key } == ["home", "food", "play"])
        #expect(built.boards.allSatisfy { $0.format == OBFFormat.version })
        #expect(built.boards[0].name == "Home")
    }

    @Test("A link becomes a board reference, resolved through <home>")
    func linksBecomeBoardReferences() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let built = OBFExporter.boards(for: scene, tileLookup: lookup)

        let navButton = try #require(built.boards[0].buttons.first { $0.load_board != nil })
        // Cboard matches `load_board` by PATH against the zip entry key, so the
        // path stays page-key based and must be exact.
        #expect(navButton.load_board?.path == "boards/food.obf")
        #expect(navButton.load_board?.id == OBFExporter.boardID(for: "food", in: scene))

        // "<home>" is ours, not OBF's — it must be resolved before it leaves.
        let homeward = try #require(built.boards[1].buttons.first { $0.load_board != nil })
        #expect(homeward.load_board?.path == "boards/home.obf")
    }

    /// Unlike a vocabulary pack, where a link means nothing outside its scene, an
    /// .obz carries every board — so navigation stays meaningful and travels.
    @Test("Page-link tiles are kept, not dropped as they are for packs")
    func chromeTravelsInOBF() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let built = OBFExporter.boards(for: scene, tileLookup: lookup)
        #expect(built.boards[0].buttons.contains { $0.ext_blasterai_tile_key == PageLink.key(forPage: "food") })
    }

    @Test("Only speaking buttons carry a vocalization")
    func vocalizationOnlyWhereItSpeaks() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let buttons = OBFExporter.boards(for: scene, tileLookup: lookup).boards[0].buttons
        let speak = try #require(buttons.first { $0.ext_blasterai_tile_key == "eat" })
        let navigate = try #require(buttons.first { $0.load_board != nil })
        let silent = try #require(buttons.first { $0.ext_blasterai_tile_key == "shh" })

        #expect(speak.vocalization == "eat")
        #expect(navigate.vocalization == nil, "a navigation button travels, it does not speak")
        #expect(silent.vocalization == nil, "OBF has no 'present but silent'; absent is the true statement")
    }

    /// In the app Home is chrome — the grid injects it at cell 0 and it is never
    /// in `page.tiles`. OBF has no chrome, so a straight export leaves every
    /// sub-board a one-way trip.
    @Test("Every sub-board gets a Home button at cell 0")
    func subBoardsCanGetBackHome() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let home = TileModel(key: "home", value: "home", wordClass: "navigation")
        home.isSystem = true
        context.insert(home)
        var withHome = lookup
        withHome["home"] = home

        let built = OBFExporter.boards(for: scene, tileLookup: withHome)
        let homeBoard = try #require(built.boards.first { $0.ext_blasterai_page_key == "home" })
        let subBoard = try #require(built.boards.first { $0.ext_blasterai_page_key == "play" })

        // Cell 0, matching the app — an invariant position is what makes it
        // motor-planned rather than hunted for.
        let firstCell = try #require(subBoard.grid.order.first?.first ?? nil)
        #expect(firstCell == "home")
        let homeButton = try #require(subBoard.buttons.first { $0.id == "home" })
        #expect(homeButton.load_board?.path == "boards/home.obf")
        #expect(homeButton.load_board?.id == OBFExporter.boardID(for: "home", in: scene))
        #expect(homeButton.vocalization == nil, "Home travels, it does not speak")

        // The home board does not link to itself.
        #expect(!homeBoard.buttons.contains { $0.id == "home" })
    }

    @Test("A page that already links home is left alone")
    func existingHomeLinkIsNotDuplicated() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let home = TileModel(key: "home", value: "home", wordClass: "navigation")
        context.insert(home)
        var withHome = lookup
        withHome["home"] = home

        // `food` already carries a "<home>" link on its `eat` tile.
        let built = OBFExporter.boards(for: scene, tileLookup: withHome)
        let food = try #require(built.boards.first { $0.ext_blasterai_page_key == "food" })
        #expect(!food.buttons.contains { $0.id == "home" },
                "a page with its own way home should not get a second one")
    }

    /// Cboard skips any board whose id it already holds, so a bare page key —
    /// `body_health`, `vehicles` — silently dropped every page whose name had
    /// been seen before, including on a re-import of a corrected file.
    @Test("Board ids are qualified by the scene, not bare page keys")
    func boardIDsAreSceneQualified() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        scene.ensureIdentity(authorID: "author-one", authorName: "Greta")

        let built = OBFExporter.boards(for: scene, tileLookup: lookup)
        #expect(built.boards.allSatisfy { $0.id != $0.ext_blasterai_page_key })
        #expect(built.boards.allSatisfy { !$0.id.contains("/") })
        #expect(Set(built.boards.map(\.id)).count == built.boards.count)

        // Two scenes that share a page name must not collide.
        let other = BlasterScene(name: "Other", homePageKey: "home")
        other.pages = [PageSpec(key: "food", tiles: [TileEntry(key: "eat")])]
        context.insert(other)
        other.ensureIdentity(authorID: "author-two", authorName: "Sam")

        #expect(OBFExporter.boardID(for: "food", in: scene)
                != OBFExporter.boardID(for: "food", in: other))
    }

    @Test("The grid holds every button, padding with empty cells")
    func gridCoversEveryButton() {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        for board in OBFExporter.boards(for: scene, tileLookup: lookup).boards {
            let cells = board.grid.order.flatMap { $0 }
            #expect(board.grid.order.count == board.grid.rows)
            #expect(board.grid.order.allSatisfy { $0.count == board.grid.columns })
            #expect(cells.count >= board.buttons.count)
            #expect(Set(cells.compactMap { $0 }) == Set(board.buttons.map(\.id)))
        }
    }

    @Test("Grid shape holds for every board size")
    func gridShapeIsAlwaysSufficient() {
        for count in 0...200 {
            let shape = OBFExporter.grid(for: count)
            #expect(shape.rows * shape.columns >= count, "\(count) buttons")
            #expect(shape.rows >= 1 && shape.columns >= 1)
        }
    }

    @Test("Colours are written in OBF's rgb() syntax, not hex")
    func coloursUseRGBSyntax() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let button = try #require(OBFExporter.boards(for: scene, tileLookup: lookup)
            .boards[0].buttons.first)
        let colour = try #require(button.background_color)
        #expect(colour.hasPrefix("rgb("))
        #expect(colour.hasSuffix(")"))
        #expect(!colour.contains("#"))
    }

    // MARK: - Licence

    /// The licence rides inside every file we send a stranger, so it has to be
    /// true. Bundled art is the project's; a caregiver's generated word is not
    /// ours to license on their behalf.
    @Test("Bundled art reports Apache-2.0; caregiver art is attributed, not licensed")
    func licenceTellsTheTruth() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let images = OBFExporter.boards(for: scene, tileLookup: lookup)
            .boards.flatMap(\.images)

        let bundled = try #require(images.first { $0.id == "eat" }?.license)
        #expect(bundled.type == "Apache-2.0")
        #expect(bundled.author_name == "BlasterAI")
        #expect(bundled.copyright_notice_url == OBFLicense.apacheURL)

        let caregiver = try #require(images.first { $0.id == "dumpling" }?.license)
        #expect(caregiver.type == "private")
        #expect(caregiver.author_name?.contains("Greta") == true)
        #expect(caregiver.copyright_notice_url == nil,
                "we do not grant a licence on the caregiver's behalf")
    }

    // MARK: - Package

    @Test("The package is a zip with a manifest, a board per page, and images")
    func packageIsWellFormed() async throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)

        let url = try await OBFExporter.exportOBZ(scene: scene, tileLookup: lookup,
                                                  imageSet: .classic,
                                                  resolver: TileImageResolver(),
                                                  basename: "dinner")
        #expect(url.pathExtension == OBFFormat.packageExtension)
        let archive = try Data(contentsOf: url)
        #expect(archive.count > 1_000)
        #expect(archive.prefix(2) == Data("PK".utf8), "not a zip")

        // Zip stores entry names uncompressed in each local file header, so the
        // package's contents can be checked without a decompressor — there is no
        // unzip API on iOS, and `Process` does not exist here.
        let bytes = String(decoding: archive, as: UTF8.self)
        for entry in ["manifest.json",
                      "boards/home.\(OBFFormat.boardExtension)",
                      "boards/food.\(OBFFormat.boardExtension)",
                      "images/eat.png"] {
            #expect(bytes.contains(entry), "package is missing \(entry)")
        }
    }

    /// Cboard ignores `manifest.root` and opens whichever board it meets first.
    /// Verified 2026-09-02 against a real export whose root correctly named the
    /// farm board and which still opened on `body_health` — alphabetically first.
    @Test("The manifest lists the root board before any other")
    func manifestPutsRootFirst() throws {
        // A home page that sorts *after* another, which is the case that broke.
        let manifest = OBFManifest(root: "boards/zebra.obf",
                                   boardOrder: ["zebra", "apple", "middle"],
                                   boards: ["apple": "boards/apple.obf",
                                            "middle": "boards/middle.obf",
                                            "zebra": "boards/zebra.obf"],
                                   images: [:])
        let json = String(decoding: try manifest.jsonData(), as: UTF8.self)

        let boardsBlock = try #require(json.range(of: "\"boards\""))
        let after = String(json[boardsBlock.upperBound...])
        let zebra = try #require(after.range(of: "zebra"))
        let apple = try #require(after.range(of: "apple"))
        #expect(zebra.lowerBound < apple.lowerBound,
                "the root board must be written first, not sorted after its siblings")
    }

    /// The documents the package carries have to be valid OBF, which is a
    /// separate question from whether the zip holds them.
    @Test("Boards and manifest survive a JSON round trip")
    func documentsRoundTrip() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        let built = OBFExporter.boards(for: scene, tileLookup: lookup)

        let encoder = JSONEncoder()
        for board in built.boards {
            let decoded = try JSONDecoder().decode(OBFBoard.self, from: encoder.encode(board))
            #expect(decoded.id == board.id)
            #expect(decoded.buttons.count == board.buttons.count)
            #expect(decoded.grid.order.count == board.grid.rows)
            #expect(decoded.images.count == board.images.count)
        }

        let manifest = OBFManifest(root: "boards/home.\(OBFFormat.boardExtension)",
                                   boardOrder: ["home"],
                                   boards: ["home": "boards/home.obf"],
                                   images: ["eat": "images/eat.png"])
        let decoded = try JSONDecoder().decode(OBFManifestRead.self, from: manifest.jsonData())
        #expect(decoded.root == manifest.root)
        #expect(decoded.paths["images"]?["eat"] == "images/eat.png")
        #expect(decoded.paths["boards"]?["home"] == "boards/home.obf")
    }

    /// OBF permits vendor fields only under an `ext_<vendor>_` prefix. Ours carry
    /// the provenance the format has nowhere to put, so a board that round-trips
    /// through another app can still say where it came from.
    @Test("Our own fields stay inside the ext_ namespace")
    func extensionsAreNamespaced() throws {
        TestStore.reset()
        let context = TestStore.container.mainContext
        let (scene, lookup) = makeScene(context: context)
        scene.ensureIdentity(authorID: "tester", authorName: "Greta")

        let built = OBFExporter.boards(for: scene, tileLookup: lookup)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(built.boards[0])) as? [String: Any] ?? [:]

        let ours = json.keys.filter { $0.hasPrefix("ext_") }
        #expect(!ours.isEmpty)
        #expect(ours.allSatisfy { $0.hasPrefix(OBFFormat.extensionPrefix) })

        let button = (json["buttons"] as? [[String: Any]])?.first ?? [:]
        #expect(button.keys.filter { $0.hasPrefix("ext_") }
            .allSatisfy { $0.hasPrefix(OBFFormat.extensionPrefix) })
    }
}
}
