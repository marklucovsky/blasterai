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
    }

    let action: Action
    /// In key-widths; a letter is 1.
    let width: Double
    /// Position in its layout, so two keys alike are still two keys.
    let id: String

    var isVowel: Bool {
        if case .character(let c) = action { return KeyboardLayout.vowels.contains(c.lowercased()) }
        return false
    }
}

enum KeyboardLayout: String, CaseIterable {
    case qwerty, abc

    /// The BlasterAI 60 page each keyboard is. `sys:keyboard` is QWERTY, the
    /// keyboard the rail's Keyboard button has always opened.
    var pageKey: String {
        switch self {
        case .qwerty: "keyboard"
        case .abc: "keyboard_abc"
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
        }
    }

    /// The name on the key that switches to this keyboard.
    var switchLabel: String {
        switch self {
        case .qwerty: "QWERTY"
        case .abc: "ABC"
        }
    }

    private func bottom(switchingTo other: KeyboardLayout) -> [(KeyboardKey.Action, Double)] {
        [(.switchTo(page: other.pageKey, label: other.switchLabel), 2),
         (.space, 7),
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
