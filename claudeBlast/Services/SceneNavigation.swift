// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneNavigation.swift
//  claudeBlast
//
//  Deterministic structure for AI-generated scenes.
//
//  A generated scene is the child's FAMILIAR core board with today's topical
//  vocabulary laid on top — not a novel layout. The model contributes only the
//  topical world (the inferred animals/objects/places for the activity); this
//  file supplies everything the child already knows from the built-in Core-First
//  scene so the scene feels the same:
//
//  - the home page leads with the topical tiles, then carries a curated core
//    cluster (pronouns, family, hungry/thirsty, eat→food, drink→drinks, help,
//    feelings, yes/no/more/…) and links to the familiar category pages; and
//  - a small set of rich category pages — people, food, drinks, body & health —
//    is bundled in, built by word class exactly as Core-First builds them
//    (Resources/scenes/core_first.json), including the food↔drinks cross-links.
//
//  The model's own page structure is discarded entirely: it is unreliable, and
//  the value here is consistency with the board the child uses every day.
//

import Foundation

enum SceneNavigation {
    /// Symbolic link token resolved at navigation time to the active scene's
    /// homePageKey (see TileGridView).
    static let homeLinkToken = "<home>"

    /// `home` is a navigation-class tile that ships in the default vocabulary;
    /// used as the image for auto-inserted "back home" tiles.
    private static let homeTileKey = "home"

    /// Structural navigation keys that must never appear as AI-authored tiles.
    private static let structuralNavKeys: Set<String> = ["next_page", "previous_page", "home"]

    /// A familiar Core-First category page, rebuilt by word class. `crossLinks`
    /// are sibling category pages it links to (mirrors core_first.json: the food
    /// page links drinks and vice-versa).
    private struct CoreCategory {
        let pageKey: String
        let iconKey: String
        let wordClasses: Set<String>
        let crossLinks: [String]
    }

    /// The curated rich pages bundled into every generated scene — the ones the
    /// child already knows. Mirrors core_first.json's food/drinks/people/
    /// body_health page definitions.
    private static let coreCategories: [CoreCategory] = [
        CoreCategory(pageKey: "people", iconKey: "people",
                     wordClasses: ["people"], crossLinks: []),
        CoreCategory(pageKey: "food", iconKey: "food",
                     wordClasses: ["food"], crossLinks: ["drinks"]),
        CoreCategory(pageKey: "drinks", iconKey: "drinks",
                     wordClasses: ["drinks"], crossLinks: ["food"]),
        CoreCategory(pageKey: "body_health", iconKey: "body_health",
                     wordClasses: ["body", "health"], crossLinks: []),
    ]

    /// The curated core cluster appended to the home page after the topical
    /// tiles — the familiar high-frequency words from the Core-First home. Plain
    /// audible tiles; `eat`/`drink` are added separately as audible links to the
    /// food/drinks pages.
    private static let homeClusterKeys: [String] = [
        "i", "you", "me", "my", "he", "she", "we", "they", "teacher", "mom", "dad", "friend",
        "help", "hungry", "thirsty", "bathroom",
        "happy", "sad", "tired", "hurt", "sick", "scared",
        "yes", "no", "more", "want", "please", "all_done", "look",
    ]

    /// Audible link tiles on the home page that both speak and navigate to a rich
    /// page (mirrors Core-First's eat→food_drinks). (clusterKey, destinationPage).
    private static let homeClusterLinks: [(key: String, to: String)] = [
        ("eat", "food"),
        ("drink", "drinks"),
    ]

    /// Lean cluster for the Focused board: a minimal needs strip with feelings
    /// and a couple of pronouns. No eat/drink links — hungry/thirsty stand in for
    /// food & drink — and only the body & health page is bundled (see scaffold).
    private static let focusedClusterKeys: [String] = [
        "i", "you", "want",
        "help", "more", "hungry", "thirsty", "bathroom",
        "happy", "sad", "tired", "hurt", "sick", "scared",
        "yes", "no", "all_done", "look",
    ]

    /// How much of the familiar Core board to scaffold around the topical tiles.
    enum Profile { case full, focused }

