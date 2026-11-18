// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SpeechNormalizerTests.swift
//  claudeBlastTests
//
//  What typed text is said as: one key, and a line on Speak.
//

import Testing
@testable import claudeBlast

extension SerialTests {
@Suite
struct SpeechNormalizerTests {

    @Test("One key says its name", arguments: [
        ("a", "a"), ("Z", "z"), ("I", "i"), ("7", "7"),
        ("+", "plus"), ("-", "minus"), ("\u{2212}", "minus"), ("×", "times"),
        ("÷", "divided by"), ("=", "equals"), ("<", "less than"), (">", "greater than"),
        ("%", "percent"), ("$", "dollar"), (",", "comma"), (".", "period"),
        ("?", "question mark"), ("/", "slash"),
        (":00", "o'clock"), (":15", "fifteen"), (":30", "thirty"), (":45", "forty-five"),
    ])
    func oneKey(_ key: String, _ said: String) {
        #expect(SpeechNormalizer.key(key) == said)
    }

    /// The Letters pack names its tiles "A", "B", …: alone or in a line they
    /// say the letter, not "capital A". The pronoun *I* in a line is a word.
    @Test func aLetterTileSaysTheLetter() {
        #expect(SpeechNormalizer.tile("A") == "a")
        #expect(SpeechNormalizer.tile("B", wordClass: "letter", inLine: true) == "b")
        #expect(SpeechNormalizer.tile("I", wordClass: "letter", inLine: true) == "i")
        #expect(SpeechNormalizer.tile("I", wordClass: "people", inLine: true) == "I")
        #expect(SpeechNormalizer.tile("7") == "7")
        #expect(SpeechNormalizer.tile("+") == "plus")
        #expect(SpeechNormalizer.tile("Apple", wordClass: "food", inLine: true) == "Apple")
    }

    @Test("A line says what was meant", arguments: [
        // Words are said as typed.
        ("I am 7", "I am 7"),
        ("hello", "hello"),
        ("x-ray", "x-ray"),
        ("I want - no", "I want - no"),
        // Arithmetic.
        ("2 + 2 = 4", "2 plus 2 equals 4"),
        ("2+2=4", "2 plus 2 equals 4"),
        ("10 - 3 = 7", "10 minus 3 equals 7"),
        ("10-3", "10 minus 3"),
        ("6 × 7", "6 times 7"),
        ("6 x 7", "6 times 7"),
        ("6x7", "6 times 7"),
        ("box 7", "box 7"),
        ("12 ÷ 4 = 3", "12 divided by 4 equals 3"),
        ("3 < 5", "3 is less than 5"),
        ("9 > 2", "9 is greater than 2"),
        ("5 \u{2212} 1", "5 minus 1"),
        // Fractions.
        ("5/3", "5 thirds"),
        ("1/2", "1 half"),
        ("3/4", "3 fourths"),
        ("7/100", "7 over 100"),
        // Money and percent.
        ("$5", "5 dollars"),
        ("$1", "1 dollar"),
        ("$2.50", "2 dollars and 50 cents"),
        ("50%", "50 percent"),
        // Time.
        ("3:00", "3 o'clock"),
        ("3:15", "3 15"),
        ("lunch at 12:30", "lunch at 12 30"),
        (":15", "fifteen"),
        // One key on its own.
        ("+", "plus"),
        ("A", "a"),
        ("A cat", "A cat"),
        ("  ", ""),
    ])
    func aLine(_ typed: String, _ said: String) {
        #expect(SpeechNormalizer.line(typed) == said)
    }
}
}
