// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MeSceneTests.swift
//  claudeBlastTests
//
//  The Me page and My Topics: mounted scenes under the system board.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct MeSceneTests {

    private func topic(_ name: String, id: String, words: [String],
                       in ctx: ModelContext) -> BlasterScene {
        let scene = BlasterScene(name: name)
        scene.sceneID = id
        scene.designedFor = PageTemplate.designedFor
        scene.pages = [PageSpec(key: "home", tiles: words.map { TileEntry(key: $0) })]
        ctx.insert(scene)
        return scene
    }

    // MARK: - The namespace

    @Test func aSceneLinkRoundTrips() {
        let link = TileToken.sceneLink("me-abc", to: "my_topics")
        #expect(link == "<scene:me-abc>:my_topics")
        let parsed = TileToken.scenePageKey(link)
        #expect(parsed?.sceneID == "me-abc")
        #expect(parsed?.page == "my_topics")
        #expect(TileToken.scenePageKey("<system>:actions") == nil)
        #expect(TileToken.scenePageKey("actions") == nil)
        #expect(TileToken.scenePageKey("<scene:>:home") == nil)
    }

    @Test func aFolderOnAMountedPageStaysInItsScene() {
        let to = SystemLinks.destination(of: "family", fromPage: "<scene:s1>:home",
                                         homePageKey: "home", systemHomePageKey: "home")
        #expect(to == "<scene:s1>:family")
    }

    @Test func homeAndSystemLinksFromAMountedPageLeaveIt() {
        let from = "<scene:s1>:family"
        #expect(SystemLinks.destination(of: TileToken.home, fromPage: from,
                                        homePageKey: "home", systemHomePageKey: "home") == "home")
        #expect(SystemLinks.destination(of: "<system>:people", fromPage: from,
                                        homePageKey: "home", systemHomePageKey: "home") == "<system>:people")
        #expect(SystemLinks.destination(of: "<scene:s2>:home", fromPage: from,
                                        homePageKey: "home", systemHomePageKey: "home") == "<scene:s2>:home")
    }

    /// Mark, 2026-11-01: a Me page doorway to `<system>:i_page`, pressed with
    /// BlasterAI 60 as the board, showed "This Scene Has No Home Page".
    @Test func aSystemLinkFromAMountedPageOntoTheSystemBoardIsPlain() {
        let from = "<scene:me-p1>:home"
        #expect(SystemLinks.destination(of: "<system>:i_page", fromPage: from, homePageKey: "home",
                                        systemHomePageKey: "home", systemIsActive: true) == "i_page")
        #expect(SystemLinks.destination(of: "<system>:home", fromPage: from, homePageKey: "home",
                                        systemHomePageKey: "home", systemIsActive: true) == "home")
        // Another scene active: BlasterAI 60's page keeps its namespace.
        #expect(SystemLinks.destination(of: "<system>:i_page", fromPage: from, homePageKey: "home",
                                        systemHomePageKey: "home") == "<system>:i_page")
    }

    /// Mark, 2026-11-01: Me, then row 1's Actions, showed Home; the second
    /// press opened Actions.
    @Test func rowOneUnderAMountedPageOpensTheBoardsPage() {
        let ctx = TestStore.freshContainer().mainContext
        let system = BlasterScene(name: "BlasterAI 60")
        system.isDefault = true
        ctx.insert(system)
        let from = "<scene:me-p1>:home"
        let row = BoardChrome.row(for: system, level: nil, underMountedPage: true)
        #expect(row.contains { $0.link.hasSuffix("actions") })
        for entry in row {
            let to = SystemLinks.destination(of: entry.link, fromPage: from, homePageKey: "home",
                                             systemHomePageKey: "home", systemIsActive: true)
            #expect(TileToken.scenePageKey(to) == nil, "\(entry.key) opened \(to)")
            #expect(TileToken.systemPageKey(to) == nil)
        }
        // On the board's own pages the row is unchanged.
        #expect(BoardChrome.row(for: system, level: nil).allSatisfy { TileToken.systemPageKey($0.link) == nil })
    }

    @Test func aMountedKeyShowsThatScenesPage() {
        let mounted = [PageSpec(key: "home", tiles: [TileEntry(key: "church")])]
        let page = SystemLinks.page(forKey: "<scene:s1>:home", scenePages: [], systemPages: [],
                                    mountedPages: { $0 == "s1" ? mounted : nil })
        #expect(page?.tiles.map(\.key) == ["church"])
        let gone = SystemLinks.page(forKey: "<scene:s9>:home", scenePages: [], systemPages: [],
                                    mountedPages: { $0 == "s1" ? mounted : nil })
        #expect(gone == nil)
    }

    // MARK: - The Me scene

    @Test func ensureMakesOneMeSceneWithMyTopics() throws {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let again = MeScene.ensure(profileID: "p1", context: ctx)
        #expect(me.persistentModelID == again.persistentModelID)
        #expect(me.sceneID == "me-p1")
        #expect(MeScene.isMeScene(me))
        #expect(BoardChrome.inherits(me))
        #expect(me.page(withKey: "home")?.tiles.first?.link == MeScene.topicsPageKey)
        #expect(me.page(withKey: "home")?.tiles.first?.label == "My Topics")
        #expect(me.page(withKey: MeScene.topicsPageKey) != nil)
        let all = try ctx.fetch(FetchDescriptor<BlasterScene>())
        #expect(all.filter(MeScene.isMeScene).count == 1)
    }

    @Test func ensureRepairsARemovedTopicsPage() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        me.pages = me.pages.filter { $0.key != MeScene.topicsPageKey }
        MeScene.ensure(profileID: "p1", context: ctx)
        #expect(me.page(withKey: MeScene.topicsPageKey) != nil)
    }

    @Test func topicsAreAddedInOrderOnceAndRemoved() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let church = topic("Sunday School", id: "s1", words: ["church", "sing"], in: ctx)
        let zoo = topic("Zoo", id: "s2", words: ["lion"], in: ctx)
        MeScene.addTopic(church, to: me, context: ctx)
        MeScene.addTopic(zoo, to: me, context: ctx)
        MeScene.addTopic(church, to: me, context: ctx)
        #expect(MeScene.topicIDs(in: me) == ["s1", "s2"])
        let first = MeScene.topicEntries(in: me).first
        #expect(first?.key == SceneCover.key(for: church))
        #expect(first?.label == "Sunday School")
        #expect(first?.link == "<scene:s1>:home")
        MeScene.removeTopic(sceneID: "s1", from: me)
        #expect(MeScene.topicIDs(in: me) == ["s2"])
    }

    // MARK: - Covers

    @Test func aTopicIsItsSceneCoverBorrowingTheFirstWord() throws {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let church = topic("Church", id: "first/church", words: ["sing", "pray"], in: ctx)
        let choir = topic("Choir", id: "first/choir", words: ["sing", "song"], in: ctx)
        MeScene.addTopic(church, to: me, context: ctx)
        MeScene.addTopic(choir, to: me, context: ctx)
        let keys = MeScene.topicEntries(in: me).map(\.key)
        #expect(keys == ["scenecover_first_church", "scenecover_first_choir"])
        let covers = try ctx.fetch(FetchDescriptor<TileModel>())
            .filter { $0.key.hasPrefix(SceneCover.prefix) }
        // Same picture, separate tiles: a shared picture no longer collides.
        #expect(covers.map(\.bundleImage).sorted() == ["sing", "sing"])
        #expect(covers.allSatisfy { $0.wordClass == PageLink.wordClass })
        #expect(covers.contains { $0.displayName == "Church" })
    }

    @Test func aPickedCoverIsKeptAndAWordReplacesAPhoto() {
        let ctx = TestStore.freshContainer().mainContext
        let zoo = topic("Zoo", id: "s1", words: ["lion", "tiger"], in: ctx)
        let cover = SceneCover.ensure(for: zoo, context: ctx)
        cover.userImageData = Data([1, 2, 3])
        SceneCover.ensure(for: zoo, context: ctx)
        #expect(cover.hasUserImage)
        #expect(cover.bundleImage == "lion")
        SceneCover.use(word: "tiger", on: cover)
        #expect(!cover.hasUserImage)
        #expect(SceneCover.ensure(for: zoo, context: ctx).bundleImage == "tiger")
    }

    @Test func coverWordsAreTheScenesWordsHomeFirst() {
        let ctx = TestStore.freshContainer().mainContext
        let scene = topic("Farm", id: "s1", words: ["cow"], in: ctx)
        scene.pages = [PageSpec(key: "animals", tiles: [TileEntry(key: "pig"), TileEntry(key: "cow")]),
                       PageSpec(key: "home", tiles: [TileEntry(key: "page_animals", link: "animals"),
                                                     .spacer(), TileEntry(key: "cow")])]
        #expect(SceneCover.candidateWords(of: scene) == ["cow", "pig"])
        #expect(SceneCover.defaultWord(of: scene) == "cow")
    }

    @Test func onlyTemplateScenesCanBeTopics() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let flat = topic("Flat", id: "s1", words: ["cat"], in: ctx)
        flat.designedFor = ""
        #expect(!MeScene.isEligibleTopic(flat))
        #expect(!MeScene.isEligibleTopic(me))
        MeScene.addTopic(flat, to: me, context: ctx)
        #expect(MeScene.topicIDs(in: me).isEmpty)
    }

    @Test func topicsFillColumnsOneToEight() {
        let entries = (0..<10).map { TileEntry(key: "w\($0)", link: "<scene:s\($0)>:home") }
        let tiles = MeScene.layout(entries)
        let cols = PageTemplate.cols
        for (index, entry) in tiles.enumerated() where !entry.isSpacer {
            #expect(index % cols < 8, "\(entry.key) landed in column \(index % cols + 1)")
        }
        #expect(tiles.filter { !$0.isSpacer }.map(\.key) == entries.map(\.key))
    }

    @Test func deletingASceneTakesItOffEveryMyTopics() {
        let ctx = TestStore.freshContainer().mainContext
        let a = MeScene.ensure(profileID: "p1", context: ctx)
        let b = MeScene.ensure(profileID: "p2", context: ctx)
        let zoo = topic("Zoo", id: "s1", words: ["lion"], in: ctx)
        MeScene.addTopic(zoo, to: a, context: ctx)
        MeScene.addTopic(zoo, to: b, context: ctx)
        MeScene.removeTopicEverywhere(sceneID: "s1", context: ctx)
        #expect(MeScene.topicIDs(in: a).isEmpty)
        #expect(MeScene.topicIDs(in: b).isEmpty)
    }

    @Test func refreshRelabelsAndMovesAnOldTopicOntoItsCover() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let zoo = topic("Zoo", id: "s1", words: ["lion"], in: ctx)
        // A topic from before covers: keyed by a borrowed word.
        var pages = me.pages
        let i = pages.firstIndex { $0.key == MeScene.topicsPageKey }!
        pages[i].tiles = [TileEntry(key: "lion", link: "<scene:s1>:home", isAudible: false, label: "Zoo")]
        me.pages = pages
        zoo.name = "The Zoo"
        MeScene.refresh(in: me, scenes: ["s1": zoo], context: ctx)
        let entry = MeScene.topicEntries(in: me).first
        #expect(entry?.label == "The Zoo")
        #expect(entry?.key == SceneCover.key(for: zoo))
        #expect(SceneCover.find(for: zoo, context: ctx)?.displayName == "The Zoo")
    }

    @Test func twoDevicesMeScenesCollapseToOne() throws {
        let ctx = TestStore.freshContainer().mainContext
        for _ in 0..<2 {
            let scene = BlasterScene(name: "Me")
            scene.sceneID = MeScene.sceneID(forProfileID: "p1")
            ctx.insert(scene)
        }
        CloudKitDedupReconciler.reconcile(context: ctx)
        let left = try ctx.fetch(FetchDescriptor<BlasterScene>()).filter(MeScene.isMeScene)
        #expect(left.count == 1)
    }

    // MARK: - Contexts

    @Test func aTopicIsShownOnTheContextsChosenAndAnEmptyPageGoes() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let farm = topic("Farm", id: "s1", words: ["cow"], in: ctx)
        let zoo = topic("Zoo", id: "s2", words: ["lion"], in: ctx)
        let titles = ["i_page": "I", "people": "People"]
        MeScene.setContexts(["i_page", "people"], for: farm, in: me, context: ctx, titles: titles)
        MeScene.setContexts(["i_page"], for: zoo, in: me, context: ctx, titles: titles)
        #expect(Set(MeScene.contexts(of: "s1", in: me)) == ["i_page", "people"])
        let onI = me.page(withKey: MeScene.contextPageKey(for: "i_page"))
        #expect(onI?.displayName == "On I")
        #expect(onI?.tiles.map(\.label) == ["Farm", "Zoo"])
        MeScene.setContexts(["i_page"], for: farm, in: me, context: ctx, titles: titles)
        #expect(MeScene.contexts(of: "s1", in: me) == ["i_page"])
        #expect(me.page(withKey: MeScene.contextPageKey(for: "people")) == nil)
    }

    @Test func contextEntriesReadPlainKeysWhenTheSystemIsTheBoard() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let farm = topic("Farm", id: "s1", words: ["cow"], in: ctx)
        MeScene.setContexts(["i_page"], for: farm, in: me, context: ctx, titles: [:])
        #expect(MeScene.contextEntries(forNavKey: "i_page", systemIsActive: true, in: me).count == 1)
        #expect(MeScene.contextEntries(forNavKey: "<system>:i_page", systemIsActive: false, in: me).count == 1)
        #expect(MeScene.contextEntries(forNavKey: "i_page", systemIsActive: false, in: me).isEmpty)
        #expect(MeScene.contextEntries(forNavKey: "<scene:s1>:home", systemIsActive: true, in: me).isEmpty)
    }

    @Test func removingATopicTakesItOffItsContextsAndRefreshKeepsThemCurrent() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        let farm = topic("Farm", id: "s1", words: ["cow"], in: ctx)
        MeScene.addTopic(farm, to: me, context: ctx)
        MeScene.setContexts(["i_page"], for: farm, in: me, context: ctx, titles: [:])
        farm.name = "The Farm"
        MeScene.refresh(in: me, scenes: ["s1": farm], context: ctx)
        #expect(me.page(withKey: MeScene.contextPageKey(for: "i_page"))?.tiles.first?.label == "The Farm")
        MeScene.removeTopic(sceneID: "s1", from: me)
        #expect(MeScene.contexts(of: "s1", in: me).isEmpty)
        #expect(me.page(withKey: MeScene.contextPageKey(for: "i_page")) == nil)
    }

    @Test func theRegionFillsColumnEightThenNineThenTenAroundTheAuthor() {
        let cols = PageTemplate.cols
        let rows = PageTemplate.rows - 1
        // The author put My Topics at column 8, row 2 and a link at column 9, row 1.
        var home = Array(repeating: TileEntry.spacer(), count: rows * cols)
        home[0] = TileEntry(key: "favorite", link: "my_topics")
        home[1 * cols + 7] = TileEntry(key: "mine_a", link: "a")
        home[0 * cols + 8] = TileEntry(key: "mine_b", link: "b")
        let region = (0..<(rows + 2)).map { TileEntry(key: "t\($0)", link: "<scene:s\($0)>:home") }
        let tiles = MeScene.withRegion(home, region: region)
        let placed = region.map { r in tiles.firstIndex { $0.key == r.key } }
        // Column 8, skipping the author's cell, then column 9 below its link.
        let expected = [0, 2, 3, 4].map { $0 * cols + 7 } + [1, 2, 3].map { $0 * cols + 8 }
        #expect(placed.compactMap { $0 } == expected)
        #expect(tiles[1 * cols + 7].key == "mine_a")
        #expect(tiles[0 * cols + 8].key == "mine_b")
        #expect(tiles[0].key == "favorite")
    }

    @Test func theContextIsTheLastBoardPageInTheHistory() {
        let me = "<scene:me-p1>:home"
        #expect(MeScene.contextKey(inHistory: ["home", "i_page", me]) == "i_page")
        #expect(MeScene.contextKey(inHistory: ["home", "i_page", me, "<scene:me-p1>:my_topics", me]) == "i_page")
        #expect(MeScene.contextKey(inHistory: ["home", me]) == nil)
        #expect(MeScene.contextKey(inHistory: ["home"]) == nil)
    }

    @Test func aRegionWithNothingInItLeavesTheHomeAlone() {
        let home = [TileEntry(key: "favorite", link: "my_topics")]
        #expect(MeScene.withRegion(home, region: []) == home)
    }

    // MARK: - Context items: inline words and board pages

    private func words(_ keys: [String]) -> [TileEntry] { keys.map { TileEntry(key: $0) } }

    /// Me home with the My Topics folder at r2c1, as `ensure` makes it.
    private var meHome: [TileEntry] { [MeScene.topicsFolder] }

    @Test func inlineTakesNOrAllWordsAndSkipsFoldersAndRepeats() {
        let source = [TileEntry(key: "page_animals", link: "animals"), TileEntry(key: "cow"),
                      .spacer(), TileEntry(key: "go", link: "places"), TileEntry(key: "pig"),
                      TileEntry(key: "hen"), TileEntry(key: "more")]
        func inlined(_ n: Int?, rowKeys: Set<String> = []) -> [String] {
            let item = TileEntry(key: "scenecover_s1", link: "<scene:s1>:home", isAudible: false,
                                 inline: n, hidesFolder: true)
            return MeScene.compose(meHome, items: [item], rowKeys: rowKeys) { _ in source }
                .filter { !$0.isSpacer && $0.key != MeScene.topicsFolderKey }.map(\.key)
        }
        #expect(inlined(2) == ["cow", "pig"])
        #expect(inlined(TileEntry.inlineAll) == ["cow", "pig", "hen", "more"])
        #expect(inlined(nil).isEmpty)
        #expect(inlined(TileEntry.inlineAll, rowKeys: ["more"]) == ["cow", "pig", "hen"])
    }

    @Test func inlineGoesBelowTheAuthorAfterAnEmptyRow() {
        let cols = PageTemplate.cols
        let tiles = MeScene.placeInline(meHome, words: words(["a", "b", "c", "d", "e", "f", "g", "h"]))
        // Author's last row is row 0; row 1 stays empty; columns 1–7 from row 2.
        #expect((0..<cols).allSatisfy { tiles.indices.contains(cols + $0) == false || tiles[cols + $0].isSpacer })
        #expect(Array(tiles[(2 * cols)..<(2 * cols + 7)]).map(\.key) == ["a", "b", "c", "d", "e", "f", "g"])
        #expect(tiles[3 * cols].key == "h")
        #expect(tiles[2 * cols + 7].isSpacer)
    }

    @Test func inlineDropsTheBufferWhenTightThenTakesEveryFreeCell() {
        let cols = PageTemplate.cols
        let rows = PageTemplate.rows - 1
        // The author used rows 0 to rows-3 in column 1: one row is left after
        // a buffer, two without one.
        var home = Array(repeating: TileEntry.spacer(), count: rows * cols)
        for row in 0..<(rows - 2) { home[row * cols] = TileEntry(key: "mine\(row)") }
        let many = words((0..<20).map { "w\($0)" })
        let tiles = MeScene.placeInline(home, words: many)
        #expect(tiles[(rows - 2) * cols].key == "w0")  // no buffer: 8 words need 2 rows
        #expect(tiles[(rows - 1) * cols + 6].key == "w13")  // columns 1–7 first
        // Then every free cell in reading order: row 0's columns 2–10 first.
        #expect(tiles[1].key == "w14")
        #expect(tiles.filter { $0.key.hasPrefix("w") }.count == 20)
        #expect((0..<(rows - 2)).allSatisfy { tiles[$0 * cols].key == "mine\($0)" })
        // A full page leaves the rest off.
        let flood = MeScene.placeInline(home, words: words((0..<100).map { "f\($0)" }))
        #expect(flood.count == rows * cols)
        #expect(flood.allSatisfy { !$0.isSpacer })
        let few = MeScene.placeInline(home, words: words(["x"]))
        #expect(few[(rows - 1) * cols].key == "x")       // room for the buffer
    }

    @Test func foldersGoToTheRegionAndWordsOnlyHidesOne() {
        let cols = PageTemplate.cols
        let folder = TileEntry(key: "page_play", link: "<system>:play", isAudible: false, label: "Play")
        var wordsOnly = TileEntry(key: "scenecover_s1", link: "<scene:s1>:home", isAudible: false,
                                  inline: 1, hidesFolder: true)
        let tiles = MeScene.compose(meHome, items: [wordsOnly, folder], rowKeys: []) { item in
            item.link == folder.link ? self.words(["ball"]) : self.words(["cow"])
        }
        #expect(tiles[7].key == "page_play")
        #expect(tiles[7].inline == nil && !tiles[7].isAudible)
        #expect(!tiles.contains { $0.key == "scenecover_s1" })
        #expect(tiles[2 * cols].key == "cow")
        wordsOnly.hidesFolder = false
        let both = MeScene.compose(meHome, items: [wordsOnly], rowKeys: []) { _ in self.words(["cow"]) }
        #expect(both[7].key == "scenecover_s1")
    }

    @Test func setItemReplacesTheSameSourceAndAnEmptyPageGoes() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        var item = TileEntry(key: "page_play", link: "<system>:play", isAudible: false, label: "Play")
        MeScene.setItem(item, onPage: "i_page", in: me, title: "I")
        item.inline = 4
        MeScene.setItem(item, onPage: "i_page", in: me, title: "I")
        let page = me.page(withKey: MeScene.contextPageKey(for: "i_page"))
        #expect(page?.tiles.count == 1)
        #expect(page?.tiles.first?.inline == 4)
        #expect(page?.displayName == "On I")
        MeScene.removeItem(link: "<system>:play", fromPage: "i_page", in: me)
        #expect(me.page(withKey: MeScene.contextPageKey(for: "i_page")) == nil)
    }

    @Test func wordItemsInlineInListOrderAmongSources() {
        let source = TileEntry(key: "scenecover_s1", link: "<scene:s1>:home", isAudible: false,
                               inline: 2, hidesFolder: true)
        let items = [TileEntry(key: "want"), source, TileEntry(key: "help"), TileEntry(key: "more")]
        let tiles = MeScene.compose(meHome, items: items, rowKeys: ["more"]) { _ in
            self.words(["cow", "want", "pig"])
        }
        let placed = tiles.filter { !$0.isSpacer && $0.key != MeScene.topicsFolderKey }
        // "want" is listed first, so the source's copy is skipped; "more" is in row 1.
        #expect(placed.map(\.key) == ["want", "cow", "pig", "help"])
        // A word is never a folder: column 8 stays free.
        #expect(tiles[7].isSpacer)
        #expect(placed.allSatisfy { $0.isAudible && $0.link.isEmpty })
    }

    @Test func addWordsKeepsTapOrderAndSkipsListedWords() {
        let ctx = TestStore.freshContainer().mainContext
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        MeScene.addWords(["want", "more"], onPage: "i_page", in: me, title: "I")
        MeScene.setItem(TileEntry(key: "page_play", link: "<system>:play", isAudible: false),
                        onPage: "i_page", in: me, title: "I")
        MeScene.addWords(["help", "want"], onPage: "i_page", in: me, title: "I")
        let page = me.page(withKey: MeScene.contextPageKey(for: "i_page"))
        #expect(page?.displayName == "On I")
        #expect(page?.tiles.map(\.key) == ["want", "more", "page_play", "help"])
        // Removing a source leaves the words alone.
        MeScene.removeItem(link: "<system>:play", fromPage: "i_page", in: me)
        #expect(me.page(withKey: MeScene.contextPageKey(for: "i_page"))?.tiles.map(\.key)
                == ["want", "more", "help"])
    }

    @Test func aBoardPageItemOpensThatPageFromMe() {
        let from = "<scene:me-p1>:home"
        #expect(SystemLinks.destination(of: "<system>:play", fromPage: from, homePageKey: "home",
                                        systemHomePageKey: "home", systemIsActive: true) == "play")
        #expect(SystemLinks.destination(of: "<system>:play", fromPage: from, homePageKey: "home",
                                        systemHomePageKey: "home") == "<system>:play")
    }

    @Test func aFolderBorrowsThePictureOfTheTileThatOpensItsPage() {
        let scene = BlasterScene(name: "BlasterAI 60")
        scene.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "play", link: "play_page")])]
        #expect(MeScene.folderKey(forPage: "play_page", in: scene) == "play")
        #expect(MeScene.folderKey(forPage: "nowhere", in: scene) == PageLink.key(forPage: "nowhere"))
    }

    @Test func inlineSettingsSurviveTheStoreAndWriteNothingWhenUnset() throws {
        let entry = TileEntry(key: "page_play", link: "<system>:play", isAudible: false,
                              inline: TileEntry.inlineAll, hidesFolder: true)
        let back = try JSONDecoder().decode(TileEntry.self, from: JSONEncoder().encode(entry))
        #expect(back.inline == TileEntry.inlineAll)
        #expect(back.hidesFolder)
        let plain = String(decoding: try JSONEncoder().encode(TileEntry(key: "eat")), as: UTF8.self)
        #expect(!plain.contains("inline") && !plain.contains("hidesFolder"))
    }

    // MARK: - TileEntry.label

    @Test func aLabelSurvivesTheStore() throws {
        let entry = TileEntry(key: "church", link: "<scene:s1>:home", isAudible: false,
                              label: "Sunday School")
        let data = try JSONEncoder().encode([entry])
        let back = try JSONDecoder().decode([TileEntry].self, from: data)
        #expect(back.first?.label == "Sunday School")
    }

    @Test func noLabelWritesNoKey() throws {
        let data = try JSONEncoder().encode(TileEntry(key: "eat"))
        #expect(!String(decoding: data, as: UTF8.self).contains("label"))
        let back = try JSONDecoder().decode(TileEntry.self, from: data)
        #expect(back.label == nil)
    }
}
}
