// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  InteractionModeTests.swift
//  claudeBlastTests
//
//  Covers single-word (classic AAC) mode and the universal "grid tap adds,
//  never deletes" rule introduced alongside it.

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct InteractionModeTests {

    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    /// Run `body` with an engine wired to a resolver whose active profile uses
    /// `mode`. The container is held alive for the whole closure — returning the
    /// engine alone would deallocate the container and orphan the profile, and
    /// reading a SwiftData property on an orphaned model traps.
    private func withEngine(mode: InteractionMode,
                            _ body: (SentenceEngine) throws -> Void) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Interaction mode is no longer stored — it is a projection of the
        // child's Brown's Stage. Stage I is single words; Stage IV+ builds
        // sentences with room for the multi-tile cases below.
        let profile = ChildProfile(displayName: "Test",
                                   brownsStage: mode == .singleWord ? .one : .fourPlus,
                                   isActive: true)
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        try body(engine)
        withExtendedLifetime(container) {}
    }

    // MARK: - Model

    /// Mode is derived from the stage, not stored. Stage I *is* single-word
    /// mode; every later stage builds sentences.
    @Test func interactionModeIsDerivedFromStage() {
        let p = ChildProfile(displayName: "A")
        #expect(p.brownsStage == .one)          // default
        #expect(p.interactionMode == .singleWord)

        p.brownsStage = .twoThree
        #expect(p.interactionMode == .sentence)

        p.brownsStage = .fourPlus
        #expect(p.interactionMode == .sentence)
    }

    /// An unknown raw value falls back to Stage I rather than to sentences.
    /// That is the safe direction: a child shown one word at a time is
    /// under-served, whereas one handed sentences they cannot parse is being
    /// spoken *for* rather than *with*.
    @Test func unknownStageRawFallsBackToStageOne() {
        let p = ChildProfile(displayName: "A")
        p.brownsStageRaw = "somethingFuture"
        #expect(p.brownsStage == .one)
        #expect(p.interactionMode == .singleWord)
    }

    /// The stage pins the tile cap at I and II-III, and only leaves a choice
    /// at IV+.
    @Test func stageConstrainsTileCap() {
        let p = ChildProfile(displayName: "A", brownsStage: .one)
        #expect(p.effectiveTileCap == 1)

        p.brownsStage = .twoThree
        #expect(p.effectiveTileCap == 4)

        p.brownsStage = .fourPlus
        p.setTileCap(6)
        #expect(p.effectiveTileCap == 6)
    }

    /// Widening past four tiles promotes the stage instead of being clamped —
    /// a caregiver who does that is telling us the child combines more words.
    @Test func wideningTileCapPromotesStage() {
        let p = ChildProfile(displayName: "A", brownsStage: .twoThree)
        p.setTileCap(6)
        #expect(p.brownsStage == .fourPlus)
        #expect(p.effectiveTileCap == 6)
        #expect(p.interactionMode == .sentence)
    }

    /// And narrowing to a single tile is Stage I, mode included.
    @Test func narrowingTileCapDemotesToStageOne() {
        let p = ChildProfile(displayName: "A", brownsStage: .fourPlus, maxSelectedTiles: 7)
        p.setTileCap(1)
        #expect(p.brownsStage == .one)
        #expect(p.interactionMode == .singleWord)
    }

    // MARK: - Device-local single-word override

    /// The caregiver-menu override changes this device without touching the
    /// child's stage — the whole point of moving it off the synced profile.
    /// See `DeviceProfile.modeOverrideRaw`.
    @Test func deviceOverrideForcesSingleWordsWithoutChangingStage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus,
                                   maxSelectedTiles: 6, isActive: true)
        ctx.insert(profile)
        try? ctx.save()

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(resolver.interactionMode == .sentence)
        #expect(resolver.maxSelectedTiles == 6)

        resolver.requestMode(.singleWord)
        #expect(resolver.interactionMode == .singleWord)
        #expect(resolver.maxSelectedTiles == 1)
        // The child's clinical record is untouched.
        #expect(profile.brownsStage == .fourPlus)
        #expect(profile.effectiveTileCap == 6)

        resolver.requestMode(.sentence)
        #expect(resolver.interactionMode == .sentence)
        #expect(resolver.maxSelectedTiles == 6)
        // Asking for what the stage already implies clears the override rather
        // than pinning a redundant one.
        #expect(resolver.modeOverride == nil)

        withExtendedLifetime(container) {}
    }

    /// The override works in **both** directions. A Stage I child already
    /// resolves to single words, so an override that could only force single
    /// words *on* left the caregiver menu's toggle a no-op in exactly the
    /// default configuration — which is how it shipped broken the first time.
    @Test func deviceOverrideCanForceSentencesForAStageOneChild() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .one, isActive: true)
        ctx.insert(profile)
        try? ctx.save()

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(resolver.interactionMode == .singleWord)

        resolver.requestMode(.sentence)
        #expect(resolver.interactionMode == .sentence)
        #expect(resolver.maxSelectedTiles >= 2)   // one tile cannot make a sentence
        #expect(profile.brownsStage == .one)      // stage untouched

        resolver.requestMode(.singleWord)
        #expect(resolver.interactionMode == .singleWord)
        #expect(resolver.modeOverride == nil)     // back to following the stage

        withExtendedLifetime(container) {}
    }

    /// The override is device-local and survives a resolver rebuild, which is
    /// what "persists until changed back" means in practice.
    @Test func deviceOverridePersistsAcrossResolverRebuild() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(ChildProfile(displayName: "Test", brownsStage: .twoThree, isActive: true))
        try? ctx.save()

        let first = ChildProfileResolver()
        first.configure(modelContext: ctx)
        first.requestMode(.singleWord)

        let second = ChildProfileResolver()
        second.configure(modelContext: ctx)
        #expect(second.modeOverride == .singleWord)
        #expect(second.interactionMode == .singleWord)

        withExtendedLifetime(container) {}
    }

    // MARK: - Universal: grid tap adds, never deletes (sentence mode)

    @Test func sentenceMode_reTapIsNoOp_notToggleOff() throws {
        try withEngine(mode: .sentence) { engine in
            let dad = TileModel(key: "dad", wordClass: "people")
            engine.addTile(dad)
            engine.addTile(dad) // re-tap: no toggle-off, no duplicate
            #expect(engine.selectedTiles.count == 1)
            #expect(engine.selectedTiles[0].key == "dad")
        }
    }

    // MARK: - Single-word mode

    @Test func singleWordMode_appendsToStrip_notGroup() throws {
        try withEngine(mode: .singleWord) { engine in
            engine.addTile(TileModel(key: "dad", wordClass: "people"))
            #expect(engine.spokenStrip.count == 1)
            #expect(engine.selectedTiles.isEmpty) // no sentence group
            #expect(engine.generatedSentence == nil)
        }
    }

    @Test func singleWordMode_allowsDuplicates() throws {
        try withEngine(mode: .singleWord) { engine in
            let dad = TileModel(key: "dad", wordClass: "people")
            let mom = TileModel(key: "mom", wordClass: "people")
            // Single-word mode allows the same word to appear again — but only
            // NON-consecutively. Consecutive re-taps intentionally mash-to-escalate
            // (bump the escalation counter, no new strip tile — see
            // SentenceEngine.appendSpokenWord), so dad→mom→dad yields a 3-tile
            // strip with "dad" twice, while dad→dad→dad would yield one tile.
            engine.addTile(dad)
            engine.addTile(mom)
            engine.addTile(dad)
            #expect(engine.spokenStrip.map(\.key) == ["dad", "mom", "dad"])
        }
    }

    @Test func singleWordMode_stripRollsAtCap() throws {
        try withEngine(mode: .singleWord) { engine in
            for i in 0..<25 {
                engine.addTile(TileModel(key: "w\(i)", wordClass: "actions"))
            }
            // Capped at 20; oldest dropped off the left, newest retained.
            #expect(engine.spokenStrip.count == 20)
            #expect(engine.spokenStrip.first?.key == "w5")
            #expect(engine.spokenStrip.last?.key == "w24")
        }
    }

    @Test func singleWordMode_removeAndClear() throws {
        try withEngine(mode: .singleWord) { engine in
            engine.addTile(TileModel(key: "a", wordClass: "actions"))
            engine.addTile(TileModel(key: "b", wordClass: "actions"))
            engine.removeStripWord(at: 0)
            #expect(engine.spokenStrip.map(\.key) == ["b"])
            engine.clearStrip()
            #expect(engine.spokenStrip.isEmpty)
        }
    }

    // MARK: - Escalation accounting

    /// Regression: escalation depth must reach the flushed group (and the logged
    /// utterance). Previously the flush logged the TileGroup's own repetitionCount
    /// (never updated) instead of the engine's live counter, so every utterance
    /// recorded 0 escalations.
    @Test func escalationDepthIsLoggedOnCommit() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Default profile is .sentence mode.
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))
        engine.triggerGo()
        try await waitUntil { engine.canReplay }
        engine.replay()
        try await waitUntil { !engine.isThinking }
        engine.replay()
        try await waitUntil { !engine.isThinking }

        #expect(engine.repetitionCount == 2)
        engine.commitActiveAndStartNew()
        #expect(engine.groupHistory.first?.repetitionCount == 2)

        let logged = try ctx.fetch(FetchDescriptor<LoggedUtterance>())
        #expect(logged.contains { $0.repetitionCount == 2 })
        withExtendedLifetime(container) {}
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout {
                Issue.record("waitUntil timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
}
