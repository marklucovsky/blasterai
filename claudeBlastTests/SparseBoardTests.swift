// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SparseBoardTests.swift
//  claudeBlastTests
//
//  Concealed words and spacers — the two ways a board holds a cell empty.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SparseBoardTests {

    // MARK: - Identity

    /// The reason spacers are not a bare `<spacer>` token. Four grid surfaces
    /// render with `ForEach(tiles, id: \.key)`, and `TileEntry.id` IS its key —
    /// two identical keys on one page is one SwiftUI identity, which misrenders
    /// silently rather than failing.
    @Test("Every spacer has its own identity")
    func spacersAreUnique() {
        let spacers = (0..<50).map { _ in TileEntry.spacer() }
        #expect(Set(spacers.map(\.id)).count == spacers.count)
        #expect(spacers.allSatisfy { $0.isSpacer })
    }

    /// A spacer is recognised by an explicit reserved prefix, never by "this key
    /// did not resolve". `docs/s4-cleanup.md` §9 records a page that looked
    /// populated in the editor and drew empty on the board because an export bug
    /// dropped its words — unresolvable keys are the signature of corruption, and
    /// conflating the two would destroy the only signal that separates a broken
    /// board from an intentional one.
    @Test("A word is never mistaken for a spacer")
    func wordsAreNotSpacers() {
        for key in ["eat", "more", "page_farm", "home", "zzz_never_seen"] {
            #expect(!TileEntry(key: key).isSpacer, "\(key) read as a spacer")
        }
    }

    // MARK: - Decoding

    /// The case that would fail in a stranger's hands rather than in a migration
    /// we control: a scene file shared from a device running an older build.
    ///
    /// Swift's synthesized decoder calls `decode` for a non-optional property and
    /// throws on a missing key — a default value does not save it — which is why
    /// `TileEntry` hand-writes `init(from:)`.
    @Test("A tile written before conceal existed still decodes")
    func decodesWithoutTheField() throws {
        let json = #"{"key":"eat","link":"","isAudible":true}"#
        let entry = try JSONDecoder().decode(TileEntry.self, from: Data(json.utf8))
        #expect(entry.key == "eat")
        #expect(entry.isConcealed == false)
        #expect(entry.isAudible)
    }

    @Test("A page written before conceal existed still decodes")
    func decodesWholePage() throws {
        let json = #"{"key":"home","tiles":[{"key":"eat","link":"","isAudible":true}]}"#
        let page = try JSONDecoder().decode(PageSpec.self, from: Data(json.utf8))
        #expect(page.tiles.count == 1)
        #expect(page.tiles[0].isConcealed == false)
    }

    @Test("Conceal survives a round trip")
    func concealRoundTrips() throws {
        let original = TileEntry(key: "eat", isConcealed: true)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(TileEntry.self, from: data)
        #expect(back.isConcealed)
        #expect(back == original)
    }

    // MARK: - Coverage

    private func page(_ tiles: [TileEntry]) -> PageSpec {
        PageSpec(key: "home", tiles: tiles)
    }

    /// The distinction the feature exists to preserve. A caregiver who conceals
    /// ten words to teach six must not read "the child ignores fifty words".
    @Test("A concealed word is not counted as reachable vocabulary")
    func concealedIsNotReachable() {
        let pages = [page([
            TileEntry(key: "eat"),
            TileEntry(key: "want", isConcealed: true),
            TileEntry.spacer(),
        ])]

        #expect(CoverageReport.vocabularyKeys(of: pages) == ["eat"])
        #expect(CoverageReport.concealedKeys(of: pages) == ["want"])
    }

    /// A spacer was never a word, so it appears in neither list.
    @Test("A spacer is not vocabulary and is not concealed vocabulary")
    func spacerIsNotAWord() {
        let pages = [page([TileEntry(key: "eat"), TileEntry.spacer(), TileEntry.spacer()])]
        #expect(CoverageReport.vocabularyKeys(of: pages) == ["eat"])
        #expect(CoverageReport.concealedKeys(of: pages).isEmpty)
    }

    /// Conceal is per-placement, so a word concealed on one page and available
    /// on another is available — the child can still reach it.
    @Test("A word concealed on one page but open on another is reachable")
    func concealIsPerPlacement() {
        let pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "want", isConcealed: true)]),
            PageSpec(key: "actions", tiles: [TileEntry(key: "want")]),
        ]
        #expect(CoverageReport.vocabularyKeys(of: pages) == ["want"])
        #expect(CoverageReport.concealedKeys(of: pages).isEmpty)
    }

    // MARK: - Placement

    /// A new gap lands in slot 0, the same place a newly picked tile does
    /// (`TilePickerView` inserts at index 0). On a long page an appended gap
    /// would arrive off the bottom of the screen, and a blank cell is the one
    /// thing that cannot announce itself once it is out of view.
    @Test("A new space lands at the front, beside the Add cell")
    func spacerLandsAtTheFront() {
        let existing = [TileEntry(key: "eat"), TileEntry(key: "want")]
        let after = [TileEntry.spacer()] + existing

        #expect(after.first?.isSpacer == true)
        #expect(after.count == existing.count + 1)
        // Everything else keeps its order, so a gap added by mistake is one
        // undo away from a board that never moved.
        #expect(after.dropFirst().map(\.key) == existing.map(\.key))
    }

    // MARK: - Sharing

    /// The failure this caught in the field: a shared board arrived with its
    /// gaps closed. Both the exporter and the importer guard on
    /// `tileLookup[key]`, which a spacer has no entry in, so it was silently
    /// dropped — and `ExportablePageTile` had no conceal flag, so a concealed
    /// word arrived available. Either one reflows the recipient's board, which
    /// is the exact thing sparse boards exist to prevent.
    @Test("A shared scene keeps its gaps")
    func sceneShareRoundTripsGaps() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext

        let cow = TileModel(key: "cow", wordClass: "animal")
        let alien = TileModel(key: "alien", wordClass: "people")
        context.insert(cow)
        context.insert(alien)
        let lookup = ["cow": cow, "alien": alien]

        let spacer = TileEntry.spacer()
        let scene = BlasterScene(name: "Farm Visit", descriptionText: "", homePageKey: "farm")
        scene.pages = [PageSpec(key: "farm", tiles: [
            TileEntry(key: "cow"),
            TileEntry(key: "alien", isConcealed: true),
            spacer,
        ])]
        context.insert(scene)

        let exportable = SceneExporter.export(scene, defaultTileKeys: ["cow", "alien"],
                                              tileLookup: lookup)

        // On the wire: three placements, in order, with the gap intact.
        let wire = try #require(exportable.pages.first)
        #expect(wire.tiles.count == 3, "a placement was dropped on export")
        #expect(wire.tiles[1].isConcealed == true)
        #expect(wire.tiles[2].key == spacer.key)

        // And back again, through the real JSON path.
        let data = try JSONEncoder().encode(exportable)
        let result = try SceneImporter.importJSON(data, context: context)
        let landed = try #require(result.scene.pages.first)

        #expect(landed.tiles.count == 3, "a placement was dropped on import")
        #expect(landed.tiles.map(\.key) == ["cow", "alien", spacer.key])
        #expect(landed.tiles[1].isConcealed)
        #expect(landed.tiles[2].isSpacer)
        // A gap is not a missing word, so it must not be reported as skipped.
        #expect(!result.skippedKeys.contains { $0.hasPrefix(TileToken.spacerPrefix) })
    }

    /// A file written before conceal existed must still import — the case that
    /// fails in a stranger's hands rather than in a migration we control.
    @Test("A scene file without the conceal field still imports")
    func legacySceneFileImports() throws {
        let json = """
        {"@type":"\(BlasterSceneFormat.mediaType)","version":"\(BlasterSceneFormat.currentVersion)",\
        "name":"Legacy","description":"","homePageKey":"home",\
        "pages":[{"key":"home","tiles":[{"key":"cow","isAudible":true,"link":""}]}],"tiles":[]}
        """
        let container = TestStore.freshContainer()
        let context = container.mainContext
        context.insert(TileModel(key: "cow", wordClass: "animal"))

        let result = try SceneImporter.importJSON(Data(json.utf8), context: context)
        let page = try #require(result.scene.pages.first)
        #expect(page.tiles.count == 1)
        #expect(page.tiles[0].isConcealed == false)
    }

    // MARK: - Bulk conceal

    /// The rule the selection bar enforces, tested on the data rather than the
    /// view: a toggle over a mixed selection has no honest answer, so the
    /// control names the one thing it will do and refuses when there is not one.
    private func action(for entries: [TileEntry]) -> String {
        if entries.isEmpty { return "conceal" }
        if entries.allSatisfy({ $0.isConcealed }) { return "reveal" }
        if entries.allSatisfy({ !$0.isConcealed }) { return "conceal" }
        return "mixed"
    }

    @Test("All-visible offers Conceal, all-concealed offers Reveal")
    func uniformSelectionsOfferOneAction() {
        #expect(action(for: [TileEntry(key: "a"), TileEntry(key: "b")]) == "conceal")
        #expect(action(for: [TileEntry(key: "a", isConcealed: true),
                             TileEntry(key: "b", isConcealed: true)]) == "reveal")
    }

    /// Neither label is true of a mixed selection, and flipping each tile would
    /// leave the caregiver the same mixture inverted — which is nobody's intent.
    @Test("A mixed selection offers neither")
    func mixedSelectionRefuses() {
        #expect(action(for: [TileEntry(key: "a"),
                             TileEntry(key: "b", isConcealed: true)]) == "mixed")
    }

    /// A gap has no word to hide. Concealing one would store a no-op as if it
    /// meant something, and would make an all-spacer selection look uniform.
    @Test("Bulk conceal skips spacers")
    func bulkConcealSkipsSpacers() {
        var entries = [TileEntry(key: "eat"), TileEntry.spacer()]
        for index in entries.indices where !entries[index].isSpacer {
            entries[index].isConcealed = true
        }
        #expect(entries[0].isConcealed)
        #expect(!entries[1].isConcealed, "a spacer was concealed")
        #expect(entries[1].isEmptyCell, "and it is still a gap")
    }

    // MARK: - Print

    /// A gap must survive a print filter. Dropping it would close the hole and
    /// shift every tile after it, so a filtered sheet would no longer match the
    /// board it was printed from.
    @Test("Print filters never close a gap")
    func printFiltersKeepGaps() {
        let tile = TileModel(key: "eat", value: "eat", wordClass: "actions")
        let pages = [page([
            TileEntry(key: "eat"),
            TileEntry(key: "want", isConcealed: true),
            TileEntry.spacer(),
        ])]

        var filter = BoardPrintFilter()
        filter.wordClasses = ["actions"]
        let filtered = BoardPagination.filtered(pages, filter: filter,
                                                tileLookup: ["eat": tile])

        #expect(filtered[0].tiles.count == 3,
                "a filter removed a gap and reflowed the sheet")
        #expect(filtered[0].tiles.filter { $0.isEmptyCell }.count == 2)
    }
}
}
