// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileIdentityCollisionTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct TileIdentityCollisionTests {

    /// Vocabulary keys that are also the name of their own wordClass.
    ///
    /// These are the collision: a link tile is keyed for the class it opens,
    /// and the destination page is built by expanding that class — so the page
    /// you land on contains a tile with the link's own key.
    private func selfNamedClasses() throws -> [String] {
        // Bundle.main — the tests run hosted in the app, and vocabulary.json
        // ships in the app bundle, not the test bundle.
        let url = try #require(Bundle.main.url(forResource: "vocabulary",
                                               withExtension: "json"))
        struct Entry: Decodable { let key: String; let wordClass: String }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        return entries.filter { $0.key == $0.wordClass }.map(\.key).sorted()
    }

    /// The reason `TileGridView` scopes tile identity to the page.
    ///
    /// `ForEach(tiles, id: \.key)` on its own makes a tile the same SwiftUI
    /// view on every page it appears on, so its `@State` — including a press
    /// animation still running — survives navigation. Tapping a link then
    /// finished the bounce on the *destination* page, on the tile sharing the
    /// link's name.
    ///
    /// If this list ever empties, the collision has gone and the `.id()` in
    /// `tileCellView` looks like dead weight. It is not: the collision is a
    /// property of this vocabulary, not of SwiftUI, and any scene a caregiver
    /// authors can reintroduce it. Read the comment there before removing it.
    @Test func vocabularyContainsSelfNamedClassKeys() throws {
        let selfNamed = try selfNamedClasses()
        #expect(!selfNamed.isEmpty)
        // The seven reachable from the shipped home board.
        for expected in ["actions", "describe", "drinks", "people",
                         "places", "social", "weather"] {
            #expect(selfNamed.contains(expected),
                    "'\(expected)' should still be its own wordClass")
        }
    }

    /// `food` is deliberately NOT one of them — it is classed `navigation`,
    /// which is why tapping Food was the one link that looked fine and made
    /// the bug read as intermittent rather than systematic.
    @Test func foodIsClassedAsNavigationNotFood() throws {
        #expect(!(try selfNamedClasses()).contains("food"))
    }
}
}
