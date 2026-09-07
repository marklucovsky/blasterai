// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ImportWarningTests.swift
//  claudeBlastTests
//
//  Load whatever we can, and make sure both sides know what is wrong with it.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ImportWarningTests {

    /// The same shape `tools/make_damaged_scenes.py` writes, so the fixtures a
    /// person imports by hand and the ones asserted on here cannot drift.
    private func sceneJSON(home: String = "home",
                           pages: [[String: Any]]) -> Data {
        let body: [String: Any] = [
            "@type": BlasterSceneFormat.mediaType,
            "version": "1.0.0",
            "name": "Fixture",
            "description": "",
            "homePageKey": home,
            "pages": pages,
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func tile(_ key: String, concealed: Bool? = nil) -> [String: Any] {
        var entry: [String: Any] = ["key": key, "isAudible": true, "link": ""]
        if let concealed { entry["isConcealed"] = concealed }
        return entry
    }

    private func seedVocabulary(_ context: ModelContext) {
        for key in ["eat", "drink", "more"] {
            context.insert(TileModel(key: key, wordClass: "actions"))
        }
    }

    // MARK: - What the import reports

    /// The fixture run found this: a board of nothing but gaps imports happily
    /// and lands the child on an empty page. Survivable — `homeCell` is drawn by
    /// the grid, not by page data, so Home is still there and Admin is still
    /// reachable — but the caregiver has to be told.
    @Test("A board with nothing pressable warns on import")
    func nothingPressableWarnsAtImport() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [
            tile("<spacer>#aaaaaaaa"), tile("<spacer>#bbbbbbbb"),
        ]]])
        let result = try SceneImporter.importJSON(data, context: context)

        #expect(result.warnings.contains(.noReachableWords))
    }

    /// Concealed is not deleted: the words are still on the page, still in
    /// order, and the caregiver reveals them when ready. That is the whole
    /// reveal workflow, so this warns and must never refuse.
    @Test("A wholly concealed board imports, and warns")
    func whollyConcealedImportsAndWarns() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [
            tile("eat", concealed: true), tile("drink", concealed: true),
        ]]])
        let result = try SceneImporter.importJSON(data, context: context)

        #expect(result.warnings.contains(.noReachableWords))
        #expect(result.scene.pages.first?.tiles.count == 2, "concealed tiles must survive the trip")
    }

    /// A healthy file must not acquire a warning, or the banner cries wolf and
    /// the caregiver stops reading it.
    @Test("A healthy scene imports clean")
    func healthySceneImportsClean() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [tile("eat"), tile("drink")]]])
        let result = try SceneImporter.importJSON(data, context: context)

        #expect(result.warnings.isEmpty)
        #expect(result.skippedKeys.isEmpty)
    }

    /// Words the device does not have are dropped and named. Checked here
    /// because the fixture run showed the *activation* warning never fires for
    /// an imported scene — the importer has already removed them by then, so
    /// this is the only layer that can report it.
    @Test("Unknown words are dropped and named, not imported blindly")
    func unknownWordsAreNamed() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [
            tile("eat"), tile("zzz_not_a_word"),
        ]]])
        let result = try SceneImporter.importJSON(data, context: context)

        #expect(result.skippedKeys == ["zzz_not_a_word"])
        #expect(result.scene.pages.first?.tiles.map(\.key) == ["eat"])
    }

    /// A gap names no word, so it must not be reported as one — the caregiver
    /// would be hunting for a missing word that never existed.
    @Test("Spacers are not reported as missing words")
    func spacersAreNotMissingWords() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [
            tile("eat"), tile("<spacer>#aaaaaaaa"),
        ]]])
        let result = try SceneImporter.importJSON(data, context: context)

        #expect(result.skippedKeys.isEmpty)
    }

    // MARK: - Undo

    @Test("Undo removes the scene the import created")
    func undoRemovesTheScene() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        let data = sceneJSON(pages: [["key": "home", "tiles": [tile("eat")]]])
        let result = try SceneImporter.importJSON(data, context: context)
        #expect(result.isUndoable)

        try SceneImporter.undo(result, context: context)

        let scenes = try context.fetch(FetchDescriptor<BlasterScene>())
        #expect(scenes.isEmpty)
    }

    /// An undo that leaves the vocabulary behind is a half-undo: those words sit
    /// in the caregiver's word list with nothing pointing at them, and they have
    /// no way to tell where they came from.
    @Test("Undo takes the words the import created with it")
    func undoRemovesNewWords() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        var body = try JSONSerialization.jsonObject(
            with: sceneJSON(pages: [["key": "home", "tiles": [tile("eat"), tile("brontosaurus")]]])
        ) as! [String: Any]
        body["tiles"] = [["key": "brontosaurus", "wordClass": "animal", "displayName": "brontosaurus"]]
        let data = try JSONSerialization.data(withJSONObject: body)

        let result = try SceneImporter.importJSON(data, context: context)
        #expect(result.newTileKeys == ["brontosaurus"])

        try SceneImporter.undo(result, context: context)

        let keys = try context.fetch(FetchDescriptor<TileModel>()).map(\.key)
        #expect(!keys.contains("brontosaurus"))
        // …and only those. The device's own vocabulary is untouched.
        #expect(Set(keys) == ["eat", "drink", "more"])
    }

    /// On an update the incoming content has already replaced what was there.
    /// Deleting the scene would take the caregiver's own board with it, and
    /// nothing here can put the old version back — so undo must decline.
    @Test("Undo declines an update, which it cannot reverse")
    func undoDeclinesAnUpdate() throws {
        let context = TestStore.freshContainer().mainContext
        seedVocabulary(context)

        var body = try JSONSerialization.jsonObject(
            with: sceneJSON(pages: [["key": "home", "tiles": [tile("eat")]]])
        ) as! [String: Any]
        body["id"] = "fixture-scene-id"
        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try SceneImporter.importJSON(data, context: context)
        let second = try SceneImporter.importJSON(data, context: context)

        #expect(second.wasUpdate)
        #expect(!second.isUndoable)

        try SceneImporter.undo(second, context: context)
        let scenes = try context.fetch(FetchDescriptor<BlasterScene>())
        #expect(scenes.count == 1, "undo must not delete a scene it cannot restore")
    }
}
}
