// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  KeyboardLayout.swift
//  claudeBlast
//
//  The keyboards, as key geometry. A keyboard page is an ordinary page of
//  BlasterAI 60 — reachable as `sys:keyboard`, under the navigation bar and
//  beside the rail — whose grid area draws these keys instead of cells
//  (Mark, 2026-11-18: ten columns leave no room for backspace beside a QWERTY
//  row, so the keys get their own geometry). See `docs/keyboard-design.md`.
//

import Foundation

/// One key: what it does, and how many key-widths it takes.
struct KeyboardKey: Hashable, Identifiable {
    enum Action: Hashable {
        /// Types its text: a letter, digit or mark.
        case character(String)
        case shift
        case backspace
        case deleteWord
        case space
        /// Commits the word being typed and says the whole line.
        case speakLine
        /// Opens another keyboard page of BlasterAI 60, by page key.
        case switchTo(page: String, label: String)
        /// The numbers page's `?`: types a question mark and, when the line
        /// asks something, works it out (`MathHelper`).
        case mathHelp
    }

    let action: Action
    /// In key-widths; a letter is 1.
    let width: Double
    /// Position in its layout, so two keys alike are still two keys.
    let id: String

    /// An arithmetic sign: tinted on the numbers page as vowels are on the
    /// letters (Settings › Keyboard › Highlight Signs).
    var isSign: Bool {
        if case .character(let c) = action { return ["+", "\u{2212}", "×", "÷", "=", "<", ">"].contains(c) }
        return false
    }

    var isVowel: Bool {
        if case .character(let c) = action { return KeyboardLayout.vowels.contains(c.lowercased()) }
        return false
    }
}

enum KeyboardLayout: String, CaseIterable {
    case qwerty, abc
    /// Digits, the arithmetic signs, money and the clock, and nothing else:
    /// uncluttered, as TouchChat's is (Mark, 2026-11-17).
    case numbers
    /// A calculator, styled as one (Mark, 2026-11-20): a display over a pad
    /// with brackets, powers and roots down its left side.
    case calculator

    /// The BlasterAI 60 page each keyboard is. `sys:keyboard` is QWERTY, the
    /// keyboard the rail's Keyboard button has always opened.
    var pageKey: String {
        switch self {
        case .qwerty: "keyboard"
        case .abc: "keyboard_abc"
        case .numbers: "numbers"
        case .calculator: "calculator"
        }
    }

    /// The keyboard a page shows, by navigation key: `<system>:keyboard` from
    /// any board built on BlasterAI 60, `keyboard` on BlasterAI 60 itself.
    /// Nil for every other page.
    static func forPage(_ navigationKey: String) -> KeyboardLayout? {
        let key = TileToken.systemPageKey(navigationKey) ?? navigationKey
        return allCases.first { $0.pageKey == key }
    }

    static let vowels: Set<String> = ["a", "e", "i", "o", "u"]

    /// Key-widths across every row.
    static let rowWidth: Double = 11.5

    /// Key-widths across every row of a compact layout: 10 for the letters,
    /// as the iPhone's own keyboard; 5 for the numbers, a calculator's pad.
    var compactRowWidth: Double {
        switch self {
        case .numbers, .calculator: 5
        case .qwerty, .abc: 10
        }
    }

    /// The calculator is five across at every size.
    func rowWidth(compact: Bool) -> Double {
        compact || self == .calculator ? compactRowWidth : Self.rowWidth
    }

    /// The rows, top to bottom: the compact ones on a narrow grid (a phone in
    /// portrait), where 11.5 keys across drew thin, tall keys (Mark,
    /// 2026-11-20).
    func rows(compact: Bool) -> [[KeyboardKey]] { compact || self == .calculator ? compactRows : rows }

    /// The rows for a phone in portrait. Letters as the iPhone's keyboard
    /// lays them out — backspace beside z–m, Speak on the space row, no
    /// delete word — and the numbers as a calculator's pad, five across.
    var compactRows: [[KeyboardKey]] {
        let bottom: [(KeyboardKey.Action, Double)] = [
            (.switchTo(page: Self.numbers.pageKey, label: Self.numbers.switchLabel), 1.25),
            (.switchTo(page: (self == .abc ? Self.qwerty : Self.abc).pageKey,
                       label: (self == .abc ? Self.qwerty : Self.abc).switchLabel), 1.25),
            (.character(","), 1), (.space, 3), (.character("."), 1), (.character("?"), 1),
            (.speakLine, 1.5),
        ]
        switch self {
        case .qwerty:
            return Self.build([
                letters("qwertyuiop"),
                letters("asdfghjkl") + [(.character("'"), 1)],
                [(.shift, 1.5)] + letters("zxcvbnm") + [(.backspace, 1.5)],
                bottom,
            ])
        case .abc:
            return Self.build([
                letters("abcdefghij"),
                letters("klmnopqrst"),
                [(.shift, 1.5)] + letters("uvwxyz") + [(.character("'"), 1), (.backspace, 1.5)],
                bottom,
            ])
        case .numbers:
            return Self.build([
                marks("789÷") + [(.backspace, 1)],
                marks("456×=") ,
                marks("123\u{2212}<"),
                marks("0.%+>"),
                [(.character(":00"), 1), (.character(":15"), 1), (.character(":30"), 1),
                 (.character(":45"), 1), (.mathHelp, 1)],
                marks("$/:") + [(.space, 2)],
                [(.switchTo(page: Self.qwerty.pageKey, label: Self.qwerty.switchLabel), 1.25),
                 (.switchTo(page: Self.abc.pageKey, label: Self.abc.switchLabel), 1.25),
                 (.switchTo(page: Self.calculator.pageKey, label: Self.calculator.switchLabel), 1.25),
                 (.speakLine, 1.25)],
            ])
        case .calculator:
            return Self.calculatorRows
        }
    }

