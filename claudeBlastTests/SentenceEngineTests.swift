// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceEngineTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SentenceEngineTests {

    private func makeTestContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    // MARK: - SentencePromptBuilder

    @Test func promptBuilderIncludesGradeLevel() {
        let builder = SentencePromptBuilder(ageGradeLevel: 2)
        let prompt = builder.buildSystemPrompt()
        #expect(prompt.contains(where: { $0.content.contains("2nd-grade") }))
    }

    @Test func promptBuilderHonorsExplicitGradeLevel() {
        // Catch silent regression to the old hardcoded grade default.
        let builder = SentencePromptBuilder(ageGradeLevel: 5)
        let prompt = builder.buildSystemPrompt()
        #expect(prompt.contains(where: { $0.content.contains("5th-grade") }))
        #expect(!prompt.contains(where: { $0.content.contains("2nd-grade") }))
    }

    @Test func promptBuilderIncludesRepetition() {
        var builder = SentencePromptBuilder(ageGradeLevel: 2)
        builder.repetitionCount = 2
        let prompt = builder.buildSystemPrompt()
        #expect(prompt.contains(where: { $0.content.contains("repeat #2") }))
        #expect(prompt.contains(where: { $0.content.contains("insistent") }))
        #expect(prompt.contains(where: { $0.content.contains("escalate") }))
    }

    @Test func promptBuilderFormatsUserPrompt() {
        let builder = SentencePromptBuilder(ageGradeLevel: 2)
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]
        let prompt = builder.formatUserPrompt(tiles: tiles)
        #expect(prompt == "eat (actions), pizza (food)")
    }

    // MARK: - SentenceCacheManager

    @Test func cacheLookupMiss() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]
        let result = cache.lookup(tiles: tiles, grade: 2)
        #expect(result == nil)
    }

    @Test func cacheStoreAndHit() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]

        cache.store(tiles: tiles, grade: 2, sentence: "I want pizza!")
        let hit = cache.lookup(tiles: tiles, grade: 2)
        #expect(hit != nil)
        #expect(hit?.sentence == "I want pizza!")
        #expect(hit?.hitCount == 1)
    }

    @Test func cacheHitCountIncrements() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]

        cache.store(tiles: tiles, grade: 2, sentence: "I want to eat!")
        _ = cache.lookup(tiles: tiles, grade: 2)
        let second = cache.lookup(tiles: tiles, grade: 2)
        #expect(second?.hitCount == 2)
    }

    @Test func cacheUpsertUpdates() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]

        cache.store(tiles: tiles, grade: 2, sentence: "Original")
        cache.store(tiles: tiles, grade: 2, sentence: "Updated")

        let hit = cache.lookup(tiles: tiles, grade: 2)
        #expect(hit?.sentence == "Updated")
    }

    @Test func cacheFlushAll() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles1 = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]
        let tiles2 = [TileSelection(key: "drink", value: "drink", wordClass: "actions")]

        cache.store(tiles: tiles1, grade: 2, sentence: "I want to eat!")
        cache.store(tiles: tiles2, grade: 2, sentence: "I want to drink!")
        #expect(cache.allEntries().count == 2)

        cache.flushAll()
        #expect(cache.allEntries().count == 0)
    }

    @Test func cacheKeyIsOrderIndependent() throws {
        let tilesA = [
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
        ]
        let tilesB = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]
        #expect(SentenceCacheManager.cacheKey(for: tilesA, grade: 2) == SentenceCacheManager.cacheKey(for: tilesB, grade: 2))
    }

    // MARK: - MockSentenceProvider

    @Test func mockProviderCannedResponse() async throws {
        let mock = MockSentenceProvider(minLatency: 0, maxLatency: 0)
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "mom", value: "mom", wordClass: "people"),
        ]
        let result = try await mock.generateSentence(
            tiles: tiles, systemPrompt: [], conversationContext: []
        )
        #expect(result.text == "Mom, I want to eat something!")
    }

    @Test func mockProviderFallbackResponse() async throws {
        let mock = MockSentenceProvider(minLatency: 0, maxLatency: 0)
        let tiles = [
            TileSelection(key: "run", value: "run", wordClass: "actions"),
            TileSelection(key: "fast", value: "fast", wordClass: "describe"),
        ]
        let result = try await mock.generateSentence(
            tiles: tiles, systemPrompt: [], conversationContext: []
        )
        #expect(result.text.contains("run"))
        #expect(result.text.contains("fast"))
    }

    // MARK: - SentenceEngine

    @Test func singleTileDoesNotKickGeneration() throws {
        // Single-tile preview is now derived in the tray view from activeGroup.tiles, so the
        // engine no longer sets activeGroup.sentence for a single tile and never enters the
        // waiting/thinking/idle-nudge states until a 2nd tile lands.
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        let tile = TileModel(key: "happy", wordClass: "describe")
        engine.addTile(tile)

        #expect(engine.selectedTiles.count == 1)
        #expect(engine.generatedSentence == nil)
        #expect(!engine.isThinking)
        #expect(!engine.isWaiting)
        #expect(!engine.isIdleNudge)
    }

    @Test func clearResetsAllState() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "happy", wordClass: "describe"))
        engine.clearSelection()

        #expect(engine.selectedTiles.isEmpty)
        #expect(engine.generatedSentence == nil)
        #expect(!engine.isThinking)
        #expect(!engine.isWaiting)
    }

    @Test func maxTilesEnforced() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        for i in 0..<5 {
            engine.addTile(TileModel(key: "tile\(i)", wordClass: "actions"))
        }

        #expect(engine.selectedTiles.count == 4)
    }

    @Test func multipleTilesDoNotAutoGenerate() throws {
        // Pre-cap: idle no longer fires generation automatically. After the idle wait, the engine
        // sets isIdleNudge so the tray pulses the play button — the user explicitly fires Go.
        // Right after the 2nd tile lands (synchronously), neither state has been entered yet.
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))

        #expect(engine.selectedTiles.count == 2)
        #expect(!engine.isWaiting)
        #expect(!engine.isThinking)
        #expect(engine.generatedSentence == nil)
    }

    @Test func removeTileAtValidIndex() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))
        engine.removeTile(at: 0)

        #expect(engine.selectedTiles.count == 1)
        #expect(engine.selectedTiles[0].key == "pizza")
    }

    @Test func removingLastTileClears() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.removeTile(at: 0)

        #expect(engine.selectedTiles.isEmpty)
        #expect(engine.generatedSentence == nil)
    }

    @Test func tileSelectionEquality() {
        let a = TileSelection(key: "eat", value: "eat", wordClass: "actions")
        let b = TileSelection(key: "eat", value: "eat", wordClass: "actions")
        let c = TileSelection(key: "pizza", value: "pizza", wordClass: "food")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Caregiver refinement (hand-type / suppress)

    @Test func handTypeActiveWritesDurableOverride() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)
        engine.addTile(TileModel(key: "mom", wordClass: "people"))
        engine.addTile(TileModel(key: "juice", wordClass: "drinks"))

        engine.handTypeActive("Mom, may I have juice please?")
        #expect(engine.generatedSentence == "Mom, may I have juice please?")

        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let overrides = cache.allEntries().filter(\.isOverride)
        #expect(overrides.count == 1)
        #expect(overrides.first?.sentence == "Mom, may I have juice please?")
        #expect(overrides.first?.isCaregiverEdited == true)
        #expect(overrides.first?.isPinned == true)
    }

    @Test func suppressActiveBlocksAndFlags() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)
        engine.addTile(TileModel(key: "no", wordClass: "social"))
        engine.addTile(TileModel(key: "go", wordClass: "actions"))

        engine.suppressActive()
        #expect(engine.generatedSentence == nil)      // blocked sentence cleared
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let suppressed = cache.allEntries().filter(\.isSuppressed)
        #expect(suppressed.count == 1)
        #expect(suppressed.first?.isPinned == true)
    }

    @Test func suppressRemovesMatchingHistoryGroup() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)
        // Build + commit a group so it lands in history (Done flushes the tile
        // values as the sentence when none was generated).
        engine.addTile(TileModel(key: "i", wordClass: "core"))
        engine.addTile(TileModel(key: "all_done", wordClass: "core"))
        engine.commitActiveAndStartNew()
        #expect(engine.groupHistory.count == 1)

        // Re-select the same set and suppress it — the history bubble must go.
        engine.addTile(TileModel(key: "i", wordClass: "core"))
        engine.addTile(TileModel(key: "all_done", wordClass: "core"))
        engine.suppressActive()
        #expect(engine.groupHistory.isEmpty)
    }

    @Test func reopenHistoryGroupHonorsHandTypedOverride() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)
        engine.addTile(TileModel(key: "sister", wordClass: "people"))
        engine.addTile(TileModel(key: "toilet", wordClass: "body"))
        engine.commitActiveAndStartNew()   // stored snapshot = "sister toilet"
        let groupID = try #require(engine.groupHistory.first?.id)

        // Caregiver hand-types a correction for this combination.
        engine.addTile(TileModel(key: "sister", wordClass: "people"))
        engine.addTile(TileModel(key: "toilet", wordClass: "body"))
        engine.handTypeActive("My sister needs to use the bathroom.")
        engine.commitActiveAndStartNew()

        // Replaying the ORIGINAL history bubble must serve the override, not the
        // stale stored snapshot.
        engine.reopenHistoryGroup(id: groupID)
        #expect(engine.activeGroup.sentence == "My sister needs to use the bathroom.")
    }
}
}
