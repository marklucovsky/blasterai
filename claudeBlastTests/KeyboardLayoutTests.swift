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
    @Test(arguments: KeyboardLayout.allCases)
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

    /// QWERTY's switch key opens ABC and back.
    @Test func theKeyboardsSwitchToEachOther() {
        func switchTarget(_ layout: KeyboardLayout) -> String? {
            layout.rows.flatMap { $0 }.compactMap { key -> String? in
                if case .switchTo(let page, _) = key.action { return page }
                return nil
            }.first
        }
        #expect(switchTarget(.qwerty) == KeyboardLayout.abc.pageKey)
        #expect(switchTarget(.abc) == KeyboardLayout.qwerty.pageKey)
    }

    @Test func aPageIsAKeyboardByItsKey() {
        #expect(KeyboardLayout.forPage("keyboard") == .qwerty)
        #expect(KeyboardLayout.forPage("<system>:keyboard") == .qwerty)
        #expect(KeyboardLayout.forPage("<system>:keyboard_abc") == .abc)
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