    /// The calculator: brackets, powers and roots down the left, the digits
    /// in the middle, the signs down the right; delete word is its C. `=` is
    /// a key like any other, so a child can type `5+5=10` and say it; the
    /// purple `?` works a sum out, as on the numbers page (Mark, 2026-11-20).
    private static let calculatorRows: [[KeyboardKey]] = build([
        [(.deleteWord, 1), (.character("("), 1), (.character(")"), 1), (.character("%"), 1), (.character("÷"), 1)],
        [(.character("²"), 1), (.character("7"), 1), (.character("8"), 1), (.character("9"), 1), (.character("×"), 1)],
        [(.character("√"), 1), (.character("4"), 1), (.character("5"), 1), (.character("6"), 1),
         (.character("\u{2212}"), 1)],
        [(.character("^"), 1), (.character("1"), 1), (.character("2"), 1), (.character("3"), 1), (.character("+"), 1)],
        [(.backspace, 1), (.character("0"), 2), (.character("."), 1), (.character("="), 1)],
        [(.switchTo(page: numbers.pageKey, label: numbers.switchLabel), 1),
         (.switchTo(page: abc.pageKey, label: abc.switchLabel), 1),
         (.switchTo(page: qwerty.pageKey, label: qwerty.switchLabel), 1),
         (.mathHelp, 1),
         (.speakLine, 1)],
    ])

    /// The rows, top to bottom. Every row is `rowWidth` wide.
    var rows: [[KeyboardKey]] {
        switch self {
        case .qwerty:
            return Self.build([
                letters("qwertyuiop") + [(.backspace, 1.5)],
                letters("asdfghjkl") + [(.character("'"), 1), (.speakLine, 1.5)],
                [(.shift, 1.5)] + letters("zxcvbnm") + marks(",.?"),
                bottom(switchingTo: .abc),
            ])
        case .abc:
            return Self.build([
                letters("abcdefghij") + [(.backspace, 1.5)],
                letters("klmnopqrst") + [(.speakLine, 1.5)],
                [(.shift, 1.5)] + letters("uvwxyz") + marks(",.?'"),
                bottom(switchingTo: .qwerty),
            ])
        case .numbers:
            // `−` is the minus sign, not a hyphen: it reads as minus wherever
            // it lands (`SpeechNormalizer`). The clock keys add to the hour
            // typed before them: 3 then :15 is 3:15. `?` is the math helper.
            return Self.build([
                marks("1234567890") + [(.backspace, 1.5)],
                marks("+\u{2212}×÷=<>%$.") + [(.speakLine, 1.5)],
                [(.character(":00"), 1.5), (.character(":15"), 1.5), (.character(":30"), 1.5),
                 (.character(":45"), 1.5), (.character("/"), 1.5), (.character(":"), 1.5),
                 (.mathHelp, 2.5)],
                [(.switchTo(page: Self.qwerty.pageKey, label: Self.qwerty.switchLabel), 2),
                 (.switchTo(page: Self.abc.pageKey, label: Self.abc.switchLabel), 2),
                 (.switchTo(page: Self.calculator.pageKey, label: Self.calculator.switchLabel), 2),
                 (.space, 3),
                 (.deleteWord, 2.5)],
            ])
        case .calculator:
            return compactRows
        }
    }

    /// The keyboard the rail's Keyboard button opens: the one chosen in
    /// Settings, unless the board's navigation bar already links to it — a
    /// second way to the same place is a wasted button — when it becomes the
    /// next of Calculator, Numbers, QWERTY, ABC the bar doesn't have (Mark,
    /// 2026-11-20: Brandi's board has Keyboard in its bar).
    static func railTarget(preferred: KeyboardLayout, inBar: Set<KeyboardLayout>) -> KeyboardLayout {
        [preferred, .calculator, .numbers, .qwerty, .abc].first { !inBar.contains($0) } ?? preferred
    }

    /// The rail button's face when it opens this keyboard.
    var railTitle: String {
        switch self {
        case .qwerty: "Keyboard"
        case .abc: "ABC"
        case .numbers: "Numbers"
        case .calculator: "Calculator"
        }
    }

    var railImage: String {
        switch self {
        case .qwerty, .abc: "keyboard"
        case .numbers: "textformat.123"
        case .calculator: "plus.forwardslash.minus"
        }
    }

    /// The name on the key that switches to this keyboard.
    var switchLabel: String {
        switch self {
        case .qwerty: "QWERTY"
        case .abc: "ABC"
        case .numbers: "123"
        case .calculator: "Calc"
        }
    }

    /// A letter keyboard's bottom row: the numbers, the other letter
    /// keyboard, space, delete word.
    private func bottom(switchingTo other: KeyboardLayout) -> [(KeyboardKey.Action, Double)] {
        [(.switchTo(page: Self.numbers.pageKey, label: Self.numbers.switchLabel), 2),
         (.switchTo(page: other.pageKey, label: other.switchLabel), 2),
         (.space, 5),
         (.deleteWord, 2.5)]
    }

    private func letters(_ s: String) -> [(KeyboardKey.Action, Double)] {
        s.map { (.character(String($0)), 1) }
    }

    private func marks(_ s: String) -> [(KeyboardKey.Action, Double)] {
        s.map { (.character(String($0)), 1) }
    }

    private static func build(_ rows: [[(KeyboardKey.Action, Double)]]) -> [[KeyboardKey]] {
        rows.enumerated().map { r, row in
            row.enumerated().map { c, key in
                KeyboardKey(action: key.0, width: key.1, id: "\(r).\(c)")
            }
        }
    }
}