    /// Build the canonical scene: a topical home page (topical tiles first, then
    /// the familiar core cluster and category links) plus the bundled rich
    /// category pages. Returns the original scene unchanged only if the model
    /// produced no usable topical content.
    ///
    /// `allTiles` is the live vocabulary (used to fill category pages and confirm
    /// keys exist); `validKeys` is its key set.
    static func scaffold(_ scene: GeneratedScene, allTiles: [TileModel], validKeys: Set<String>,
                         profile: Profile = .full) -> GeneratedScene {
        let clusterKeys = profile == .focused ? focusedClusterKeys : homeClusterKeys
        let clusterLinks = profile == .focused ? [] : homeClusterLinks
        let categories = profile == .focused
            ? coreCategories.filter { $0.pageKey == "body_health" }
            : coreCategories

        // Keys we supply ourselves — never carried over from the model's tiles.
        // Reserve the full superset regardless of profile so topical extraction
        // is stable when a scene's profile changes.
        var reserved = structuralNavKeys
            .union(coreCategories.map(\.pageKey))
            .union(homeClusterKeys)
            .union(homeClusterLinks.map(\.key))

        // 1. Topical tiles: every model tile that isn't navigation or something
        //    we provide via the core cluster, de-duplicated in first-seen order.
        var topical: [GeneratedTile] = []
        for page in scene.pages {
            for tile in page.tiles where !isStructuralNav(tile) && !reserved.contains(tile.key) {
                guard reserved.insert(tile.key).inserted else { continue }
                topical.append(GeneratedTile(key: tile.key, isAudible: true, link: "",
                                             displayName: tile.displayName, wordClass: tile.wordClass))
            }
        }
        guard !topical.isEmpty else { return scene }

        let pageKeys = scene.pages.map(\.key)
        let homeKey: String = pageKeys.contains(scene.homePageKey) ? scene.homePageKey : (pageKeys.first ?? "home")

        // 2. Core cluster + category links for the home page.
        var homeTiles = topical
        for key in clusterKeys where validKeys.contains(key) {
            homeTiles.append(GeneratedTile(key: key, isAudible: true, link: ""))
        }
        for link in clusterLinks where validKeys.contains(link.key) {
            homeTiles.append(GeneratedTile(key: link.key, isAudible: true, link: link.to))
        }

        // 3. Bundled category pages, and their links from the home page.
        var categoryPages: [GeneratedPage] = []
        for category in categories where category.pageKey != homeKey {
            let contentTiles = allTiles
                .filter { category.wordClasses.contains($0.wordClass) }
                .map { GeneratedTile(key: $0.key, isAudible: true, link: "") }
            guard !contentTiles.isEmpty else { continue }

            var pageTiles = [GeneratedTile(key: homeTileKey, isAudible: false, link: homeLinkToken)]
            for sibling in category.crossLinks where sibling != homeKey {
                pageTiles.append(GeneratedTile(key: sibling, isAudible: false, link: sibling))
            }
            pageTiles += contentTiles
            categoryPages.append(GeneratedPage(key: category.pageKey, tiles: pageTiles))

            let icon = validKeys.contains(category.iconKey) ? category.iconKey : category.pageKey
            homeTiles.append(GeneratedTile(key: icon, isAudible: false, link: category.pageKey))
        }

        let homePage = GeneratedPage(key: homeKey, tiles: homeTiles)
        return GeneratedScene(
            name: scene.name,
            description: scene.description,
            homePageKey: homeKey,
            pages: [homePage] + categoryPages,
            newWords: scene.newWords
        )
    }

    /// Keys this scaffolder injects itself — the core cluster, the eat/drink
    /// links, the bundled category pages, and structural navigation. Everything
    /// else on a scaffolded home page is topical.
    static var injectedKeys: Set<String> {
        structuralNavKeys
            .union(coreCategories.map(\.pageKey))
            .union(homeClusterKeys)
            .union(homeClusterLinks.map(\.key))
    }

    /// The topical tile keys of a scaffolded scene: the audible, unlinked tiles
    /// on its home page that aren't part of the injected core board. This is the
    /// layer iterative refinement reads and rewrites.
    static func topicalKeys(of scene: BlasterScene) -> [String] {
        let home = scene.pages.first(where: { $0.key == scene.homePageKey }) ?? scene.pages.first
        guard let home else { return [] }
        let injected = injectedKeys
        return home.tiles
            .filter { $0.link.isEmpty && $0.isAudible && !injected.contains($0.key) }
            .map(\.key)
    }

    /// The topical tiles of an in-memory (possibly un-accepted) scaffolded scene,
    /// preserving each tile's new-word metadata so refinement can carry proposed
    /// words forward. GeneratedScene analogue of `topicalKeys`.
    static func topicalTiles(of scene: GeneratedScene) -> [GeneratedTile] {
        let home = scene.pages.first(where: { $0.key == scene.homePageKey }) ?? scene.pages.first
        guard let home else { return [] }
        let injected = injectedKeys
        return home.tiles.filter { $0.link.isEmpty && $0.isAudible && !injected.contains($0.key) }
    }

    // MARK: - Private

    /// A tile that switches pages rather than communicating.
    private static func isStructuralNav(_ tile: GeneratedTile) -> Bool {
        (!tile.isAudible && !tile.link.isEmpty) || structuralNavKeys.contains(tile.key)
    }
}
