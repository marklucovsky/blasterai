// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneIdentityTests.swift
//  claudeBlastTests
//
//  Decentralized scene identity: slug/id, resolver ladder, author identity,
//  import dedupe, and the modified-scene import-conflict semantics
//  (keep mine / take update / keep both).
//
//  Every BlasterScene is created inside a ModelContext — SwiftData aborts the
//  process if @Model instances are built container-less. Suite is serialized
//  so the in-memory containers aren't created concurrently.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
@Suite(.serialized)
struct SceneIdentityTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TileModel.self, SentenceCache.self, BlasterScene.self, MetricEvent.self,
            RecordedScript.self, DeviceProfile.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config]).mainContext
    }

    /// Create + insert a scene (never container-less).
    @discardableResult
    private func scene(_ ctx: ModelContext, _ name: String,
                       isDefault: Bool = false, isActive: Bool = false) -> BlasterScene {
        let s = BlasterScene(name: name, isDefault: isDefault, isActive: isActive)
        ctx.insert(s)
        return s
    }

    /// Build a `.blasterscene` JSON payload with optional identity fields.
    private func importData(id: String?, name: String, author: String? = nil,
                            home: String = "home", tiles: [String],
                            sceneVersion: String = "1.0.0") -> Data {
        var fields = """
          "@type": "application/vnd.claudeblast.scene+json",
          "version": "1.0.0",
          "name": "\(name)",
          "description": "",
          "homePageKey": "\(home)"
        """
        if let id {
            fields += ",\n  \"id\": \"\(id)\",\n  \"slug\": \"\(SceneIdentity.slug(from: name))\",\n  \"sceneVersion\": \"\(sceneVersion)\""
        }
        if let author { fields += ",\n  \"authorName\": \"\(author)\"" }
        let tilesJSON = tiles.map { "{ \"key\": \"\($0)\", \"isAudible\": true, \"link\": \"\" }" }
            .joined(separator: ",")
        return "{\n\(fields),\n  \"pages\": [{ \"key\": \"\(home)\", \"tiles\": [\(tilesJSON)] }]\n}"
            .data(using: .utf8)!
    }

    private func seedTiles(_ ctx: ModelContext, _ keys: String...) {
        for k in keys { ctx.insert(TileModel(key: k, wordClass: "actions")) }
    }

    private func sceneCount(_ ctx: ModelContext) -> Int {
        (try? ctx.fetch(FetchDescriptor<BlasterScene>()))?.count ?? 0
    }

    // MARK: - SceneIdentity slug/id (pure)

    @Test func slugKebabsAndCollapses() {
        #expect(SceneIdentity.slug(from: "Potty Training") == "potty-training")
        #expect(SceneIdentity.slug(from: "  Hello,  World!! ") == "hello-world")
        #expect(SceneIdentity.slug(from: "123 ABC") == "123-abc")
        #expect(SceneIdentity.slug(from: "") == "scene")
        #expect(SceneIdentity.slug(from: "!!!") == "scene")
    }

    @Test func idComposition() {
        #expect(SceneIdentity.id(authority: "abc", slug: "vocab") == "abc/vocab")
    }

    // MARK: - Scene stamping

    @Test func ensureIdentityIsIdempotent() throws {
        let ctx = try makeContext()
        let s = scene(ctx, "Potty Training")
        s.ensureIdentity(authorID: "greta", authorName: "Greta")
        #expect(s.sceneID == "greta/potty-training")
        #expect(s.slug == "potty-training")
        #expect(s.sceneVersion == "1.0.0")
        #expect(s.authorName == "Greta")
        s.ensureIdentity(authorID: "someone-else", authorName: "Nope")
        #expect(s.sceneID == "greta/potty-training")   // no re-stamp
        #expect(s.authorName == "Greta")
    }

    @Test func firstPartyIdentity() throws {
        let ctx = try makeContext()
        let s = scene(ctx, "Core-First")
        s.systemSceneKey = "core_first"
        s.markFirstPartyIdentity()
        #expect(s.sceneID == "scenes.blasterai.app/core_first")
        #expect(s.slug == "core_first")
    }

    @Test func authorDisplayPrefersAuthorThenReceivedLabel() throws {
        let ctx = try makeContext()
        let s = scene(ctx, "X")
        #expect(s.authorDisplay == "")
        s.receivedLabel = "from Greta"
        #expect(s.authorDisplay == "from Greta")
        s.authorName = "Greta"
        #expect(s.authorDisplay == "Greta")
    }

    @Test func scriptReferenceUsesIdThenName() throws {
        let ctx = try makeContext()
        let s = scene(ctx, "Potty Training")
        #expect(s.scriptReference == "Potty Training")
        s.ensureIdentity(authorID: "greta")
        #expect(s.scriptReference == "greta/potty-training")
    }

    @Test func contentHashTracksContent() throws {
        let ctx = try makeContext()
        let s = scene(ctx, "A")
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "x", link: "", isAudible: true)])]
        let h1 = s.contentHash
        s.name = "B"
        #expect(s.contentHash != h1)
        s.name = "A"
        #expect(s.contentHash == h1)
        s.pages = [PageSpec(key: "home", tiles: [])]
        #expect(s.contentHash != h1)
    }

    // MARK: - Resolver ladder

    @Test func resolverLadderIdSlugName() throws {
        let ctx = try makeContext()
        let a = scene(ctx, "Alpha"); a.sceneID = "greta/alpha"; a.slug = "alpha"
        let b = scene(ctx, "Beta");  b.sceneID = "sam/beta";    b.slug = "beta"
        let scenes = [a, b]
        #expect(TileScriptValidator.resolveScene("greta/alpha", in: scenes) === a)  // id
        #expect(TileScriptValidator.resolveScene("beta", in: scenes) === b)         // slug
        #expect(TileScriptValidator.resolveScene("Alpha", in: scenes) === a)        // name
        #expect(TileScriptValidator.resolveScene("nope", in: scenes) == nil)        // miss
    }

    @Test func resolverSentinelsAndNil() throws {
        let ctx = try makeContext()
        let def = scene(ctx, "Empty", isDefault: true)
        let act = scene(ctx, "Active", isActive: true)
        let scenes = [def, act]
        #expect(TileScriptValidator.resolveScene(nil, in: scenes) === act)
        #expect(TileScriptValidator.resolveScene("<default>", in: scenes) === def)
    }

    // MARK: - Author identity

    @Test func authorIDMintedOnceAndStable() throws {
        let ctx = try makeContext()
        let first = DeviceProfileStore.ensureAuthorID(context: ctx)
        #expect(!first.isEmpty)
        #expect(DeviceProfileStore.ensureAuthorID(context: ctx) == first)
    }

    // MARK: - Import: identity carry + dedupe

    @Test func importCarriesIdentityAndFlagsMissingAuthor() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a")
        let result = try SceneImporter.importJSON(
            importData(id: "greta/potty-training", name: "Potty Training", tiles: ["a"]),
            context: ctx)
        #expect(result.scene.sceneID == "greta/potty-training")
        #expect(result.scene.slug == "potty-training")
        #expect(result.scene.authorName == "")
        #expect(result.needsReceiverLabel)
    }

    @Test func reimportSameIdUpdatesInPlaceNoDuplicate() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a", "b")
        _ = try SceneImporter.importJSON(
            importData(id: "greta/pt", name: "Potty", author: "Greta", tiles: ["a"]), context: ctx)
        #expect(sceneCount(ctx) == 1)
        let r2 = try SceneImporter.importJSON(
            importData(id: "greta/pt", name: "Potty v2", author: "Greta",
                       tiles: ["a", "b"], sceneVersion: "1.1.0"), context: ctx)
        #expect(sceneCount(ctx) == 1)                  // refreshed, not duplicated
        #expect(r2.wasUpdate)
        #expect(r2.scene.name == "Potty v2")
        #expect(r2.scene.sceneVersion == "1.1.0")
        #expect(r2.scene.pages[0].tiles.count == 2)
    }

    // MARK: - Import conflict: modified-scene semantics

    /// Import once, then locally edit the copy so it diverges from the baseline.
    private func importThenEdit(_ ctx: ModelContext) throws -> BlasterScene {
        seedTiles(ctx, "a", "b")
        let r = try SceneImporter.importJSON(
            importData(id: "greta/pt", name: "Potty", author: "Greta", tiles: ["a"]), context: ctx)
        r.scene.name = "My Potty (edited)"             // → contentHash diverges
        try ctx.save()
        return r.scene
    }

    @Test func conflictDetectedOnlyWhenModified() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a")
        _ = try SceneImporter.importJSON(
            importData(id: "greta/pt", name: "Potty", author: "Greta", tiles: ["a"]), context: ctx)
        let update = importData(id: "greta/pt", name: "Potty v2", author: "Greta",
                                tiles: ["a"], sceneVersion: "1.1.0")
        #expect(SceneImporter.conflict(for: update, context: ctx) == .none)   // unedited

        let existing = try #require(
            try ctx.fetch(FetchDescriptor<BlasterScene>()).first { $0.sceneID == "greta/pt" })
        existing.name = "Edited"
        try ctx.save()
        #expect(SceneImporter.conflict(for: update, context: ctx) == .modifiedExisting(name: "Edited"))
    }

    @Test func modifiedImportWithNoResolutionReturnsConflictAndDoesNotWrite() throws {
        let ctx = try makeContext()
        let edited = try importThenEdit(ctx)
        let editedName = edited.name
        let update = importData(id: "greta/pt", name: "Potty v2", tiles: ["a", "b"], sceneVersion: "1.1.0")

        let r = try SceneImporter.importJSON(update, context: ctx, resolution: nil)
        #expect(r.conflict == .modifiedExisting(name: editedName))
        #expect(sceneCount(ctx) == 1)
        #expect(edited.name == editedName)             // untouched
    }

    @Test func keepMineLeavesLocalUntouched() throws {
        let ctx = try makeContext()
        let edited = try importThenEdit(ctx)
        let editedName = edited.name
        let update = importData(id: "greta/pt", name: "Potty v2", tiles: ["a", "b"], sceneVersion: "1.1.0")

        let r = try SceneImporter.importJSON(update, context: ctx, resolution: .keepMine)
        #expect(r.conflict == .none)
        #expect(sceneCount(ctx) == 1)
        #expect(edited.name == editedName)
        #expect(edited.pages[0].tiles.count == 1)      // not upgraded
    }

    @Test func takeUpdateOverwritesInPlace() throws {
        let ctx = try makeContext()
        let edited = try importThenEdit(ctx)
        let update = importData(id: "greta/pt", name: "Potty v2", author: "Greta",
                                tiles: ["a", "b"], sceneVersion: "1.1.0")

        let r = try SceneImporter.importJSON(update, context: ctx, resolution: .takeUpdate)
        #expect(r.wasUpdate)
        #expect(sceneCount(ctx) == 1)
        #expect(edited.name == "Potty v2")             // edits replaced
        #expect(edited.pages[0].tiles.count == 2)
        #expect(edited.importedContentHash == edited.contentHash)   // baseline re-stamped
    }

    @Test func keepBothForksANewScene() throws {
        let ctx = try makeContext()
        let edited = try importThenEdit(ctx)
        let editedName = edited.name
        let update = importData(id: "greta/pt", name: "Potty v2", author: "Greta",
                                tiles: ["a", "b"], sceneVersion: "1.1.0")

        let r = try SceneImporter.importJSON(update, context: ctx, resolution: .keepBoth)
        #expect(sceneCount(ctx) == 2)                  // both kept
        #expect(edited.name == editedName)             // my copy preserved
        #expect(r.scene !== edited)                    // fork is new
        #expect(r.scene.name == "Potty v2 (update)")
        #expect(r.scene.sceneID != "greta/pt")         // fresh local id
        #expect(r.scene.sceneID.hasSuffix("/potty-v2-update"))
    }

    // MARK: - Receiver tagging

    @Test func receiverCanTagNamelessImport() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a")
        let r = try SceneImporter.importJSON(
            importData(id: "anon/pt", name: "Potty", tiles: ["a"]), context: ctx)   // no author
        #expect(r.needsReceiverLabel)
        r.scene.receivedLabel = "from Greta"
        #expect(r.scene.authorDisplay == "from Greta")
    }

    @Test func firstPartyImportNeverPromptsForTag() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a")
        let r = try SceneImporter.importJSON(
            importData(id: "scenes.blasterai.app/mealtime", name: "Mealtime", tiles: ["a"]),
            context: ctx)
        #expect(r.scene.isFirstParty)
        #expect(!r.needsReceiverLabel)   // BlasterAI content is never "from someone"
    }

    @Test func refreshOfExistingNeverPromptsForTag() throws {
        let ctx = try makeContext()
        seedTiles(ctx, "a")
        let data = importData(id: "greta/pt", name: "Potty", tiles: ["a"])   // no author
        let first = try SceneImporter.importJSON(data, context: ctx)
        #expect(first.needsReceiverLabel)                 // new, non-first-party, no author
        let second = try SceneImporter.importJSON(data, context: ctx)   // re-import, unmodified
        #expect(second.wasUpdate)
        #expect(!second.needsReceiverLabel)               // refresh, not a new scene → no prompt
    }
}
