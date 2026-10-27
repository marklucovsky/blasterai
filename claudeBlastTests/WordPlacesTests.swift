// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordPlacesTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {

/// "Find a button": where a word is on the boards, as the taps that reach it.
/// Pinned against the bundled board, so a placement edit that strands a word
/// or reroutes a folder shows up here.
@MainActor
@Suite(.serialized)
struct WordPlacesTests {

    private static let ipad = (cols: 10, rows: 6)

    /// The iPhone's 4 × 6: since session 14 every BlasterAI 60 page fits one
    /// iPad screen, so screens are only exercised on a phone.
    private static let phone = (cols: 4, rows: 6)

    private func places(hidden: Set<String> = [],
                        grid: (cols: Int, rows: Int) = ipad) -> [String: [WordPlace]] {
        let scene = BootstrapLoader.loadDefaultVocabulary(context: TestStore.freshContainer().mainContext).scene
        return WordPlaces.index(scene: scene, hidden: hidden, grid: grid)
    }

    @Test func aFolderWordIsReachedThroughItsFolders() {
        // `horse`: `dog` is on Things itself since session 14.
        let horse = places()["horse"] ?? []
        // The `groups` hub is named Things (session 14, after Avaz).
        #expect(horse.first?.route == ["Things", "Animals"])
        #expect(horse.first?.label == "BlasterAI 60 › Things › Animals")
    }

    @Test func aHomeWordSaysHome() {
        let eat = places()["eat"] ?? []
        #expect(eat.first?.route == [])
        #expect(eat.first?.label == "BlasterAI 60 › Home")
    }

    /// Every home, not just one: `hurt` is on Feelings, Body & Health and
    /// Actions since the session-8 placement pass — on Actions' Thinking folder,
    /// and on Health once Body & health split, since session 14.
    @Test func everyPlaceIsListed() {
        let pages = Set((places()["hurt"] ?? []).compactMap(\.route.last))
        #expect(pages.isSuperset(of: ["Feelings", "Health", "Thinking"]), "\(pages)")
    }

    /// On a 4 × 6 phone grid Actions' screen 2 starts at its 21st tile (row 1
    /// is the system row, so a screen holds 20). A hidden word earlier on the page holds its cell, as on the
    /// board, so it moves nothing — and is not a place itself.
    @Test func screensFollowTheGridAndHiddenWordsHoldTheirCells() {
        let onActions = { (places: [String: [WordPlace]], word: String) in
            (places[word] ?? []).first { $0.route.last == "Actions" }
        }
        let phone = places(grid: Self.phone)
        // `write` opens Actions' third row, the 21st tile: the first word of
        // screen 2. `need`, on its second row, is on screen 1.
        #expect(onActions(phone, "write")?.screen == 2)
        #expect(onActions(phone, "write")?.label.hasSuffix("· screen 2") == true)
        #expect(onActions(phone, "need")?.screen == 1)
        let withHidden = places(hidden: ["need"], grid: Self.phone)
        #expect(onActions(withHidden, "write")?.screen == 2)
        #expect(onActions(withHidden, "need") == nil)
        // On the iPad every page is one screen.
        #expect(onActions(places(), "write")?.screen == 1)
    }

    /// Shortest route wins, and a page no folder reaches is reported as such
    /// rather than dropped — the word is in the scene, the child can't get to it.
    @Test func routesAreShortestAndOrphansAreFlagged() {
        let pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "a", link: "a"), TileEntry(key: "b", link: "b")]),
            PageSpec(key: "a", tiles: [TileEntry(key: "to_b", link: "b"), TileEntry(key: "back", link: TileToken.home)]),
            PageSpec(key: "b", tiles: [TileEntry(key: "dog")]),
            PageSpec(key: "orphan", tiles: [TileEntry(key: "cat")]),
        ]
        let routes = WordPlaces.routesFromHome(pages: pages, homeKey: "home")
        #expect(routes["b"] == ["B"])
        #expect(routes["home"] == [])
        #expect(routes["orphan"] == nil)

        let orphan = WordPlace(sceneName: "S", route: [], pageTitle: "Orphan", screen: 1, isReachable: false)
        #expect(orphan.label == "S › Orphan (no folder leads here)")
    }

    @Test func everyBundledWordIsSomewhere() {
        let index = places()
        let stranded = index.values.flatMap { $0 }.filter { !$0.isReachable }
        #expect(stranded.isEmpty, "\(stranded.map(\.label))")
        for word in ["because", "but", "will", "lets", "one", "chicken", "police_car"] {
            #expect(index[word]?.isEmpty == false, "\(word)")
        }
    }
}
}
