// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordPredictorTests.swift
//  claudeBlastTests
//
//  The prediction bar: prefix matches from the vocabulary and what was typed
//  before, ranked by the person's own use; nothing typed, what usually comes
//  next.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct WordPredictorTests {

    private func tiles() -> [TileModel] {
        [TileModel(key: "cookie", value: "cookie", wordClass: "food"),
         TileModel(key: "cold", value: "cold", wordClass: "describe"),
         TileModel(key: "come", value: "come", wordClass: "actions"),
         TileModel(key: "want", value: "want", wordClass: "actions"),
         TileModel(key: "i", value: "I", wordClass: "people"),
         TileModel(key: "letter_c", value: "C", wordClass: "letter"),
         TileModel(key: "food", value: "food", wordClass: "navigation")]
    }

    @Test func aPrefixOffersTheWordsItStarts() {
        let p = WordPredictor(tiles: tiles(), history: [])
        let words = p.predict(prefix: "co", after: nil).map(\.word)
        #expect(Set(words) == ["cookie", "cold", "come"])
        #expect(words.first == "cold" || words.first == "come", "shorter first when unused")
        #expect(p.predict(prefix: "Co", after: nil).count == 3, "case does not matter")
        #expect(p.predict(prefix: "c", after: nil).allSatisfy { $0.tileKey != "letter_c" },
                "the Letters pack is not a word")
        #expect(p.predict(prefix: "f", after: nil).isEmpty, "folders are not words")
    }

    @Test func ownUseRanksFirst() {
        let history = [["i", "want", "cookie"], ["cookie"], ["cookie"]]
        let p = WordPredictor(tiles: tiles(), history: history)
        #expect(p.predict(prefix: "co", after: nil).first?.word == "cookie")
    }

    @Test func aTypedWordIsOfferedOnceSaid() {
        let history = [["\(TileSelection.typedPrefix)zebra"], ["\(TileSelection.typedPrefix)2+2=4"]]
        let p = WordPredictor(tiles: tiles(), history: history)
        let zebra = p.predict(prefix: "ze", after: nil)
        #expect(zebra.map(\.word) == ["zebra"])
        #expect(zebra.first?.tileKey == nil, "no picture: a text chip")
        #expect(p.predict(prefix: "2", after: nil).isEmpty, "sums are not words")
    }

    /// Nothing typed, nothing offered; once a word is started, what has
    /// followed the last word comes first.
    @Test func onlyAStartedWordIsOffered() {
        let history = [["i", "want", "cookie"], ["i", "want", "cookie"], ["want", "cold"],
                       ["come"], ["come"], ["come"]]
        let p = WordPredictor(tiles: tiles(), history: history)
        #expect(p.predict(prefix: "", after: "want").isEmpty)
        #expect(p.predict(prefix: "", after: nil).isEmpty)
        #expect(p.predict(prefix: "co", after: nil).first?.word == "come", "most used")
        #expect(p.predict(prefix: "co", after: "want").first?.word == "cookie", "what follows want")
    }

    /// Alphabetical, the default in the app: the same letters always show
    /// the same words in the same places, whatever has been used.
    @Test func alphabeticalOrderNeverMoves() {
        let used = WordPredictor(tiles: tiles(), history: [["come"], ["come"], ["want", "cookie"]])
        let fresh = WordPredictor(tiles: tiles(), history: [])
        let a = used.predict(prefix: "co", after: "want", order: .alphabetical).map(\.word)
        #expect(a == ["cold", "come", "cookie"])
        #expect(fresh.predict(prefix: "co", after: nil, order: .alphabetical).map(\.word) == a)
    }

    @Test func sumsWithSpacesAreNotWords() {
        let p = WordPredictor(tiles: tiles(), history: [["\(TileSelection.typedPrefix)5/3=1 2/3"]])
        #expect(p.predict(prefix: "5", after: nil).isEmpty)
    }

    /// A chosen word is typed in full and committed: the vocabulary's tile.
    @Test func choosingAPredictionCommitsTheWord() throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        profile.aiMode = .sentences
        ctx.insert(profile)
        ctx.insert(TileModel(key: "cookie", value: "cookie", wordClass: "food"))
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        engine.typeKey("c", speaking: false)
        engine.typeKey("o", speaking: false)
        engine.choosePrediction("cookie")
        #expect(engine.typingDraft == "")
        #expect(engine.selectedTiles.map(\.key) == ["cookie"])
        #expect(engine.lastTypedLineWord == "cookie")
        withExtendedLifetime(container) {}
    }
}
}
