// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordFinderTests.swift
//  claudeBlastTests
//
//  Find Word: the places a typed word is on the active board, the pages to
//  open to reach each, and why a place cannot be gone to.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct WordFinderTests {

    // MARK: - Fixtures

    private func bundled() -> (BlasterScene, [String: TileModel]) {
        let context = TestStore.freshContainer().mainContext
        let scene = BootstrapLoader.loadDefaultVocabulary(context: context).scene
        let tiles = (try? context.fetch(FetchDescriptor<TileModel>())) ?? []
        return (scene, Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Home: `want` always, `more` from L2, a folder to Food from L3, a spacer,
    /// and `stop` concealed. Food holds `apple` and `crème`.
    private func leveled() -> (BlasterScene, [String: TileModel]) {
        let context = TestStore.freshContainer().mainContext
        let s = BlasterScene(name: "Levels", descriptionText: "", homePageKey: "home")
        s.pages = [
            PageSpec(key: "home", tiles: [
                TileEntry(key: "want"),
                TileEntry(key: "more", revealLevel: 2),
                TileEntry(key: "food", link: "food", isAudible: false, revealLevel: 3),
                TileEntry.spacer(),
                TileEntry(key: "stop", isConcealed: true),
            ]),
            PageSpec(key: "food", tiles: [TileEntry(key: "apple"), TileEntry(key: "creme")]),
        ]
        s.revealLevelCount = 3
        s.setRevealLevel(3)
        context.insert(s)
        var lookup: [String: TileModel] = [:]
        for key in ["want", "more", "food", "stop", "apple"] {
            lookup[key] = TileModel(key: key, value: key, wordClass: "core")
        }
        lookup["creme"] = TileModel(key: "creme", value: "Crème", wordClass: "food")
        return (s, lookup)
    }

    // MARK: - Places and routes

    @Test func aFolderWordGivesThePagesToOpen() {
        let (scene, lookup) = bundled()
        let dog = WordFinder.find("dog", in: scene, lookup: lookup).first
        #expect(dog?.isAvailable == true)
        // The `groups` hub is named Things since session 14.
        #expect(dog?.route == ["Things", "Animals"])
        #expect(dog?.path.count == 2)
        #expect(dog?.path.last == dog?.pageKey, "the last page opened is the word's page")
        #expect(dog?.place == "Things › Animals")
    }

    @Test func aHomeWordOpensNothing() {
        let (scene, lookup) = bundled()
        let eat = WordFinder.find("eat", in: scene, lookup: lookup).first { $0.pageKey == scene.homePageKey }
        #expect(eat?.path == [])
        #expect(eat?.place == "Home")
    }

    @Test func theWholeWordComesFirst() {
        let (scene, lookup) = bundled()
        let results = WordFinder.find("eat", in: scene, lookup: lookup)
        #expect(results.first?.key == "eat")
        #expect(results.first?.isExact == true)
        #expect(results.contains { !$0.isExact }, "words that start with it follow")
    }

    @Test func caseAndAccentsDoNotMatter() {
        let (scene, lookup) = leveled()
        #expect(WordFinder.find("APPLE", in: scene, lookup: lookup).first?.key == "apple")
        #expect(WordFinder.find("creme", in: scene, lookup: lookup).first?.label == "Crème")
        #expect(WordFinder.find("   ", in: scene, lookup: lookup).isEmpty)
    }

    // MARK: - Places that cannot be gone to

    @Test func levelsAndConcealmentSayWhy() {
        let (scene, lookup) = leveled()
        scene.setRevealLevel(1)
        func status(_ word: String) -> WordFinder.Finding.Status? {
            WordFinder.find(word, in: scene, lookup: lookup).first?.status
        }
        #expect(status("want") == .available)
        #expect(status("more") == .aboveLevel(2))
        #expect(status("stop") == .concealed)
        // The folder to Food is above level 1, so nothing leads there — but
        // `apple` itself is on the board, so it can still be gone to: Food
        // opens on its own, and Home is the way back.
        #expect(status("apple") == .unreachable)
        let apple = WordFinder.find("apple", in: scene, lookup: lookup).first
        #expect(apple?.isAvailable == true)
        #expect(apple?.path == ["food"])
        #expect(apple?.place == "Food")
        #expect(apple?.reason == "No folder leads here · Home goes back")

        scene.setRevealLevel(3)
        #expect(status("more") == .available)
        #expect(status("apple") == .available)
        #expect(WordFinder.find("apple", in: scene, lookup: lookup).first?.path == ["food"])
    }

    @Test func wordsHiddenFromTheChildAreLeftOut() {
        let (scene, lookup) = leveled()
        lookup["apple"]?.isRetired = true
        #expect(WordFinder.find("apple", in: scene, lookup: lookup).isEmpty)
    }

    // MARK: - Return

    @Test func returnGoesOnlyWhenThereIsOnePlace() {
        let (scene, lookup) = leveled()
        #expect(WordFinder.onlyMatch(in: WordFinder.find("apple", in: scene, lookup: lookup))?.key == "apple")

        // Listed, but nowhere to go: Return does nothing.
        scene.setRevealLevel(1)
        let more = WordFinder.find("more", in: scene, lookup: lookup)
        #expect(more.count == 1 && more[0].isAvailable == false)
        #expect(WordFinder.onlyMatch(in: more) == nil)

        // "e" is in want, more, apple and crème: the caregiver chooses.
        scene.setRevealLevel(3)
        #expect(WordFinder.onlyMatch(in: WordFinder.find("e", in: scene, lookup: lookup)) == nil)
    }

    // MARK: - Going there

    /// The route is walked, not jumped: Back then retraces it, and the child's
    /// navigation log does not record the caregiver's search.
    @Test func goingThereLeavesAHistoryBackCanRetrace() {
        let coordinator = NavigationCoordinator()
        var presses = 0
        coordinator.onPress = { _, _, _ in presses += 1 }
        coordinator.show(path: ["groups", "animals"], homePageKey: "home")
        #expect(coordinator.navigationPath == ["home", "groups", "animals"])
        #expect(coordinator.currentPageKey == "animals")
        #expect(presses == 0)
        coordinator.goBack()
        #expect(coordinator.currentPageKey == "groups")

        coordinator.show(path: [], homePageKey: "home")
        #expect(coordinator.navigationPath == ["home"])
        #expect(coordinator.currentPageKey == nil)
    }

    /// The path badge: where a page sits, through folders rather than doorways.
    /// *wear* opens Clothes from Actions, but Clothes lives under Things.
    @Test func aTrailFollowsFoldersNotDoorways() {
        let (scene, _) = bundled()
        let pages = scene.visiblePages
        let home = scene.homePageKey
        #expect(WordPlaces.trail(to: "describe_how_much", pages: pages, homeKey: home)
                == ["Home", "Describe", "How much"])
        #expect(WordPlaces.trail(to: "clothes", pages: pages, homeKey: home).dropFirst().first == "Things")
        #expect(WordPlaces.trail(to: home, pages: pages, homeKey: home) == ["Home"])
    }

    @Test func keyPathsMatchTheTitledRoutes() {
        let (scene, _) = bundled()
        let pages = scene.visiblePages
        let titles = Dictionary(pages.map { ($0.key, $0.title) }, uniquingKeysWith: { a, _ in a })
        let paths = WordPlaces.pathsFromHome(pages: pages, homeKey: scene.homePageKey)
        let routes = WordPlaces.routesFromHome(pages: pages, homeKey: scene.homePageKey)
        #expect(paths.keys.sorted() == routes.keys.sorted())
        for (key, path) in paths {
            #expect(path.compactMap { titles[$0] } == routes[key])
        }
    }
}
}
