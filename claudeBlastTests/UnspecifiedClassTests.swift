// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UnspecifiedClassTests.swift
//  claudeBlastTests
//
//  Unspecified: the class of a word nobody has classified yet. A caregiver
//  can choose it, it is never a meaning a model is told or may give, and its
//  tile draws plain. Pure logic — no container.
//

import SwiftUI
import Testing
@testable import claudeBlast

struct UnspecifiedClassTests {
    @Test func isACaregiverClassButNeverOneAModelMayGive() {
        let cls = VocabularyClasses.known(VocabularyClasses.unspecified)
        #expect(cls?.isCaregiverSelectable == true)
        #expect(cls?.defaultPartOfSpeech == nil)
        #expect(!VocabularyClasses.assignable.map(\.name).contains(VocabularyClasses.unspecified))
        #expect(!VocabularyClasses.assignableList.contains(VocabularyClasses.unspecified))
        #expect(VocabularyClasses.assignable.count == VocabularyClasses.caregiverSelectable.count - 1)
    }

    /// The sentence prompt names a class so it can settle the sense; a word
    /// with none goes in bare rather than as `cat (unspecified)`.
    @Test func theSentencePromptNamesNoClassForIt() {
        let builder = SentencePromptBuilder(brownsStage: .twoThree)
        let prompt = builder.formatUserPrompt(tiles: [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "zorb", value: "zorb", wordClass: VocabularyClasses.unspecified),
        ])
        #expect(prompt == "eat (actions), zorb")
    }

    @Test func thePicturePromptNamesNoClassForIt() {
        #expect(TileImageGenerator.subject("zorb", VocabularyClasses.unspecified) == "zorb")
        #expect(TileImageGenerator.subject("pony", "animal") == "pony (animal)")
    }

    /// Generation sees the word, so it is not proposed again, but under no
    /// class a model could copy as one.
    @Test func theVocabularyListPutsItApart() {
        let tiles = [TileModel(key: "pony", value: "pony", wordClass: "animal"),
                     TileModel(key: "zorb", value: "zorb", wordClass: VocabularyClasses.unspecified)]
        let block = SceneGeneratorService.vocabBlock(allTiles: tiles)
        #expect(block == "animal: pony\nother words: zorb")
        #expect(!block.contains(VocabularyClasses.unspecified))
    }

    /// Plain, not chrome's grey: an unfinished word, not board furniture.
    @Test func itsTileIsPlainNotChrome() {
        let tile = TileModel(key: "zorb", value: "zorb", wordClass: VocabularyClasses.unspecified)
        #expect(tile.resolvedPartOfSpeech == nil)
        #expect(TileColorResolver.color(for: tile) == TileColorResolver.unspecified)
        #expect(TileColorResolver.color(forWordClass: VocabularyClasses.unspecified) == TileColorResolver.unspecified)
        #expect(TileColorResolver.unspecified != TileColorResolver.chromeDefault)
    }
}
