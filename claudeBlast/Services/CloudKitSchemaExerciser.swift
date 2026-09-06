// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CloudKitSchemaExerciser.swift
//  claudeBlast
//
//  Force every synced record type and field into the CloudKit Development
//  schema, so promotion has something complete to promote.
//

import Foundation
import SwiftData

/// Writes and then modifies one instance of every synced model, so CloudKit
/// materializes the whole schema.
///
/// ## Why this has to exist
///
/// CloudKit's Development schema is built from what the app has actually
/// **written**, not from what the app declares. A record type nothing has saved
/// does not exist, and `SchemaVersions` is explicit about what that costs:
/// *"a field that never appeared in Development does not exist after
/// promotion."* Production is read-only, so the first device to write an
/// unmaterialized type fails to sync — permanently.
///
/// We hit exactly this. A real device on iCloud showed four of eight record
/// types, because nothing had yet logged an utterance, cached a sentence,
/// recorded a script or received a pack. Reaching the other four by hand took a
/// specific sequence of caregiver actions, several of them non-obvious. Doing
/// that by memory before each promotion is how a type gets missed.
///
/// `retiredReason` is the same trap one level down: a *field* absent from the
/// dev schema purely because nothing had been auto-hidden yet. Hence "and then
/// modifies" — a write followed by an update exercises the same save path a real
/// edit takes, so nothing depends on which properties happen to be touched at
/// insert time.
///
/// ## What it is not
///
/// Not a substitute for using the app. It proves the *schema* is complete; it
/// proves nothing about whether sync works, whether records merge sensibly, or
/// whether the dedup reconciler behaves. `docs/cloudkit-promotion-runbook.md`
/// still governs the ceremony.
///
/// DEBUG only, and it writes obviously-labelled rows that `cleanUp` removes.
#if DEBUG
enum CloudKitSchemaExerciser {

    /// Marks every row this creates, so cleanup can find them and a human
    /// reading the CloudKit dashboard knows what they are looking at.
    static let marker = "__schema_probe__"

    /// The models this exercises, as names.
    ///
    /// Kept as a declared list rather than derived, so `SchemaVersionTests` can
    /// assert it matches `BlasterSchemaV1.syncedModels` exactly. Adding a synced
    /// model without exercising it is precisely the mistake that produces an
    /// unmaterialized record type, and it should fail a test rather than
    /// surface at promotion.
    static let exercised: [String] = [
        "TileModel",
        "TileArtVariant",
        "SentenceCache",
        "BlasterScene",
        "RecordedScript",
        "LoggedUtterance",
        "ChildProfile",
        "ReceivedPack",
    ]

    struct Result {
        var written: [String] = []
        var failed: [String] = []
        var isComplete: Bool { failed.isEmpty && written.count == exercised.count }
    }

    /// Create then modify one row of each synced model.
    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Result {
        var result = Result()

        func step(_ name: String, _ body: () throws -> Void) {
            do {
                try body()
                try context.save()          // create
                result.written.append(name)
            } catch {
                result.failed.append(name)
            }
        }

        // Each block inserts, saves, mutates, and saves again. The second save
        // is the point: an update is the write path a real edit takes.

        step("TileModel") {
            let tile = TileModel(key: "\(marker)_word", wordClass: "object")
            tile.displayName = marker
            context.insert(tile)
            try context.save()
            tile.retiredReason = marker     // a field only ever set on update
            tile.partOfSpeechRaw = PartOfSpeech.noun.rawValue
            tile.needsReview = true
        }

        step("TileArtVariant") {
            TileArtVariant.upsert(tileKey: "\(marker)_word",
                                  imageSet: ImageSetID.defaultSet,
                                  imageData: Data(marker.utf8),
                                  context: context)
            try context.save()
            TileArtVariant.upsert(tileKey: "\(marker)_word",
                                  imageSet: ImageSetID.defaultSet,
                                  imageData: Data("\(marker)2".utf8),
                                  context: context)
        }

        step("SentenceCache") {
            let entry = SentenceCache(
                tiles: [TileSelection(key: "\(marker)_word", value: marker, wordClass: "object")],
                stage: .one,
                sentence: marker)
            context.insert(entry)
            try context.save()
            entry.hitCount += 1
            entry.isPinned = true
            entry.isSuppressed = true
            entry.isCaregiverEdited = true
            entry.caregiverAccepted = true
        }

        step("BlasterScene") {
            let scene = BlasterScene(name: marker, descriptionText: marker, homePageKey: "home")
            scene.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "\(marker)_word")])]
            context.insert(scene)
            try context.save()
            scene.creationSummary = marker
            scene.receivedLabel = marker
            scene.sourceURL = marker
            scene.importedContentHash = marker
            scene.isFocused = true
        }

        step("RecordedScript") {
            let script = RecordedScript(name: marker, descriptionText: marker,
                                        yamlContent: "steps: []", sceneRef: marker)
            context.insert(script)
            try context.save()
            script.descriptionText = "\(marker) updated"
        }

        step("LoggedUtterance") {
            let entry = LoggedUtterance(tileKeys: ["\(marker)_word"], sentence: marker,
                                        repetitionCount: 1, pageKeys: ["home"],
                                        sceneName: marker, sceneID: marker, childID: marker)
            context.insert(entry)
            try context.save()
            entry.repetitionCount += 1
        }

        step("ChildProfile") {
            let profile = ChildProfile(displayName: marker)
            context.insert(profile)
            try context.save()
            profile.notes = marker
            profile.voiceIdentifier = marker
            profile.defaultSceneKey = marker
            profile.ttsRate = 0.5
            profile.ttsVolume = 0.9
        }

        step("ReceivedPack") {
            let pack = ReceivedPack(packID: "\(marker)/probe", slug: marker,
                                    displayName: marker, packVersion: "1.0.0",
                                    authorName: marker,
                                    words: [VocabPackWord(key: "\(marker)_word",
                                                          wordClass: "object",
                                                          displayName: marker)])
            context.insert(pack)
            try context.save()
            pack.packVersion = "1.0.1"
        }

        try? context.save()
        return result
    }

    /// Remove every row `run` created.
    ///
    /// **The schema survives cleanup** — that is the whole trick. CloudKit keeps
    /// a record type and its fields once they have been written, so the probe
    /// rows can go and the schema they created stays.
    @MainActor
    static func cleanUp(context: ModelContext) {
        func purge<T: PersistentModel>(_ type: T.Type, matches: (T) -> Bool) {
            guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
            for row in rows where matches(row) { context.delete(row) }
        }

        purge(TileModel.self) { $0.key.hasPrefix(marker) }
        purge(TileArtVariant.self) { $0.tileKey.hasPrefix(marker) }
        purge(SentenceCache.self) { $0.sentence == marker }
        purge(BlasterScene.self) { $0.name == marker }
        purge(RecordedScript.self) { $0.name == marker }
        purge(LoggedUtterance.self) { $0.sentence == marker }
        purge(ChildProfile.self) { $0.displayName == marker }
        purge(ReceivedPack.self) { $0.slug == marker }
        try? context.save()
    }
}
#endif
