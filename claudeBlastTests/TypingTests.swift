// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TypingTests.swift
//  claudeBlastTests
//
//  Typed text in the message box: letters build a word, Space commits it, a
//  word in the vocabulary becomes its tile, and a typed line is said as typed.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct TypingTests {

    /// An engine on a profile in `mode`, words per message 4, with a few
    /// words in the vocabulary. The container lives for the whole closure.
    private func withEngine(mode: InteractionMode,
                            _ body: (SentenceEngine, ModelContext) throws -> Void) throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test",
                                   brownsStage: mode == .singleWord ? .one : .fourPlus,
                                   isActive: true)
        profile.maxSelectedTiles = 4
        profile.aiMode = mode == .sentence ? .sentences : .on
        ctx.insert(profile)
        ctx.insert(TileModel(key: "cookie", value: "cookie", wordClass: "food"))
        ctx.insert(TileModel(key: "want", value: "want", wordClass: "actions"))
        ctx.insert(TileModel(key: "i", value: "I", wordClass: "people"))
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        #expect(engine.interactionMode == mode)
        try body(engine, ctx)
        withExtendedLifetime(container) {}
    }

    /// Type `text` key by key; a space is Space.
    private func type(_ text: String, into engine: SentenceEngine) {
        for ch in text {
            if ch == " " { engine.typeSpace() } else { engine.typeKey(String(ch)) }
        }
    }

    // MARK: - Building a word

    @Test func lettersBuildADraftThatSpaceCommits() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("hel", into: engine)
            #expect(engine.typingDraft == "hel")
            #expect(engine.selectedTiles.isEmpty, "nothing is committed until Space")
            type("lo ", into: engine)
            #expect(engine.typingDraft == "")
            #expect(engine.selectedTiles.map(\.value) == ["hello"])
            #expect(engine.selectedTiles.first?.isTyped == true, "not a word we have: a text chip")
            #expect(engine.activeGroup.isTyped)
        }
    }

    @Test func spaceWithNothingTypedIsNotAWord() throws {
        try withEngine(mode: .sentence) { engine, _ in
            engine.typeSpace()
            #expect(engine.selectedTiles.isEmpty)
            #expect(!engine.activeGroup.isTyped)
        }
    }

    /// "cookie" typed becomes the cookie tile's chip, picture and all.
    @Test func aTypedWordInTheVocabularyBecomesItsTile() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("I want Cookie ", into: engine)
            #expect(engine.selectedTiles.map(\.key) == ["i", "want", "cookie"])
            #expect(engine.selectedTiles.allSatisfy { !$0.isTyped })
            // Every word matched, but the line is still typed: no sentence.
            #expect(engine.activeGroup.isTyped)
        }
    }

    // MARK: - A typed line

    @Test func aTypedLineIsNotHeldToTheCap() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("one two three four five six ", into: engine)
            #expect(engine.selectedTiles.count == 6, "words per message is 4")
            #expect(engine.maxTilesPerGroup == 4)
        }
    }

    /// Play on a typed line says it; it never asks for a sentence.
    @Test func aTypedLineIsNeverGenerated() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("2 + 2 = 4", into: engine)
            engine.triggerGo()
            #expect(engine.typingDraft == "", "Play commits the word being typed")
            #expect(engine.selectedTiles.map(\.value) == ["2", "+", "2", "=", "4"])
            #expect(!engine.isWaiting && !engine.isThinking)
            #expect(engine.generatedSentence == nil)
        }
    }

    /// A tile tapped onto a typed line joins it, past the cap, and the line
    /// stays typed.
    @Test func aTileTappedOntoATypedLineJoinsIt() throws {
        try withEngine(mode: .sentence) { engine, ctx in
            type("one two three four ", into: engine)
            let cookie = try #require(try ctx.fetch(FetchDescriptor<TileModel>())
                .first { $0.key == "cookie" })
            engine.addTile(cookie)
            #expect(engine.selectedTiles.last?.key == "cookie")
            #expect(engine.selectedTiles.count == 5)
            #expect(engine.activeGroup.isTyped)
        }
    }

    // MARK: - Taking it back

    @Test func backspaceTakesALetterThenAWord() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("hi there", into: engine)
            engine.typeBackspace()
            #expect(engine.typingDraft == "ther")
            engine.typeDeleteWord()
            #expect(engine.typingDraft == "")
            #expect(engine.selectedTiles.map(\.value) == ["hi"])
            engine.typeBackspace()
            #expect(engine.selectedTiles.isEmpty)
            #expect(!engine.activeGroup.isTyped, "an emptied line is no longer typed")
        }
    }

    @Test func clearTakesTheDraftToo() throws {
        try withEngine(mode: .sentence) { engine, _ in
            type("hi the", into: engine)
            engine.clearSelection()
            #expect(engine.typingDraft == "")
            #expect(engine.selectedTiles.isEmpty)
        }
    }

    // MARK: - Single-word mode

    /// In single-word mode a typed word joins the strip, and a repeat is a
    /// second word, not a mash.
    @Test func singleWordModeTypesIntoTheStrip() throws {
        try withEngine(mode: .singleWord) { engine, _ in
            type("no no cookie ", into: engine)
            #expect(engine.spokenStrip.map(\.value) == ["no", "no", "cookie"])
            #expect(engine.spokenStrip.last?.key == "cookie")
            type("ok", into: engine)
            engine.typeBackspace()
            engine.typeBackspace()
            engine.typeBackspace()
            #expect(engine.spokenStrip.map(\.value) == ["no", "no"])
            type("bye", into: engine)
            engine.clearStrip()
            #expect(engine.typingDraft == "" && engine.spokenStrip.isEmpty)
        }
    }

    // MARK: - Matching

    @Test func matchingSkipsLettersAndFoldersAndPrefersTheKey() {
        let letter = TileModel(key: "letter_a", value: "A", wordClass: "letter")
        let article = TileModel(key: "a", value: "a", wordClass: "describe")
        let folder = TileModel(key: "food", value: "food", wordClass: "navigation")
        let custom = TileModel(key: "custom_i", value: "I", wordClass: "people")
        let pronoun = TileModel(key: "i", value: "I", wordClass: "people")
        let tiles = [letter, article, folder, custom, pronoun]
        #expect(TypedWords.match("A", in: tiles)?.key == "a")
        #expect(TypedWords.match("food", in: tiles) == nil)
        #expect(TypedWords.match("i", in: tiles)?.key == "i")
        #expect(TypedWords.match("zebra", in: tiles) == nil)
    }
}
}
