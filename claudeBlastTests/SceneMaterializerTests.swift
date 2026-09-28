// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneMaterializerTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct SceneMaterializerTests {

    // Tiny test vocabulary — three classes, declaration order matters.
    static let testVocab: [TileModelCodable] = [
        .init(key: "eat",    wordClass: "actions"),
        .init(key: "drink",  wordClass: "actions"),
        .init(key: "stop",   wordClass: "actions"),
        .init(key: "mom",    wordClass: "people"),
        .init(key: "dad",    wordClass: "people"),
        .init(key: "sister", wordClass: "people"),
        .init(key: "apple",  wordClass: "food"),
        .init(key: "banana", wordClass: "food"),
    ]

    private func mat(_ pages: [PageJSON],
                     home: String = "home",
                     isDefault: Bool = true) throws -> SceneMaterializer.MaterializedScene {
        let scene = SceneJSON(
            key: "test", name: "Test",
            description: nil, homePageKey: home,
            isDefault: isDefault, pages: pages
        )
        return try SceneMaterializer.materialize(scene: scene, vocabulary: Self.testVocab)
    }

    @Test func classActions_inVocabOrder() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .classSelector(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab)
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["eat","drink","stop"])
    }

    @Test func classAlphabetical() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .classSelector(classes: ["actions"], exclude: [], limit: nil, orderBy: .name)
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["drink","eat","stop"])
    }

    @Test func classMulti_keepsVocabOrderAcrossClasses() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .classSelector(classes: ["people","food"], exclude: [], limit: nil, orderBy: .vocab)
        ])])
        // people block then food block (vocab order within the filter)
        #expect(m.pages[0].tiles.map(\.key) == ["mom","dad","sister","apple","banana"])
    }

    @Test func classWithExcludeAndLimit() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .classSelector(classes: ["people"], exclude: ["sister"], limit: 1, orderBy: .vocab)
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["mom"])
    }

    @Test func classUnknown_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "home", tiles: [
                .classSelector(classes: ["nope"], exclude: [], limit: nil, orderBy: .vocab)
            ])])
        }
    }

    @Test func keys_inOrder() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .keys(["dad","apple","stop"])
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["dad","apple","stop"])
    }

    @Test func keysUnknown_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "home", tiles: [
                .keys(["bogus"])
            ])])
        }
    }

    @Test func link_inserts_whenNotPresent() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .link(key: "mom", to: "people", audible: false, color: nil)
        ])])
        let t = m.pages[0].tiles[0]
        #expect(t.key == "mom")
        #expect(t.link == "people")
        #expect(t.isAudible == false)
    }

    @Test func link_updatesInPlace_whenPresent() throws {
        // Place the tile first via keys (audible=true, no link), then
        // link should mutate the existing tile in its current position.
        let m = try mat([PageJSON(key: "home", tiles: [
            .keys(["eat","drink","mom"]),
            .link(key: "drink", to: "drinks", audible: true, color: nil),
        ])])
        let keys = m.pages[0].tiles.map(\.key)
        #expect(keys == ["eat","drink","mom"])  // position preserved
        let drink = m.pages[0].tiles[1]
        #expect(drink.link == "drinks")
        #expect(drink.isAudible == true)
    }

    @Test func remove_removes() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .classSelector(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab),
            .remove("stop"),
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["eat","drink"])
    }

    @Test func remove_missing_isNoOp() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .keys(["mom"]),
            .remove("ghost"),
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["mom"])
    }

    @Test func mixedCommands_buildExpectedPage() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .link(key: "mom", to: "people", audible: false, color: nil),  // [mom→link]
            .keys(["eat","drink"]),                            // [mom→link, eat, drink]
            .link(key: "eat", to: "food", audible: true, color: nil),     // mutate eat
            .classSelector(classes: ["food"], exclude: [], limit: nil, orderBy: .vocab),
            .remove("banana"),
        ])])
        let entries = m.pages[0].tiles
        #expect(entries.map(\.key) == ["mom","eat","drink","apple"])
        #expect(entries[0].link == "people"); #expect(entries[0].isAudible == false)
        #expect(entries[1].link == "food");   #expect(entries[1].isAudible == true)
        #expect(entries[2].link == "");       #expect(entries[2].isAudible == true)
    }

    @Test func homePageNotFound_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "actual_home", tiles: [.keys(["mom"])])],
                        home: "wrong_home")
        }
    }

    @Test func metadataPassesThrough() throws {
        let m = try mat([PageJSON(key: "home", tiles: [.keys(["mom"])])])
        #expect(m.name == "Test")
        #expect(m.homePageKey == "home")
        #expect(m.isDefault == true)
    }

    // MARK: - Spacers

    /// A gap holds a cell and says nothing.
    @Test func spaceAppendsEmptyCells() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .keys(["mom"]), .space(2), .keys(["dad"]),
        ])])
        let tiles = m.pages[0].tiles
        #expect(tiles.count == 4)
        #expect(tiles[0].key == "mom")
        #expect(tiles[1].isSpacer)
        #expect(tiles[2].isSpacer)
        #expect(tiles[3].key == "dad")
        // The point of a spacer: the grid must not filter it out, or the board
        // reflows and every word after it moves.
        #expect(tiles[1].isEmptyCell)
    }

    /// Every spacer needs its own identity.
    ///
    /// `TileEntry.id` *is* its key, so two gaps sharing one would collide in
    /// any SwiftUI list and in the grid editor's selection. This is the reason
    /// `space` is the one command that does not dedupe: for words, a repeat is
    /// a mistake; for gaps, a repeat is the layout.
    @Test func spacersAreDistinct() throws {
        let m = try mat([PageJSON(key: "home", tiles: [.space(3)])])
        let keys = m.pages[0].tiles.map(\.key)
        #expect(keys.count == 3)
        #expect(Set(keys).count == 3)
    }

    /// `{"space": true}` — the bare form, for nudging a cluster by one cell.
    @Test func bareSpaceDecodesAsOne() throws {
        let json = #"{"space": true}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        #expect(cmd == .space(1))
    }

    /// A count decodes as itself, and a negative one is clamped rather than
    /// throwing — a bad number in a bundled scene should cost a gap, not the
    /// whole board.
    @Test func spaceCountDecodes() throws {
        func decode(_ s: String) throws -> PageBuildCommand {
            try JSONDecoder().decode(PageBuildCommand.self, from: s.data(using: .utf8)!)
        }
        #expect(try decode(#"{"space": 4}"#) == .space(4))
        #expect(try decode(#"{"space": -2}"#) == .space(0))
    }

    /// Round-trips, so a scene edited in the app and written back keeps its gaps.
    @Test func spaceSurvivesEncoding() throws {
        let original = PageBuildCommand.space(3)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PageBuildCommand.self, from: data) == original)
    }

    /// **A hand-placed prefix followed by a class selector.**
    ///
    /// This is the thing that makes per-page ordering cheap, so it is worth a
    /// test rather than an assumption. Brandi, reviewing the board: *"we want to
    /// think about the order of words in each part of speech: touch chat orders
    /// them by alpha order. Do we want them organized in a certain way?"* Ours
    /// are in vocabulary-file order, which is alphabetical only by accident —
    /// so `actions` opens on `answer, ask, bathe, blow, blush` and a child
    /// reaching for `want` has to page.
    ///
    /// The fix has to not need an exclude list, or every promotion becomes two
    /// edits that can disagree. It does not: **every command skips a key already
    /// on the page**, so naming the important words first puts them in the first
    /// cells and the class fills in behind them, each word appearing once.
    @Test func handPlacedPrefixThenClassFillsTheRest() throws {
        let vocab = [
            TileModelCodable(key: "apple", wordClass: "food"),
            TileModelCodable(key: "banana", wordClass: "food"),
            TileModelCodable(key: "cookie", wordClass: "food"),
            TileModelCodable(key: "pizza", wordClass: "food"),
        ]
        let page = PageJSON(key: "food", tiles: [
            .keys(["pizza", "cookie"]),          // what a child asks for first
            .classSelector(classes: ["food"], exclude: [], limit: nil, orderBy: .vocab),
        ])
        let scene = SceneJSON(key: "s", name: "S", description: nil,
                              homePageKey: "food", isDefault: false, pages: [page])
        let result = try SceneMaterializer.materialize(scene: scene, vocabulary: vocab)
        let keys = try #require(result.pages.first).tiles.map(\.key)

        // The named words lead, in the order given — not in vocabulary order.
        #expect(keys.prefix(2) == ["pizza", "cookie"])
        // The rest follow, and nothing is doubled.
        #expect(keys == ["pizza", "cookie", "apple", "banana"])
        #expect(Set(keys).count == keys.count)
    }

}
