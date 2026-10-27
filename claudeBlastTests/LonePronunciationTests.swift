// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LonePronunciationTests.swift
//  claudeBlastTests
//
//  A word spoken on its own is said as a word, not read as a letter.
//

import Testing
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct LonePronunciationTests {

    /// The *I* tile said "capital I" when tapped on its own; "i." says the word.
    @Test func theITileIsSaidAsAWord() {
        #expect(SpeechSynthesizer.loneSpeech["i"] == "i.")
    }

    /// Keyed by tile key, not text: the letters pack's I is the letter.
    @Test func theLetterIKeepsItsName() {
        #expect(SpeechSynthesizer.loneSpeech["letter_i"] == nil)
    }
}
}
