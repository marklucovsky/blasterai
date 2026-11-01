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
