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
            && !scene.isCarriedTemplate && BoardChrome.inherits(scene)
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

    /// Take `sceneID` off My Topics and off every context page.
    static func removeTopic(sceneID: String, from me: BlasterScene) {
        let entries = topicEntries(in: me)
        let kept = entries.filter { TileToken.scenePageKey($0.link)?.sceneID != sceneID }
        if kept.count != entries.count { setTopicEntries(kept, in: me) }
        setContexts([], forSceneID: sceneID, in: me) { _ in nil }
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

        // The same entries on the context pages, kept in step.
        var pages = me.pages
        var changed = false
        for i in pages.indices where isContextPage(pages[i].key) {
            let tiles = pages[i].tiles.map { entry -> TileEntry in
                // Only an item for a topic's home stands for the topic; one
                // for another of its pages keeps that page's picture and name.
                guard let source = TileToken.scenePageKey(entry.link),
                      let topic = scenes[source.sceneID],
                      source.page == topic.homePageKey else { return entry }
                var e = entry
                e.key = SceneCover.ensure(for: topic, context: context).key
                e.label = topic.name
                return e
            }
            if tiles != pages[i].tiles { pages[i].tiles = tiles; changed = true }
        }
        if changed { me.pages = pages }
    }

    // MARK: - Contexts

    /// A topic can also be shown *in context*: when the child presses ♥ from
    /// a page of BlasterAI 60, the Me page shows the topics attached to it
    /// (`withRegion`). The system page itself never changes (Mark, 2026-11-01).
    ///
    /// Each context is a page of the Me scene, `on:<system>:i_page`, whose
    /// tiles are the topic links shown for that page. Being a page, it syncs
    /// with the scene, and a caregiver orders it in the page editor and may
    /// put any word or folder on it.
    static let contextPrefix = "on:"

    static func contextPageKey(for systemKey: String) -> String {
        contextPrefix + TileToken.systemLink(to: systemKey)
    }

    static func isContextPage(_ key: String) -> Bool { key.hasPrefix(contextPrefix) }

    /// The BlasterAI 60 page a context page is for.
    static func systemKey(ofContextPage key: String) -> String? {
        guard isContextPage(key) else { return nil }
        return TileToken.systemPageKey(String(key.dropFirst(contextPrefix.count)))
    }

    /// The BlasterAI 60 pages `sceneID` is shown on.
    static func contexts(of sceneID: String, in me: BlasterScene) -> [String] {
        me.pages.compactMap { page in
            guard let key = systemKey(ofContextPage: page.key),
                  page.tiles.contains(where: { TileToken.scenePageKey($0.link)?.sceneID == sceneID })
            else { return nil }
            return key
        }
    }

    /// Show `topic` on exactly `systemKeys`. A new context page is named "On
    /// <title>" from `titles`; a context page left empty is dropped.
    static func setContexts(_ systemKeys: Set<String>, for topic: BlasterScene,
                            in me: BlasterScene, context: ModelContext,
                            titles: [String: String]) {
        let cover = SceneCover.ensure(for: topic, context: context)
        let entry = entry(for: topic, cover: cover)
        setContexts(systemKeys, forSceneID: topic.sceneID, in: me) { key in
            (entry, titles[key] ?? PageNaming.displayName(key))
        }
    }

    /// `make` gives the entry to add and the title for a page it creates; it
    /// is not called when only removing.
    private static func setContexts(_ systemKeys: Set<String>, forSceneID sceneID: String,
                                    in me: BlasterScene,
                                    make: (String) -> (TileEntry, String)?) {
        func isTopic(_ e: TileEntry) -> Bool { TileToken.scenePageKey(e.link)?.sceneID == sceneID }
        var pages = me.pages
        let before = pages
        // Off the pages no longer wanted.
        for i in pages.indices {
            guard let key = systemKey(ofContextPage: pages[i].key), !systemKeys.contains(key) else { continue }
            pages[i].tiles.removeAll(where: isTopic)
        }
        // Onto the wanted ones, at the end.
        for key in systemKeys.sorted() {
            let pageKey = contextPageKey(for: key)
            if let i = pages.firstIndex(where: { $0.key == pageKey }) {
                guard !pages[i].tiles.contains(where: isTopic),
                      let (entry, _) = make(key) else { continue }
                pages[i].tiles.append(entry)
            } else if let (entry, title) = make(key) {
                pages.append(PageSpec(key: pageKey, displayName: "On " + title, tiles: [entry]))
            }
        }
        pages.removeAll { isContextPage($0.key) && $0.tiles.isEmpty }
        if pages != before { me.pages = pages }
    }

    /// The page "contextual me" is about, from the board's history: the last
    /// page that is not a Me or topic page, the board's home left out. Going
    /// deeper into Me and back keeps it; Home clears the history, and with it
    /// the context.
    static func contextKey(inHistory path: [String]) -> String? {
        path.dropFirst().last { TileToken.scenePageKey($0) == nil }
    }

    /// What the Me page shows for the page the child came from, a navigation
    /// key.
    ///
    /// Pages are matched by name, not by scene: a scene's own Places page
    /// shows what is listed for Places, as BlasterAI 60's does. The caregiver
    /// listed those items for "when we are on Places"; which scene drew the
    /// page is a detail of how the board was built. A mounted page (the Me
    /// page, a topic) is never a context.
    static func contextEntries(forNavKey navKey: String, systemIsActive: Bool,
                               in me: BlasterScene) -> [TileEntry] {
        // A template's page is its name too: `template:random` is Random.
        let systemKey = TileToken.systemPageKey(navKey).map(TileToken.bareKey)
            ?? (TileToken.scenePageKey(navKey) == nil ? navKey : nil)
        guard let systemKey else { return [] }
        return (me.page(withKey: contextPageKey(for: systemKey))?.tiles ?? [])
            .filter { !$0.isEmptyCell }
    }

    // MARK: - Pages a context can be for

    /// The pages a caregiver can list Me items or a topic for, grouped by the
    /// board they come from: BlasterAI 60's, then each scene of the caregiver's
    /// own that draws on the 10 × 6 layout. Every board lists all its pages,
    /// so a scene reads as the caregiver built it; a name two boards share is
    /// one context (`contextEntries`), and `sharedContextKeys` says which.
    /// Homes are left out: Home clears the context. A page standing in for a
    /// BlasterAI 60 page is listed under its own scene too.
    static func contextChoices(system: BlasterScene?, scenes: [BlasterScene])
        -> [(board: String, pages: [PageSpec])] {
        var groups: [(board: String, pages: [PageSpec])] = []
        func add(_ board: BlasterScene) {
            var seen = Set<String>()
            let pages = board.pages.compactMap { page -> PageSpec? in
                // A copy of a BlasterAI 60 page is reached as that page.
                var page = page
                if page.isShadow { page.key = TileToken.bareKey(page.shadows) }
                return page.key != board.homePageKey && seen.insert(page.key).inserted ? page : nil
            }
            if !pages.isEmpty { groups.append((BlasterScene.copyRoot(of: board.name), pages)) }
        }
        if let system { add(system) }
        for scene in scenes where !scene.isDefault && !scene.isSystemOwned && !scene.isCarriedTemplate
            && !isMeScene(scene) && BoardChrome.inherits(scene) {
            add(scene)
        }
        return groups
    }

    /// Page names more than one board in `groups` has: choosing one chooses
    /// them all, so the list says so.
    static func sharedContextKeys(_ groups: [(board: String, pages: [PageSpec])]) -> Set<String> {
        var count: [String: Int] = [:]
        for group in groups { for page in group.pages { count[page.key, default: 0] += 1 } }
        return Set(count.filter { $0.value > 1 }.keys)
    }

    /// A context page's title: BlasterAI 60's name for it, else the first
    /// scene page of that key, else one made from the key.
    static func contextTitle(_ key: String, system: BlasterScene?, scenes: [BlasterScene]) -> String {
        if let page = system?.page(withKey: key) { return page.title }
        for scene in scenes where !scene.isDefault && !isMeScene(scene) {
            if let page = scene.page(withKey: key) { return page.title }
        }
        return PageNaming.displayName(key)
    }

    // MARK: - Context items

    /// Add `item` to the context page for `systemKey`, replacing the one with
    /// the same source (`link`). A new page is named "On <title>".
    static func setItem(_ item: TileEntry, onPage systemKey: String, in me: BlasterScene,
                        title: String) {
        let pageKey = contextPageKey(for: systemKey)
        var pages = me.pages
        if let i = pages.firstIndex(where: { $0.key == pageKey }) {
            if let j = pages[i].tiles.firstIndex(where: { $0.link == item.link }) {
                pages[i].tiles[j] = item
            } else {
                pages[i].tiles.append(item)
            }
        } else {
            pages.append(PageSpec(key: pageKey, displayName: "On " + title, tiles: [item]))
        }
        me.pages = pages
    }

    /// Replace the items on the context page for `systemKey`, in this order;
    /// none left drops the page. What reordering and deleting write.
    static func setItems(_ items: [TileEntry], onPage systemKey: String, in me: BlasterScene) {
        let pageKey = contextPageKey(for: systemKey)
        var pages = me.pages
        guard let i = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        if items.isEmpty { pages.remove(at: i) } else { pages[i].tiles = items }
        me.pages = pages
    }

    /// A word on its own: an item with no source, inlined as itself.
    static func isWordItem(_ item: TileEntry) -> Bool {
        item.link.isEmpty && !item.isEmptyCell
    }

    /// Append `keys` to the context page for `systemKey` as words, in this
    /// order, skipping any already listed. A new page is named "On <title>".
    static func addWords(_ keys: [String], onPage systemKey: String, in me: BlasterScene,
                         title: String) {
        let pageKey = contextPageKey(for: systemKey)
        var pages = me.pages
        let i = pages.firstIndex { $0.key == pageKey } ?? {
            pages.append(PageSpec(key: pageKey, displayName: "On " + title, tiles: []))
            return pages.count - 1
        }()
        var listed = Set(pages[i].tiles.filter(isWordItem).map(\.key))
        for key in keys where listed.insert(key).inserted {
            pages[i].tiles.append(TileEntry(key: key))
        }
        if pages[i].tiles.isEmpty { pages.remove(at: i) }
        me.pages = pages
    }

    /// Drop the source item `link`; words (no link) go through `setItems`.
    static func removeItem(link: String, fromPage systemKey: String, in me: BlasterScene) {
        let items = me.page(withKey: contextPageKey(for: systemKey))?.tiles ?? []
        setItems(items.filter { $0.link != link }, onPage: systemKey, in: me)
    }

    /// The picture for a folder to `pageKey` of `scene`: the tile that already
    /// opens it there, else its minted page link — the rule
    /// `PageLink.ensurePageImages` follows.
    static func folderKey(forPage pageKey: String, in scene: BlasterScene) -> String {
        PageCover.key(ofPage: pageKey, in: scene)
    }

    /// Me home as the child sees it after pressing ♥ from a page: `home`, the
    /// words of the items that inline (into columns 1–7 below the author's
    /// content), and the folders (into the region, `withRegion`).
    ///
    /// `words` reads an item's source page live. Only words are inlined —
    /// folders, doorways and empty cells are not — and a word already on the
    /// page, in row 1 (`rowKeys`) or inlined by an earlier item is skipped: a
    /// key is a tile's identity on a page.
    static func compose(_ home: [TileEntry], items: [TileEntry], rowKeys: Set<String>,
                        words: (TileEntry) -> [TileEntry]) -> [TileEntry] {
        let folders = items.filter { !isWordItem($0) && !$0.hidesFolder }.map { item -> TileEntry in
            var folder = item
            folder.inline = nil
            folder.isAudible = false
            return folder
        }
        var used = Set(home.filter { !$0.isEmptyCell }.map(\.key))
            .union(rowKeys).union(folders.map(\.key))
        var inlined: [TileEntry] = []
        for item in items {
            // A word on the list is inlined as itself, in list order.
            if isWordItem(item) {
                if !item.key.hasPrefix("<"), used.insert(item.key).inserted {
                    inlined.append(TileEntry(key: item.key, label: item.label))
                }
                continue
            }
            guard let count = item.inline else { continue }
            var taken = 0
            for word in words(item) {
                if count != TileEntry.inlineAll, taken >= count { break }
                guard !word.isEmptyCell, word.link.isEmpty, !word.key.hasPrefix("<"),
                      used.insert(word.key).inserted else { continue }
                inlined.append(TileEntry(key: word.key, label: word.label))
                taken += 1
            }
        }
        // Folders first, so they keep column 8 and the words fill around them.
        return placeInline(withRegion(home, region: folders), words: inlined)
    }

    /// Lay `words` across columns 1–7 below the last row the author used
    /// there, after one empty row when everything still fits with it (Mark:
    /// "preserve a whitespace buffer if feasible").
    ///
    /// When that is not enough, the rest take every free cell left on the
    /// page in reading order — columns 8–10 and the gaps between the author's
    /// tiles included (Mark: All "should steal all unallocated space if
    /// needed"). Only empty cells are ever filled; past a full page the rest
    /// are left off.
    static func placeInline(_ home: [TileEntry], words: [TileEntry]) -> [TileEntry] {
        guard !words.isEmpty else { return home }
        let cols = PageTemplate.cols
        let rows = PageTemplate.rows - 1
        let field = 7
        func isFree(_ index: Int) -> Bool { index >= home.count || home[index].isSpacer }
        let lastRow = (0..<rows).last { row in (0..<field).contains { !isFree(row * cols + $0) } }
        func free(from row: Int) -> Int {
            (row..<max(row, rows)).reduce(0) { n, r in n + (0..<field).filter { isFree(r * cols + $0) }.count }
        }
        var start = lastRow.map { $0 + 1 } ?? 0
        if let lastRow, lastRow + 2 < rows, free(from: lastRow + 2) >= words.count { start = lastRow + 2 }
        var tiles = home
        var queue = words[...]
        func fill(_ index: Int) {
            guard let next = queue.first else { return }
            while tiles.count <= index { tiles.append(.spacer()) }
            guard tiles[index].isSpacer else { return }
            tiles[index] = next
            queue = queue.dropFirst()
        }
        for row in start..<max(start, rows) {
            for col in 0..<field { fill(row * cols + col) }
        }
        for index in 0..<(rows * cols) where !queue.isEmpty { fill(index) }
        return tiles
    }

    /// Lay `region` into the free cells of `home`: column 8 top to bottom,
    /// then 9, then 10 (Mark). Columns 9–10 are the page author's for links
    /// that stay, so whatever the author placed is kept and the region flows
    /// around it. What does not fit is left off.
    static func withRegion(_ home: [TileEntry], region: [TileEntry]) -> [TileEntry] {
        guard !region.isEmpty else { return home }
        let cols = PageTemplate.cols
        let rows = PageTemplate.rows - 1
        var tiles = home
        var queue = region[...]
        for col in 7..<cols {
            for row in 0..<rows {
                guard let next = queue.first else { return tiles }
                let index = row * cols + col
                while tiles.count <= index { tiles.append(.spacer()) }
                guard tiles[index].isSpacer else { continue }
                tiles[index] = next
                queue = queue.dropFirst()
            }
        }
        return tiles
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
