// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GradedRevealTests.swift
//  claudeBlastTests
//
//  Board levels: a scene declares levels, each placement appears from one, and
//  the board draws everything above the current level as a concealed cell in
//  place. These pin the data shape, the projection every child-facing surface
//  reads, and that every path a scene travels — bundle, update, share, refine —
//  carries the levels and keeps the caregiver's dial.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct GradedRevealTests {

    // MARK: - Fixtures

    /// Home: `want` always, `more` from L2, `juice` from L3, a folder from L3,
    /// a spacer, and `stop` concealed by the caregiver.
    private func leveledScene(in context: ModelContext) -> BlasterScene {
        let s = BlasterScene(name: "Levels", descriptionText: "", homePageKey: "home")
        s.pages = [
            PageSpec(key: "home", tiles: [
                TileEntry(key: "want"),
                TileEntry(key: "more", revealLevel: 2),
                TileEntry(key: "juice", revealLevel: 3),
                TileEntry(key: "page_food", link: "food", isAudible: false, revealLevel: 3),
                TileEntry.spacer(),
                TileEntry(key: "stop", isConcealed: true),
            ]),
            PageSpec(key: "food", tiles: [TileEntry(key: "apple")]),
        ]
        s.revealLevelCount = 3
        context.insert(s)
        return s
    }

    private func insertWords(_ keys: [String], in context: ModelContext) {
        for key in keys { context.insert(TileModel(key: key, value: key, wordClass: "core")) }
        try? context.save()
    }

    // MARK: - Encoding

    /// The synthesized encoder `TileEntry` had before levels, field for field.
    /// A level-0 entry must encode to the same JSON object — no `revealLevel`
    /// key, nothing else changed — or every stored scene would grow a field on
    /// its next write.
    ///
    /// Compared as parsed objects, not bytes: `JSONEncoder` orders keys
    /// differently in every process, so two encodings of the same value are
    /// not byte-identical even before this change.
    private struct LegacyTileEntry: Encodable {
        let key: String
        let link: String
        let isAudible: Bool
        let isConcealed: Bool
        let linkColor: String?
        let linkColorIsAuto: Bool
    }

    @Test func levelZeroEncodesTheSameObjectAsBefore() throws {
        let result = BootstrapLoader.loadDefaultVocabulary(context: TestStore.freshContainer().mainContext)
        let entries = result.scene.pages.flatMap(\.tiles).map { var e = $0; e.revealLevel = 0; return e }
        let legacy = entries.map {
            LegacyTileEntry(key: $0.key, link: $0.link, isAudible: $0.isAudible,
                            isConcealed: $0.isConcealed, linkColor: $0.linkColor,
                            linkColorIsAuto: $0.linkColorIsAuto)
        }
        let now = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries)) as? NSArray
        let before = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? NSArray
        #expect(now != nil && now == before)
        #expect(entries.count > 100)
    }

    @Test func aLevelRoundTripsAndZeroIsOmitted() throws {
        let entries = [TileEntry(key: "a"), TileEntry(key: "b", revealLevel: 3)]
        let data = try JSONEncoder().encode(entries)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.components(separatedBy: "revealLevel").count == 2, "only the leveled entry writes the key")
        let back = try JSONDecoder().decode([TileEntry].self, from: data)
        #expect(back.map(\.revealLevel) == [0, 3])
    }

    // MARK: - The projection

    @Test func aboveTheLevelDrawsAsConcealedInPlace() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        let home = s.pages(atLevel: 1).first { $0.key == "home" }!
        #expect(home.tiles.count == 6, "nothing is removed — cells keep their place")
        #expect(home.tiles.map(\.isEmptyCell) == [false, true, true, true, true, true])

        let atTwo = s.pages(atLevel: 2).first { $0.key == "home" }!
        #expect(atTwo.tiles.map(\.isEmptyCell) == [false, false, true, true, true, true])

        let atTop = s.pages(atLevel: 3).first { $0.key == "home" }!
        #expect(atTop.tiles.map(\.isEmptyCell) == [false, false, false, false, true, true],
                "the caregiver's conceal and the spacer hold at every level")
    }

    @Test func noLevelsIsTheIdentity() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        s.revealLevelCount = 0
        #expect(s.effectiveRevealLevel == nil)
        #expect(s.visiblePages == s.pages)
    }

    @Test func theProjectionFollowsTheDial() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        s.revealLevel = 1
        #expect(s.visibleTileCount(atLevel: s.effectiveRevealLevel) == 2) // want, apple
        s.revealLevel = 3
        #expect(s.visibleTileCount(atLevel: s.effectiveRevealLevel) == 5)
        s.revealLevel = 1
        #expect(s.visibleTileCount(atLevel: s.effectiveRevealLevel) == 2, "cache keyed by level")
    }

    @Test func theProjectionSeesAnEdit() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        #expect(s.visibleTileCount(atLevel: 1) == 2)
        var pages = s.pages
        pages[0].tiles[1].revealLevel = 1
        s.pages = pages
        #expect(s.visibleTileCount(atLevel: 1) == 3, "cache keyed by the bytes too")
    }

    @Test func effectiveLevelClamps() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        #expect(s.effectiveRevealLevel == 3, "a stored 0 reads as the top, hiding nothing")
        s.revealLevel = 1
        #expect(s.effectiveRevealLevel == 1)
        s.revealLevel = 9
        #expect(s.effectiveRevealLevel == 3)
    }

    @Test func setRevealLevelStaysInRange() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        s.setRevealLevel(0)
        #expect(s.revealLevel == 1, "a board with levels is always at one")
        s.setRevealLevel(7)
        #expect(s.revealLevel == 3)
    }

    @Test func turningLevelsOnStartsAtTheTop() {
        let context = TestStore.freshContainer().mainContext
        let s = BlasterScene(name: "Plain", descriptionText: "", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]
        context.insert(s)
        s.setRevealLevelCount(5)
        #expect(s.revealLevel == 5, "nothing disappears until a caregiver steps down")
        s.setRevealLevel(2)
        s.setRevealLevelCount(0)
        s.setRevealLevelCount(4)
        #expect(s.revealLevel == 4, "back on is a fresh start at the top")
    }

    // MARK: - Authoring

    @Test func loweringTheLevelCountBringsPlacementsDown() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        s.revealLevel = 3
        s.setRevealLevelCount(2)
        #expect(s.pages[0].tiles.map(\.revealLevel) == [0, 2, 2, 2, 0, 0])
        #expect(s.revealLevel == 2, "a level above the new top comes down to it")
        #expect(s.visibleTileCount(atLevel: 2) == 5, "nothing stranded above every level")
    }

    @Test func theLevelIsNotContent() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        let before = s.contentHash
        s.setRevealLevel(1)
        #expect(s.contentHash == before)
        s.setRevealLevelCount(4)
        #expect(s.contentHash != before, "the level count is content")
    }

    @Test func aSceneWithoutLevelsKeepsItsHash() {
        let context = TestStore.freshContainer().mainContext
        let s = BlasterScene(name: "Plain", descriptionText: "", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]
        context.insert(s)
        let before = s.contentHash
        s.revealLevel = 2
        #expect(s.contentHash == before)
    }

    // MARK: - The bundled board

    @Test func theBundledBoardShipsFourLevelsOpeningAtTheTop() {
        let s = BootstrapLoader.loadDefaultVocabulary(context: TestStore.freshContainer().mainContext).scene
        #expect(s.revealLevelCount == 4)
        #expect(s.effectiveRevealLevel == 4, "an update must not hide a word anyone had")
        let home = s.pages(atLevel: 1).first { $0.key == s.homePageKey }!
        let shown = home.tiles.filter { !$0.isEmptyCell }.map(\.key)
        #expect(Set(shown) == ["i", "you", "want", "more", "help", "stop", "go", "yes", "no",
                               "all_done", "eat", "drink", "play"])
        #expect(s.visibleTileCount(atLevel: 1) < s.visibleTileCount(atLevel: 2))
        #expect(s.visibleTileCount(atLevel: 3) < s.visibleTileCount(atLevel: 4))
    }

    @Test func aBundleUpdateKeepsTheCaregiversLevel() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        s.revealLevel = 2
        s.applyLevelDeclaration(count: 4, initial: 4)
        #expect(s.revealLevel == 2, "the bundle's level is for new installs only")
        s.applyLevelDeclaration(count: 1, initial: 1)
        #expect(s.revealLevel == 1, "a level past the new top comes down to it")
        s.applyLevelDeclaration(count: 0, initial: nil)
        #expect(s.revealLevel == 0 && s.effectiveRevealLevel == nil)
    }

    @Test func aBoardGainingLevelsStartsAtTheSourcesLevel() {
        let context = TestStore.freshContainer().mainContext
        let s = BlasterScene(name: "Plain", descriptionText: "", homePageKey: "home")
        context.insert(s)
        s.applyLevelDeclaration(count: 4, initial: 2)
        #expect(s.revealLevel == 2)
        let t = BlasterScene(name: "Plain", descriptionText: "", homePageKey: "home")
        context.insert(t)
        t.applyLevelDeclaration(count: 4, initial: nil)
        #expect(t.revealLevel == 4, "no level in the source: the top")
    }

    // MARK: - The DSL

    private func materialize(_ json: String) throws -> SceneMaterializer.MaterializedScene {
        let scene = try JSONDecoder().decode(SceneJSON.self, from: Data(json.utf8))
        let vocab = ["want", "more", "juice", "stop"].map {
            TileModelCodable(key: $0, wordClass: "core")
        }
        return try SceneMaterializer.materialize(scene: scene, vocabulary: vocab)
    }

    @Test func levelCommandsStampPlacements() throws {
        let m = try materialize("""
        {"key":"t","name":"T","homePageKey":"home","isDefault":false,
         "revealLevels":3,"revealLevel":2,
         "pages":[{"key":"home","tiles":[
           {"keys":["want","more","juice"]},{"space":1},
           {"level":1,"words":["want"]},{"level":3,"rest":true}]}]}
        """)
        #expect(m.revealLevelCount == 3 && m.revealLevel == 2)
        #expect(m.pages[0].tiles.map(\.revealLevel) == [1, 3, 3, 0], "rest skips the gap")
    }

    @Test func aLevelForAnUnplacedWordIsAnError() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            try materialize("""
            {"key":"t","name":"T","homePageKey":"home","isDefault":false,"revealLevels":2,
             "pages":[{"key":"home","tiles":[{"keys":["want"]},{"level":2,"words":["stop"]}]}]}
            """)
        }
    }

    @Test func aLevelOutsideTheSceneIsAnError() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            try materialize("""
            {"key":"t","name":"T","homePageKey":"home","isDefault":false,"revealLevels":2,
             "pages":[{"key":"home","tiles":[{"keys":["want"]},{"level":3,"rest":true}]}]}
            """)
        }
    }

    // MARK: - Sharing

    /// The file carries every level and opens where the sharer's child is.
    @Test func shareCarriesLevelsAndOpensAtTheSharersLevel() throws {
        let words = ["want", "more", "juice", "page_food", "stop", "apple"]
        let sourceContext = TestStore.freshContainer().mainContext
        let source = leveledScene(in: sourceContext)
        source.revealLevel = 2
        let lookup = Dictionary(uniqueKeysWithValues: words.map {
            ($0, TileModel(key: $0, value: $0, wordClass: "core"))
        })
        let data = try SceneExporter.exportJSON(source, defaultTileKeys: Set(words),
                                                tileLookup: lookup)

        let target = TestStore.freshContainer().mainContext
        insertWords(words, in: target)
        let imported = try SceneImporter.importJSON(data, context: target).scene
        #expect(imported.revealLevelCount == 3)
        #expect(imported.revealLevel == 2)
        #expect(imported.pages[0].tiles.map(\.revealLevel) == [0, 2, 3, 3, 0, 0])
    }

    /// A quiet refresh keeps the receiver's level; "Replace Mine" takes the
    /// file's, because the receiver asked for the file.
    @Test func replaceMineTakesTheFilesLevel() throws {
        let words = ["want", "more", "juice", "page_food", "stop", "apple"]
        let context = TestStore.freshContainer().mainContext
        insertWords(words, in: context)
        let lookup = Dictionary(uniqueKeysWithValues: words.map {
            ($0, TileModel(key: $0, value: $0, wordClass: "core"))
        })
        let source = leveledScene(in: context)
        source.ensureIdentity(authorID: "a", authorName: "A")
        let data = try SceneExporter.exportJSON(source, defaultTileKeys: Set(words),
                                                tileLookup: lookup, level: 1)
        source.setRevealLevel(3)
        // Never imported, so it counts as edited and the importer would prompt.
        #expect(SceneImporter.conflict(for: data, context: context) != .none)

        let kept = try SceneImporter.importJSON(data, context: context, resolution: .keepMine).scene
        #expect(kept.revealLevel == 3)
        let replaced = try SceneImporter.importJSON(data, context: context, resolution: .takeUpdate).scene
        #expect(replaced.persistentModelID == source.persistentModelID)
        #expect(replaced.revealLevel == 1)

        // Now unedited: a quiet refresh keeps whatever the caregiver set.
        replaced.setRevealLevel(2)
        let refreshed = try SceneImporter.importJSON(data, context: context).scene
        #expect(refreshed.revealLevel == 2)
    }

    /// The sharer can pick the level the file opens at, apart from their own.
    @Test func shareAtAChosenLevel() throws {
        let source = leveledScene(in: TestStore.freshContainer().mainContext)
        source.revealLevel = 3
        let exported = SceneExporter.export(source, tileLookup: [:], level: 1)
        #expect(exported.revealLevels == 3 && exported.revealLevel == 1)
        #expect(source.revealLevel == 3, "sharing never moves the sharer's board")
        #expect(SceneExporter.export(source, tileLookup: [:], level: 9).revealLevel == 3)
        #expect(SceneExporter.export(source, tileLookup: [:]).revealLevel == 3, "nil: current")
    }

    @Test func aSceneWithoutLevelsSharesNoLevelKeys() throws {
        let context = TestStore.freshContainer().mainContext
        let s = BlasterScene(name: "Plain", descriptionText: "", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]
        context.insert(s)
        let text = String(decoding: try SceneExporter.exportJSON(s, tileLookup: [:]), as: UTF8.self)
        #expect(!text.contains("revealLevel"))
    }

    @Test func cloneAndDuplicateCarryLevels() {
        let context = TestStore.freshContainer().mainContext
        let source = leveledScene(in: context)
        source.revealLevel = 2
        for copy in [BlasterScene.cloneForEditing(source, in: context, authorID: "a", authorName: "A"),
                     BlasterScene.duplicate(of: source, in: context, authorID: "a", authorName: "A")] {
            #expect(copy.revealLevelCount == 3 && copy.revealLevel == 2)
            #expect(copy.pages[0].tiles.map(\.revealLevel) == [0, 2, 3, 3, 0, 0])
        }
    }

    // MARK: - Reachability

    /// A folder above the level is an empty cell, not a way in.
    @Test func aHiddenFolderIsNotARoute() {
        let s = leveledScene(in: TestStore.freshContainer().mainContext)
        #expect(WordPlaces.routesFromHome(pages: s.pages(atLevel: 3), homeKey: "home")["food"] != nil)
        #expect(WordPlaces.routesFromHome(pages: s.pages(atLevel: 2), homeKey: "home")["food"] == nil)
    }
}
}
