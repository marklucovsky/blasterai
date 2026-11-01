// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MeScene.swift
//  claudeBlast
//
//  The child's own page: the heart on the rail. It is an ordinary scene,
//  mounted rather than activated, so the system board stays exactly as it is
//  and the child extends it from here (Mark, 2026-10-31).
//

import Foundation
import SwiftData

/// One Me scene per `ChildProfile`, made on first use.
///
/// ## Why a scene
///
/// Everything a caregiver can already do to a scene — edit a page, add
/// folders and doorways, share it — works on the Me page for free, and the
/// board draws it with the same code as any other mounted page. What is
/// special is only how it is found and what the system keeps on it.
///
/// ## Layout
///
/// It is on the 10×6 template, under the inherited row 1. Columns 1–8 are the
/// button field; columns 9–10 are kept for pinned topics and extension links.
/// `home` starts with one folder, My Topics, which the system keeps.
///
/// ## The topic list is a page
///
/// `my_topics` holds one link per topic, `<scene:ID>:home`, in the order they
/// were added. The page *is* the list: it syncs with the scene, so the list
/// needs no schema change, and a caregiver sees exactly what the child sees.
enum MeScene {
    static let homePageKey = "home"
    static let topicsPageKey = "my_topics"
    /// The word whose picture the My Topics folder borrows.
    static let topicsFolderKey = "favorite"
    static let topicsFolderLabel = "My Topics"

    /// Deterministic, so two devices that each make the page for a profile
    /// make the same scene, and `CloudKitDedupReconciler` collapses them.
    static func sceneID(forProfileID profileID: String) -> String { "me-" + profileID }

    static func isMeScene(_ scene: BlasterScene) -> Bool { scene.sceneID.hasPrefix("me-") }

    static func find(profileID: String, context: ModelContext) -> BlasterScene? {
        let id = sceneID(forProfileID: profileID)
        let fetch = FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.sceneID == id })
        return (try? context.fetch(fetch))?.first
    }

    /// The profile's Me scene, made if it does not exist yet, with its
    /// system pages repaired if a caregiver removed them.
    @discardableResult
    static func ensure(profileID: String, context: ModelContext) -> BlasterScene {
        let scene: BlasterScene
        if let existing = find(profileID: profileID, context: context) {
            scene = existing
        } else {
            scene = BlasterScene(name: "Me", homePageKey: homePageKey)
            scene.sceneID = sceneID(forProfileID: profileID)
            scene.slug = "me"
            scene.sceneVersion = "1.0.0"
            scene.designedFor = PageTemplate.designedFor
            context.insert(scene)
        }
        var pages = scene.pages
        var changed = false
        if !pages.contains(where: { $0.key == homePageKey }) {
            pages.insert(PageSpec(key: homePageKey, tiles: [topicsFolder]), at: 0)
            changed = true
        }
        if !pages.contains(where: { $0.key == topicsPageKey }) {
            pages.append(PageSpec(key: topicsPageKey, displayName: topicsFolderLabel, tiles: []))
            changed = true
        }
        if changed { scene.pages = pages }
        return scene
    }

    static var topicsFolder: TileEntry {
        TileEntry(key: topicsFolderKey, link: topicsPageKey, isAudible: false,
                  label: topicsFolderLabel)
    }

    // MARK: - Topics

    /// Can `scene` be added to a profile's topics? It must draw under row 1
    /// (the template), have a home and an identity, and not be the system
    /// board or someone's Me page.
    static func isEligibleTopic(_ scene: BlasterScene) -> Bool {
        !scene.isDefault && !isMeScene(scene) && !scene.sceneID.isEmpty
            && BoardChrome.inherits(scene)
            && scene.page(withKey: scene.homePageKey) != nil
    }

    /// The `sceneID`s on My Topics, in order.
    static func topicIDs(in me: BlasterScene) -> [String] {
        topicEntries(in: me).compactMap { TileToken.scenePageKey($0.link)?.sceneID }
    }

    static func contains(_ topic: BlasterScene, in me: BlasterScene) -> Bool {
        topicIDs(in: me).contains(topic.sceneID)
    }

    /// Add `topic` at the end of My Topics, as its cover tile (`SceneCover`).
    /// No-op if it is already there or is not eligible.
    static func addTopic(_ topic: BlasterScene, to me: BlasterScene, context: ModelContext) {
        guard isEligibleTopic(topic), !contains(topic, in: me) else { return }
        let cover = SceneCover.ensure(for: topic, context: context)
        setTopicEntries(topicEntries(in: me) + [entry(for: topic, cover: cover)], in: me)
    }

    private static func entry(for topic: BlasterScene, cover: TileModel) -> TileEntry {
        TileEntry(key: cover.key,
                  link: TileToken.sceneLink(topic.sceneID, to: topic.homePageKey),
                  isAudible: false, label: topic.name)
    }

    static func removeTopic(sceneID: String, from me: BlasterScene) {
        let entries = topicEntries(in: me)
        let kept = entries.filter { TileToken.scenePageKey($0.link)?.sceneID != sceneID }
        guard kept.count != entries.count else { return }
        setTopicEntries(kept, in: me)
    }

    /// Take a deleted scene off every profile's My Topics.
    static func removeTopicEverywhere(sceneID: String, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BlasterScene>())) ?? []
        for me in all where isMeScene(me) { removeTopic(sceneID: sceneID, from: me) }
    }

    /// Bring each topic up to date with its scene: its current name, and its
    /// cover tile (a topic added before covers existed borrowed a word's key).
    static func refresh(in me: BlasterScene, scenes: [String: BlasterScene], context: ModelContext) {
        let entries = topicEntries(in: me)
        let current = entries.map { entry -> TileEntry in
            guard let id = TileToken.scenePageKey(entry.link)?.sceneID,
                  let topic = scenes[id] else { return entry }
            let cover = SceneCover.ensure(for: topic, context: context)
            var e = entry
            e.key = cover.key
            e.label = topic.name
            return e
        }
        if current != entries { setTopicEntries(current, in: me) }
    }

    // MARK: - Layout

    /// The topic links on My Topics, without the gaps that lay them out.
    static func topicEntries(in me: BlasterScene) -> [TileEntry] {
        (me.page(withKey: topicsPageKey)?.tiles ?? [])
            .filter { TileToken.scenePageKey($0.link) != nil }
    }

    /// Lay `entries` across columns 1–8, row by row, leaving 9–10 empty.
    /// Past 40 topics the rest follow in reading order and the grid pages.
    static func layout(_ entries: [TileEntry]) -> [TileEntry] {
        let cols = PageTemplate.cols
        let field = 8
        let capacity = field * (PageTemplate.rows - 1)
        var tiles: [TileEntry] = []
        for (i, entry) in entries.prefix(capacity).enumerated() {
            let index = (i / field) * cols + (i % field)
            while tiles.count < index { tiles.append(.spacer()) }
            tiles.append(entry)
        }
        if entries.count > capacity {
            while tiles.count < capacity / field * cols { tiles.append(.spacer()) }
            tiles += entries.dropFirst(capacity)
        }
        return tiles
    }

    private static func setTopicEntries(_ entries: [TileEntry], in me: BlasterScene) {
        var pages = me.pages
        let page = PageSpec(key: topicsPageKey, displayName: topicsFolderLabel, tiles: layout(entries))
        if let i = pages.firstIndex(where: { $0.key == topicsPageKey }) {
            pages[i].tiles = page.tiles
        } else {
            pages.append(page)
        }
        me.pages = pages
    }
}
