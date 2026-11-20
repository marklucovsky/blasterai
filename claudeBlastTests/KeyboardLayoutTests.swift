// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  KeyboardLayoutTests.swift
//  claudeBlastTests
//
//  The keyboard pages: their key geometry, which page is which keyboard, and
//  that BlasterAI 60 ships both.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct KeyboardLayoutTests {

    /// Every row is the same width, so every row ends on the grid's edge.
    @Test(arguments: KeyboardLayout.allCases)
    func everyRowIsTheSameWidth(_ layout: KeyboardLayout) {
        for (i, row) in layout.rows.enumerated() {
            #expect(row.reduce(0) { $0 + $1.width } == KeyboardLayout.rowWidth, "\(layout) row \(i)")
        }
    }

    /// All 26 letters, once each, and the keys every keyboard needs.
    @Test(arguments: [KeyboardLayout.qwerty, .abc])
    func everyLetterIsThereOnce(_ layout: KeyboardLayout) {
        let keys = layout.rows.flatMap { $0 }
        let letters = keys.compactMap { key -> String? in
            if case .character(let c) = key.action, c.first?.isLetter == true { return c }
            return nil
        }
        #expect(letters.sorted() == "abcdefghijklmnopqrstuvwxyz".map(String.init))
        for needed: KeyboardKey.Action in [.shift, .backspace, .deleteWord, .space, .speakLine] {
            #expect(keys.contains { $0.action == needed }, "\(layout) lacks \(needed)")
        }
        #expect(Set(keys.map(\.id)).count == keys.count, "key ids are unique")
    }

    /// Every keyboard opens the other two from its bottom row.
    @Test func theKeyboardsSwitchToEachOther() {
        func targets(_ layout: KeyboardLayout) -> Set<String> {
            Set(layout.rows.flatMap { $0 }.compactMap { key -> String? in
                if case .switchTo(let page, _) = key.action { return page }
                return nil
            })
        }
        for layout in KeyboardLayout.allCases {
            let others = Set(KeyboardLayout.allCases.filter { $0 != layout }.map(\.pageKey))
            #expect(targets(layout) == others, "\(layout)")
        }
    }

    /// The numbers page: the digits, the signs a sum needs, money and the
    /// clock — and no letters and no Shift.
    @Test func theNumbersPageIsUncluttered() {
        let keys = KeyboardLayout.numbers.rows.flatMap { $0 }
        let typed = keys.compactMap { key -> String? in
            if case .character(let c) = key.action { return c }
            return nil
        }
        for needed in ["0", "1", "9", "+", "\u{2212}", "×", "÷", "=", "<", ">", "%", "$", ".", "/",
                       ":00", ":15", ":30", ":45"] {
            #expect(typed.contains(needed), "lacks \(needed)")
        }
        #expect(!typed.contains { $0.count == 1 && $0.first!.isLetter })
        #expect(!keys.contains { $0.action == .shift })
        for needed: KeyboardKey.Action in [.backspace, .deleteWord, .space, .speakLine] {
            #expect(keys.contains { $0.action == needed })
        }
    }

    /// The signs are the numbers page's vowels: tinted when Highlight Signs
    /// is on. Digits, money and the clock are not signs.
    @Test func theSignsAreMarked() {
        let keys = KeyboardLayout.numbers.rows.flatMap { $0 }
        let signs = keys.filter(\.isSign).compactMap { k -> String? in
            if case .character(let c) = k.action { return c } else { return nil }
        }
        #expect(signs == ["+", "\u{2212}", "×", "÷", "=", "<", ">"])
        #expect(keys.contains { $0.action == .mathHelp })
    }

    /// Typed on the numbers page, a sum is said as one.
    @Test func aSumTypedOnTheNumbersPageIsSaid() {
        #expect(SpeechNormalizer.line("12\u{2212}5=7") == "12 minus 5 equals 7")
        #expect(SpeechNormalizer.line("3:15") == "3 15")
        #expect(SpeechNormalizer.line("3:00") == "3 o'clock")
        #expect(SpeechNormalizer.key(":45") == "forty-five")
    }

    @Test func aPageIsAKeyboardByItsKey() {
        #expect(KeyboardLayout.forPage("keyboard") == .qwerty)
        #expect(KeyboardLayout.forPage("<system>:keyboard") == .qwerty)
        #expect(KeyboardLayout.forPage("<system>:keyboard_abc") == .abc)
        #expect(KeyboardLayout.forPage("<system>:numbers") == .numbers)
        #expect(KeyboardLayout.forPage("home") == nil)
        #expect(KeyboardLayout.forPage("<system>:actions") == nil)
        #expect(KeyboardLayout.forPage("<template>:keyboard") == nil)
    }

    /// `sys:keyboard` and `sys:keyboard_abc` name real pages of BlasterAI 60,
    /// with nothing on them: the keys are drawn, not stored.
    @Test func blasterAI60ShipsBothKeyboardPages() {
        let context = TestStore.freshContainer().mainContext
        let system = BootstrapLoader.loadDefaultVocabulary(context: context).scene
        for layout in KeyboardLayout.allCases {
            let page = system.page(withKey: layout.pageKey)
            #expect(page != nil, "\(layout.pageKey) missing")
            #expect(page?.tiles.isEmpty == true)
        }
    }
}
}
