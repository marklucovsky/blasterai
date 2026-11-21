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
            #expect(row.reduce(0) { $0 + $1.width } == layout.rowWidth(compact: false), "\(layout) row \(i)")
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

    /// The letter keyboards open each other and the numbers; the numbers
    /// and the calculator open every other keyboard.
    @Test func theKeyboardsSwitchToEachOther() {
        func targets(_ layout: KeyboardLayout) -> Set<String> {
            Set(layout.rows.flatMap { $0 }.compactMap { key -> String? in
                if case .switchTo(let page, _) = key.action { return page }
                return nil
            })
        }
        for layout in KeyboardLayout.allCases {
            var others = Set(KeyboardLayout.allCases.filter { $0 != layout }.map(\.pageKey))
            if layout == .qwerty || layout == .abc { others.remove(KeyboardLayout.calculator.pageKey) }
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

    /// The phone's portrait layouts: rows end on the edge, every letter and
    /// digit is there, and each keyboard still reaches the other two.
    @Test func compactLayoutsAreWholeAndSquare() {
        for layout in KeyboardLayout.allCases {
            let rows = layout.rows(compact: true)
            for (i, row) in rows.enumerated() {
                #expect(row.reduce(0) { $0 + $1.width } == layout.compactRowWidth, "\(layout) row \(i)")
            }
            let keys = rows.flatMap { $0 }
            let typed = Set(keys.compactMap { k -> String? in
                if case .character(let c) = k.action { return c } else { return nil }
            })
            let expected = layout == .numbers || layout == .calculator ? "0123456789" : "abcdefghijklmnopqrstuvwxyz"
            #expect(expected.allSatisfy { typed.contains(String($0)) }, "\(layout)")
            let switches = Set(keys.compactMap { k -> String? in
                if case .switchTo(let page, _) = k.action { return page } else { return nil }
            })
            var others = Set(KeyboardLayout.allCases.filter { $0 != layout }.map(\.pageKey))
            if layout == .qwerty || layout == .abc { others.remove(KeyboardLayout.calculator.pageKey) }
            #expect(switches == others, "\(layout)")
            #expect(keys.contains { $0.action == .speakLine } && keys.contains { $0.action == .backspace })
        }
        #expect(KeyboardLayout.numbers.rows(compact: true).flatMap { $0 }.contains { $0.action == .mathHelp })
    }

    /// The calculator: five across at every size, brackets, powers and
    /// roots, a plain `=`, and the `?` helper.
    @Test func theCalculatorIsACalculator() {
        let calc = KeyboardLayout.calculator
        #expect(calc.rowWidth(compact: false) == 5 && calc.rowWidth(compact: true) == 5)
        #expect(calc.rows(compact: false) == calc.rows(compact: true))
        let keys = calc.rows(compact: false).flatMap { $0 }
        let typed = Set(keys.compactMap { k -> String? in
            if case .character(let c) = k.action { return c } else { return nil }
        })
        for needed in ["(", ")", "²", "√", "^", "÷", "×", "\u{2212}", "+", ".", "="] {
            #expect(typed.contains(needed), "lacks \(needed)")
        }
        // `=` is a key a child types; `?` is the helper, as on the numbers page.
        #expect(keys.contains { $0.action == .mathHelp })
        #expect(KeyboardLayout.forPage("<system>:calculator") == .calculator)
    }

    /// The rail's Keyboard skips a keyboard the navigation bar already has:
    /// Brandi's board has Keyboard in its bar, so the rail opens the
    /// calculator (Mark, 2026-11-20).
    @Test func theRailOpensAKeyboardTheBarDoesNotHave() {
        #expect(KeyboardLayout.railTarget(preferred: .qwerty, inBar: []) == .qwerty)
        #expect(KeyboardLayout.railTarget(preferred: .qwerty, inBar: [.qwerty]) == .calculator)
        #expect(KeyboardLayout.railTarget(preferred: .qwerty, inBar: [.qwerty, .calculator]) == .numbers)
        #expect(KeyboardLayout.railTarget(preferred: .abc, inBar: [.qwerty]) == .abc)
        #expect(KeyboardLayout.railTarget(preferred: .qwerty, inBar: Set(KeyboardLayout.allCases)) == .qwerty,
                "every one in the bar: the rail keeps the preferred")
        #expect(KeyboardLayout.calculator.railTitle == "Calculator")

        let scene = BlasterScene(name: "Brandi", homePageKey: "home")
        scene.designedFor = "ipad-10x6"
        scene.pages = [PageSpec(key: "home", tiles: [])]
        #expect(BoardChrome.barKeyboards(of: scene).isEmpty)
        scene.ownRow = PageSpec(key: BlasterScene.rowPageKey, tiles: [
            TileEntry(key: "people", link: TileToken.systemLink(to: "people"), isAudible: false),
            TileEntry(key: "keyboard", link: TileToken.systemLink(to: "keyboard"), isAudible: false),
        ])
        #expect(BoardChrome.barKeyboards(of: scene) == [.qwerty])
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
