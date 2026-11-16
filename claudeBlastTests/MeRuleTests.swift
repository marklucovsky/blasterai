// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MeRuleTests.swift
//  claudeBlastTests
//
//  A Me page's rules: Always, Pinned, and the Me pages it includes, and a
//  Me page shared with what it includes. See `MeScene`.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct MeRuleTests {

    private func me(_ id: String, always: [String] = [], pinned: [Int: String] = [:],
                    in ctx: ModelContext) -> BlasterScene {
        let scene = BlasterScene(name: id, homePageKey: MeScene.homePageKey)
        scene.sceneID = "me-" + id
        scene.designedFor = PageTemplate.designedFor
        var pages = [PageSpec(key: MeScene.homePageKey, tiles: [])]
        if !always.isEmpty {
            pages.append(PageSpec(key: MeScene.alwaysPageKey, tiles: always.map { TileEntry(key: $0) }))
        }
        if !pinned.isEmpty {
            var tiles: [TileEntry] = []
            for (index, key) in pinned.sorted(by: { $0.key < $1.key }) {
                while tiles.count < index { tiles.append(.spacer()) }
                tiles.append(TileEntry(key: key))
            }
            pages.append(PageSpec(key: MeScene.pinnedPageKey, tiles: tiles))
        }
        scene.pages = pages
        ctx.insert(scene)
        return scene
    }

    private func compose(_ home: [TileEntry], _ layers: [BlasterScene], from: String? = nil) -> [TileEntry] {
        MeScene.composeHome(home, layers: layers, contextKey: from, systemIsActive: true,
                            rowKeys: [], words: { _ in [] })
    }

    private func keys(_ tiles: [TileEntry]) -> [String] {
        tiles.filter { !$0.isEmptyCell }.map(\.key)
    }

    /// Always applies when the heart is pressed from Home too, with no page
    /// the child came from: a new patient's Me page is mostly Always.
    @Test func alwaysAppliesWithNoPageToComeFrom() {
        let ctx = TestStore.freshContainer().mainContext
        let aubrey = me("aubrey", always: ["mom", "dad"], in: ctx)
        #expect(keys(compose([], [aubrey])) == ["mom", "dad"])
    }

    /// A pinned tile goes in its cell; one whose cell the page already uses
    /// moves to the next free cell instead of covering it.
    @Test func pinnedTakesItsCellUnlessThePageUsesIt() {
        let ctx = TestStore.freshContainer().mainContext
        let aubrey = me("aubrey", pinned: [0: "dog", 5: "cat"], in: ctx)
        let home = [TileEntry(key: "mine")]
        let tiles = compose(home, [aubrey])
        #expect(tiles[0].key == "mine")
        #expect(tiles[5].key == "cat")
        #expect(keys(tiles).contains("dog"))
    }

    /// Drawn twice, the composed page is the same cells with the same keys:
    /// the board names cells by key, and fresh gaps every drawing left a
    /// phone's swipe to the next screen unable to settle. A tile two layers
    /// both bring is drawn once.
    @Test func composingTwiceGivesTheSameKeys() {
        let ctx = TestStore.freshContainer().mainContext
        let aubrey = me("aubrey", always: ["mom"], pinned: [12: "dog"], in: ctx)
        let room = me("room4", always: ["mom", "teacher"], in: ctx)
        room.pages = room.pages + [PageSpec(key: MeScene.alwaysPageKey + "x", tiles: [])]
        let byID = { (id: String) in [aubrey, room].first { $0.sceneID == id } }
        MeScene.addInclude(room, to: aubrey, find: byID)
        let layers = MeScene.layers(of: aubrey, find: byID)
        let first = compose([], layers)
        let second = compose([], layers)
        #expect(first.map(\.key) == second.map(\.key))
        let keys = first.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    /// An included page's own tiles show too, in their cells when free, and
    /// a folder to one of its pages opens that page, not the host's. Its My
    /// Topics folder stays out: the child's own is already on the page.
    @Test func anIncludedPagesOwnTilesShow() {
        let ctx = TestStore.freshContainer().mainContext
        let aubrey = me("aubrey", in: ctx)
        aubrey.pages = [PageSpec(key: MeScene.homePageKey, tiles: [MeScene.topicsFolder])]
        let room = me("room4", in: ctx)
        room.pages = [PageSpec(key: MeScene.homePageKey,
                               tiles: [MeScene.topicsFolder, .spacer(), TileEntry(key: "teacher"),
                                       TileEntry(key: "recess", link: "recess_page", isAudible: false)]),
                      PageSpec(key: "recess_page", tiles: [TileEntry(key: "swing")])]
        let byID = { (id: String) in [aubrey, room].first { $0.sceneID == id } }
        MeScene.addInclude(room, to: aubrey, find: byID)
        let tiles = compose(aubrey.page(withKey: MeScene.homePageKey)!.tiles,
                            MeScene.layers(of: aubrey, find: byID))
        #expect(tiles[0].link == MeScene.topicsPageKey)          // the child's own folder
        #expect(tiles[2].key == "teacher")
        #expect(tiles[3].link == "<scene:me-room4>:recess_page")
        #expect(tiles.filter { $0.link == MeScene.topicsPageKey }.count == 1)
    }

    /// Included pages add after the page's own, in order; one switched off
    /// adds nothing; a loop or a page included twice is applied once.
    @Test func includedPagesLayerInOrderOnceEach() {
        let ctx = TestStore.freshContainer().mainContext
        let aubrey = me("aubrey", always: ["mom"], in: ctx)
        let room = me("room4", always: ["teacher"], in: ctx)
        let group = me("group", always: ["friend"], in: ctx)
        let byID = { (id: String) in [aubrey, room, group].first { $0.sceneID == id } }
        MeScene.addInclude(room, to: aubrey, find: byID)
        MeScene.addInclude(group, to: room, find: byID)
        MeScene.addInclude(group, to: aubrey, find: byID)
        let layers = MeScene.layers(of: aubrey, find: byID)
        #expect(layers.map(\.sceneID) == ["me-aubrey", "me-room4", "me-group"])
        #expect(keys(compose([], layers)) == ["mom", "teacher", "friend"])

        // Room 4 including Aubrey would make Aubrey include itself.
        #expect(MeScene.wouldLoop(adding: aubrey, to: room, find: byID))
        MeScene.addInclude(aubrey, to: room, find: byID)
        #expect(!MeScene.includeEntries(in: room).contains { MeScene.includedID($0) == "me-aubrey" })

        MeScene.setInclude(false, sceneID: "me-room4", in: aubrey)
        #expect(MeScene.layers(of: aubrey, find: byID).map(\.sceneID) == ["me-aubrey", "me-group"])
    }

    /// What a Me page can include: other profiles' pages by name, and pages
    /// received in a file — not itself, and nothing that would loop.
    @Test func includeChoicesNameProfilesAndReceivedPages() {
        let ctx = TestStore.freshContainer().mainContext
        let a = ChildProfile(displayName: "Aubrey")
        let r = ChildProfile(displayName: "Room 4")
        ctx.insert(a); ctx.insert(r)
        let aMe = MeScene.ensure(profileID: a.id, context: ctx)
        let rMe = MeScene.ensure(profileID: r.id, context: ctx)
        let received = me("from-ms-k", in: ctx)
        received.isImported = true
        let all = [aMe, rMe, received]
        let choices = MeScene.includeChoices(for: aMe, scenes: all, profiles: [a, r])
        #expect(choices.onDevice.map(\.name) == ["Room 4"])
        #expect(choices.received.map(\.sceneID) == ["me-from-ms-k"])

        MeScene.addInclude(aMe, to: rMe, find: { id in all.first { $0.sceneID == id } })
        let after = MeScene.includeChoices(for: aMe, scenes: all, profiles: [a, r])
        #expect(after.onDevice.isEmpty)   // Room 4 now includes Aubrey
    }

    /// Mark's device test: Aubrey's page from the iPad included the iPad's
    /// caregiver page, whose id every device shares — so on the phone it
    /// named the phone's own caregiver page, and adding Aubrey there was a
    /// loop, refused. Shared, the caregiver page takes the sender's id.
    @Test func aSharedCaregiverPageDoesNotLandAsTheReceiversOwn() throws {
        let caregiverID = MeScene.sceneID(forProfileID: kCaregiverProfileID)
        func vocab(_ ctx: ModelContext) -> [String: TileModel] {
            var lookup: [String: TileModel] = [:]
            for key in ["puppy", "grandpa", MeScene.topicsFolderKey] {
                let t = TileModel(key: key, wordClass: "people"); ctx.insert(t); lookup[key] = t
            }
            return lookup
        }
        let send = TestStore.freshContainer().mainContext
        let words = vocab(send)
        let aubrey = me("aubrey", always: ["puppy"], in: send)
        let mine = me("x", always: ["grandpa"], in: send)
        mine.sceneID = caregiverID
        MeScene.addInclude(mine, to: aubrey, find: { id in [aubrey, mine].first { $0.sceneID == id } })
        let shared = MeScene.sharedID(caregiverID, authorID: "ipad-author")
        #expect(shared == "me-ipad-author-caregiver")
        let file = try SceneExporter.exportJSON(aubrey, tileLookup: words, includes: [mine],
                                               idMap: [caregiverID: shared])

        let receiveContainer = TestStore.freshContainer()
        let receive = receiveContainer.mainContext
        _ = vocab(receive)
        let phoneMine = MeScene.ensure(profileID: kCaregiverProfileID, context: receive)
        _ = try SceneImporter.importJSON(file, context: receive)
        let all = try receive.fetch(FetchDescriptor<BlasterScene>())
        let find = { (id: String) in all.first { $0.sceneID == id } }
        let landed = try #require(find("me-aubrey"))
        #expect(MeScene.includeEntries(in: landed).compactMap(MeScene.includedID) == [shared])
        #expect(find(shared) != nil)
        #expect(phoneMine.page(withKey: MeScene.alwaysPageKey) == nil)   // the phone's own, untouched

        #expect(MeScene.addInclude(landed, to: phoneMine, find: find))
        let shown = keys(compose([], MeScene.layers(of: phoneMine, find: find)))
        #expect(shown == ["puppy", "grandpa"])
        withExtendedLifetime(receiveContainer) {}
    }

    /// Mark's device test: a School topic on the shared page did not reach
    /// the phone. The file now carries the topic boards of the page and of
    /// what it includes, and the child's My Topics lists an included page's
    /// topics after its own.
    @Test func topicsTravelAndShowOnMyTopics() throws {
        func vocab(_ ctx: ModelContext) -> [String: TileModel] {
            var lookup: [String: TileModel] = [:]
            for key in ["desk", "book", MeScene.topicsFolderKey] {
                let t = TileModel(key: key, wordClass: "things"); ctx.insert(t); lookup[key] = t
            }
            return lookup
        }
        let send = TestStore.freshContainer().mainContext
        let words = vocab(send)
        let school = BlasterScene(name: "School")
        school.sceneID = "ms-k/school"
        school.designedFor = PageTemplate.designedFor
        school.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "desk"), TileEntry(key: "book")])]
        send.insert(school)
        let room = MeScene.ensure(profileID: "room4", context: send)
        MeScene.addTopic(school, to: room, context: send)
        let aubrey = MeScene.ensure(profileID: "aubrey", context: send)
        MeScene.addInclude(room, to: aubrey, find: { id in [room, aubrey].first { $0.sceneID == id } })
        var lookup = words
        for t in try send.fetch(FetchDescriptor<TileModel>()) { lookup[t.key] = t }
        let file = try SceneExporter.exportJSON(aubrey, tileLookup: lookup, includes: [room],
                                               topics: [(school, [])])

        let receiveContainer = TestStore.freshContainer()
        let receive = receiveContainer.mainContext
        _ = vocab(receive)
        let phone = MeScene.ensure(profileID: kCaregiverProfileID, context: receive)
        _ = try SceneImporter.importJSON(file, context: receive)
        let all = try receive.fetch(FetchDescriptor<BlasterScene>())
        let find = { (id: String) in all.first { $0.sceneID == id } }
        #expect(find("ms-k/school") != nil)
        let landed = try #require(find(aubrey.sceneID))
        #expect(MeScene.addInclude(landed, to: phone, find: find))
        let topics = MeScene.composeTopics(layers: MeScene.layers(of: phone, find: find))
            .filter { !$0.isEmptyCell }
        #expect(topics.map(\.link) == ["<scene:ms-k/school>:home"])
        withExtendedLifetime(receiveContainer) {}
    }

    /// One file brings a Me page and what it includes; a newer Room 4,
    /// carried in a later file, updates the copy already there.
    @Test func sharingCarriesIncludedPagesAndUpdatesThem() throws {
        let words = ["mom", "teacher", "recess", MeScene.topicsFolderKey]
        func vocab(_ ctx: ModelContext) -> [String: TileModel] {
            var lookup: [String: TileModel] = [:]
            for key in words {
                let t = TileModel(key: key, wordClass: "people")
                ctx.insert(t); lookup[key] = t
            }
            return lookup
        }
        let send = TestStore.freshContainer().mainContext
        let sendWords = vocab(send)
        let aubrey = me("aubrey", always: ["mom"], in: send)
        let room = me("room4", always: ["teacher"], in: send)
        MeScene.addInclude(room, to: aubrey, find: { id in [aubrey, room].first { $0.sceneID == id } })

        let receiveContainer = TestStore.freshContainer()
        let receive = receiveContainer.mainContext
        _ = vocab(receive)
        let first = try SceneExporter.exportJSON(aubrey, tileLookup: sendWords, includes: [room])
        _ = try SceneImporter.importJSON(first, context: receive)
        let landed = try receive.fetch(FetchDescriptor<BlasterScene>())
        #expect(Set(landed.map(\.sceneID)) == ["me-aubrey", "me-room4"])
        let landedAubrey = try #require(landed.first { $0.sceneID == "me-aubrey" })
        #expect(MeScene.includeEntries(in: landedAubrey).compactMap(MeScene.includedID) == ["me-room4"])

        room.pages = room.pages.map { page in
            var p = page
            if p.key == MeScene.alwaysPageKey { p.tiles.append(TileEntry(key: "recess")) }
            return p
        }
        room.lastModified = .now.addingTimeInterval(60)
        let second = try SceneExporter.exportJSON(aubrey, tileLookup: sendWords, includes: [room])
        _ = try SceneImporter.importJSON(second, context: receive, resolution: .takeUpdate)
        let updatedRoom = try #require(try receive.fetch(FetchDescriptor<BlasterScene>())
            .first { $0.sceneID == "me-room4" })
        #expect(updatedRoom.page(withKey: MeScene.alwaysPageKey)?.tiles.map(\.key) == ["teacher", "recess"])
        withExtendedLifetime(receiveContainer) {}
    }
}
}
