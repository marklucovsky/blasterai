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
        // Sentences are the profile's own setting (`aiMode`). The stage only
        // picks the pictures default: I keeps them, IV+ drops them.
        let profile = ChildProfile(displayName: "Test",
                                   brownsStage: mode == .singleWord ? .one : .fourPlus,
                                   isActive: true)
        profile.aiMode = mode == .sentence ? .sentences : .on
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        try body(engine)
        withExtendedLifetime(container) {}
    }

    /// The same harness, plus the context, for the tests that care what reached
    /// the log rather than what reached the strip. The two are deliberately
    /// different — the strip stops growing on a mash and the log does not — so
    /// asserting on the strip alone cannot see the bug this covers.
    private func withEngineAndContext(mode: InteractionMode,
                                      _ body: (SentenceEngine, ModelContext) throws -> Void) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test",
                                   brownsStage: mode == .singleWord ? .one : .fourPlus,
                                   isActive: true)
        profile.aiMode = mode == .sentence ? .sentences : .on
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        try body(engine, ctx)
        withExtendedLifetime(container) {}
    }

    private func loggedUtterances(_ ctx: ModelContext) -> [LoggedUtterance] {
        (try? ctx.fetch(FetchDescriptor<LoggedUtterance>())) ?? []
    }

    // MARK: - Model: the stage is an input, not a rule

    /// A new profile starts with AI on and sentences off at every stage
    /// (Mark 2026-11-15). Turning sentences on is a deliberate step.
    @Test func newProfilesStartWithSentencesOffAtEveryStage() {
        for stage in BrownsStage.allCases {
            let p = ChildProfile(displayName: "A", brownsStage: stage)
            #expect(p.aiMode == .on)
            #expect(p.interactionMode == .singleWord)
            #expect(p.wordsPerMessage == stage.defaultWordsPerMessage)
            #expect(p.trayPictures == .auto)
            #expect(p.matchesStageDefaults)
        }
    }

    /// A profile written before build 11 has no `aiModeRaw` and keeps doing
    /// what its stage did then, so an update does not silently turn a
    /// child's sentences off.
    @Test func profileFromBeforeBuildElevenFollowsItsStage() {
        let p = ChildProfile(displayName: "A", brownsStage: .one)
        p.aiModeRaw = ""
        #expect(p.aiMode == .on)
        p.brownsStage = .twoThree
        #expect(p.aiMode == .sentences)
        #expect(p.interactionMode == .sentence)
        // Once chosen, the choice holds whatever the stage does.
        p.aiMode = .on
        p.brownsStage = .fourPlus
        #expect(p.interactionMode == .singleWord)
    }

    /// Changing the stage changes nothing else on its own. Its defaults are
    /// offered by the page and applied only when taken.
    @Test func changingStageLeavesTheOtherSettingsAlone() {
        let p = ChildProfile(displayName: "A", brownsStage: .one)
        p.aiMode = .sentences
        p.wordsPerMessage = 7
        p.trayPictures = .words
        p.brownsStage = .fourPlus
        #expect(p.aiMode == .sentences)
        #expect(p.wordsPerMessage == 7)
        #expect(p.trayPictures == .words)

        p.applyStageDefaults()
        #expect(p.wordsPerMessage == 5)
        #expect(p.trayPictures == .auto)
        #expect(p.aiMode == .sentences)      // AI is not the stage's to set

        p.resetToStageDefaults()
        #expect(p.aiMode == .on)
        #expect(p.matchesStageDefaults)
    }

    /// Every stage can choose any count in 4…8. A count an earlier build
    /// stored outside that (Stage I kept 1) reads as the nearest legal one.
    @Test func wordsPerMessageIsFourToEightAtEveryStage() {
        for stage in BrownsStage.allCases {
            let p = ChildProfile(displayName: "A", brownsStage: stage)
            p.wordsPerMessage = 8
            #expect(p.wordsPerMessage == 8)
            p.wordsPerMessage = 2
            #expect(p.wordsPerMessage == 4)
        }
        let old = ChildProfile(displayName: "A")
        old.maxSelectedTiles = 1
        #expect(old.wordsPerMessage == 4)
    }

    /// An unknown raw value falls back to Stage I, and an unknown AI mode to
    /// what that stage did before build 11 — single words.
    @Test func unknownRawValuesFallBackQuietly() {
        let p = ChildProfile(displayName: "A")
        p.brownsStageRaw = "somethingFuture"
        p.aiModeRaw = "somethingFuture"
        #expect(p.brownsStage == .one)
        #expect(p.interactionMode == .singleWord)
    }

    // MARK: - Pictures in the message box

    /// Brandi's review: at Stage IV+ the tray carries the word without the
    /// picture. That is the stage's starting point; the profile can choose.
    @Test func trayPicturesDefaultFromTheStage() {
        #expect(BrownsStage.one.showsPicturesInTray)
        #expect(BrownsStage.twoThree.showsPicturesInTray)
        #expect(!BrownsStage.fourPlus.showsPicturesInTray)
    }

    /// The tray reads the profile that is talking, through the engine, and a
    /// change from the board writes that profile.
    @Test func trayPicturesFollowTheProfileThatIsTalking() throws {
        try withEngine(mode: .sentence) { engine in      // Stage IV+
            #expect(!engine.trayShowsPictures)
            engine.trayPictures = .pictures
            #expect(engine.trayShowsPictures)
            #expect(engine.profileResolver?.active?.trayPictures == .pictures)
        }
        try withEngine(mode: .singleWord) { engine in    // Stage I
            #expect(engine.trayShowsPictures)
        }
    }

    /// With no child resolved at all the tray keeps its pictures. That is the
    /// safe direction: a reader who did not need them is mildly over-served,
    /// where a child who cannot read yet would be handed a row of words.
    @Test func trayKeepsPicturesWithNoProfile() {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0,
                                                                  maxLatency: 0))
        #expect(engine.trayShowsPictures)
    }

    // MARK: - The board's switch writes the profile

    /// Single words / AI sentences on the board is the talking profile's
    /// setting now, so it syncs with the profile and survives a relaunch.
    @Test func boardSwitchWritesTheTalkingProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .one,
                                   maxSelectedTiles: 6, isActive: true)
        ctx.insert(profile)
        try? ctx.save()

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(resolver.interactionMode == .singleWord)

        resolver.requestMode(.sentence)
        #expect(profile.aiMode == .sentences)
        #expect(resolver.interactionMode == .sentence)
        #expect(resolver.maxSelectedTiles == 6)
        #expect(profile.brownsStage == .one)        // the stage is untouched

        let rebuilt = ChildProfileResolver()
        rebuilt.configure(modelContext: ctx)
        #expect(rebuilt.interactionMode == .sentence)

        rebuilt.requestMode(.singleWord)
        #expect(profile.aiMode == .on)
        withExtendedLifetime(container) {}
    }

    /// A profile with AI off stays off when the board asks for single words;
    /// only an explicit ask for sentences turns it back on.
    @Test func singleWordsLeavesAnAIOffProfileOff() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", isActive: true)
        profile.aiMode = .off
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        resolver.requestMode(.singleWord)
        #expect(profile.aiMode == .off)
        withExtendedLifetime(container) {}
    }

    /// The device-wide override earlier builds kept is folded into the
    /// profile that was talking, then cleared, so an update keeps the board
    /// doing what it did.
    @Test func legacyDeviceOverrideMovesIntoTheTalkingProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .one, isActive: true)
        profile.aiModeRaw = ""                       // written before build 11
        ctx.insert(profile)
        let device = DeviceProfileStore.ensure(context: ctx)
        device.modeOverride = .sentence
        try? ctx.save()

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(profile.aiMode == .sentences)
        #expect(resolver.interactionMode == .sentence)
        #expect(device.modeOverrideRaw.isEmpty)
        withExtendedLifetime(container) {}
    }

    /// The backspace control at Stage IV+. Tapping a bare word to delete it is
    /// not obvious once the tray is trying to look like text, so there has to be
    /// a control that is.
    @Test func backspaceRemovesTheLastWord() throws {
        try withEngine(mode: .sentence) { engine in
            engine.addTile(TileModel(key: "i", wordClass: "core"))
            engine.addTile(TileModel(key: "want", wordClass: "actions"))
            engine.addTile(TileModel(key: "more", wordClass: "core"))
            #expect(engine.activeGroup.tiles.map(\.key) == ["i", "want", "more"])

            engine.removeLastSelectedTile()
            #expect(engine.activeGroup.tiles.map(\.key) == ["i", "want"])

            engine.removeLastSelectedTile()
            engine.removeLastSelectedTile()
            #expect(engine.activeGroup.tiles.isEmpty)

            // And on an empty tray it is a no-op rather than a crash — the
            // button is disabled, but nothing should depend on that.
            engine.removeLastSelectedTile()
            #expect(engine.activeGroup.tiles.isEmpty)
        }
    }

    /// Word-mode Play at Stage IV+: say the line exactly as it was assembled.
    ///
    /// No grammar and no cleanup — a child arranging words and hearing what they
    /// arranged is the point, and tidying would teach that the board says
    /// something other than what was pressed.
    @Test func speakStripSaysEveryWordInOrder() throws {
        try withEngine(mode: .singleWord) { engine in
            engine.addTile(TileModel(key: "me", wordClass: "core"))
            engine.addTile(TileModel(key: "want", wordClass: "actions"))
            engine.addTile(TileModel(key: "cookie", wordClass: "food"))
            #expect(engine.spokenStrip.map(\.value) == ["me", "want", "cookie"])

            // Nothing to assert about audio, so assert about the line it builds.
            #expect(engine.spokenStrip.map(\.value).joined(separator: " ")
                    == "me want cookie")
            engine.speakStrip()   // must not trap on a populated strip

            engine.clearStrip()
            engine.speakStrip()   // nor on an empty one
            #expect(engine.spokenStrip.isEmpty)
        }
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

    /// Mashing one tile ten times is ten rows in the log.
    ///
    /// The strip deliberately does not grow on a mash — that is a child-surface
    /// choice and stays — but the mash branch used to `return` BEFORE the log
    /// write, so nine of the ten presses vanished. A mash became
    /// indistinguishable from one calm press, which is the opposite of what a
    /// therapist reading the log needs to see. `repetitionCount` was even
    /// incremented on that path and then never persisted anywhere.
    @Test func singleWordMode_everyMashIsLogged() throws {
        try withEngineAndContext(mode: .singleWord) { engine, ctx in
            let bathroom = TileModel(key: "bathroom", wordClass: "body")
            for _ in 0..<10 { engine.addTile(bathroom) }

            let logged = loggedUtterances(ctx)
            #expect(logged.count == 10)
            #expect(logged.allSatisfy { $0.tileKeys == ["bathroom"] })
            // The strip still shows one chip — the two consumers disagree on
            // purpose, and that is the whole point of the fix.
            #expect(engine.spokenStrip.count == 1)
        }
    }

    /// Each logged press stays a single-word row: one tile, saying itself, no
    /// escalation. `ActivitySession.isSingleWord` tests for exactly that shape,
    /// so a mash that logged anything else would silently flip every activity
    /// screen into sentence mode.
    @Test func singleWordMode_mashRowsKeepTheSingleWordShape() throws {
        try withEngineAndContext(mode: .singleWord) { engine, ctx in
            let more = TileModel(key: "more", value: "more", wordClass: "core")
            engine.addTile(more)
            engine.addTile(more)

            let logged = loggedUtterances(ctx)
            #expect(logged.count == 2)
            #expect(logged.allSatisfy { $0.sentence == "more" })
            #expect(logged.allSatisfy { $0.repetitionCount == 0 })
        }
    }

    /// A non-consecutive repeat was never broken and must stay that way.
    @Test func singleWordMode_alternatingWordsLogEachPress() throws {
        try withEngineAndContext(mode: .singleWord) { engine, ctx in
            let dad = TileModel(key: "dad", wordClass: "people")
            let mom = TileModel(key: "mom", wordClass: "people")
            engine.addTile(dad)
            engine.addTile(mom)
            engine.addTile(dad)
            #expect(loggedUtterances(ctx).count == 3)
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
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        profile.aiMode = .sentences
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

    /// Regression: two Play taps a few ms apart (before the first request's
    /// task starts) launched two generations, and the second counted as a
    /// repeat — a stray ↻ badge on a sentence asked for once.
    @Test func doublePlayBeforeGenerationStartsIsOneRequest() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        profile.aiMode = .sentences
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))
        engine.triggerGo()
        engine.triggerGo()
        try await waitUntil { engine.canReplay }

        #expect(engine.repetitionCount == 0)
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
