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
    /// homePageKey (see `TileGridView`).
    ///
    /// **Nothing authors this any more.** Every board has a Home control on its
    /// rail (`ControlRail`), so a back-to-home tile inside the grid is
    /// redundant by construction — it costs a vocabulary slot to duplicate a
    /// control that is already there, and gives the child two things to learn
    /// for one action.
    ///
    /// The token is still *resolved* because a board can arrive from elsewhere —
    /// an import from another BlasterAI user, or an older export. Rendering
    /// someone else's tile correctly is three lines; silently deleting tiles
    /// from their board would be worse than showing a redundant one.
    static let homeLinkToken = "<home>"

    /// Structural navigation keys that must never appear as AI-authored tiles.
    /// `home` stays on the list: the scaffolder no longer injects a home tile,
    /// and the model must not invent one either.
    private static let structuralNavKeys: Set<String> = ["next_page", "previous_page", "home"]

    /// Every word any core set can put on a home page.
    ///
    /// **Data, not a literal** (`Resources/core_sets.json`). These used to be two
    /// arrays here, read by `ChromeBundle` alone; the tile picker now offers the
    /// same sets as filter chips, and two readers of one list must not be two
    /// copies of it. The file also carries where each set came from — see
    /// `CoreWordSets`.
    fileprivate static var allCoreSetKeys: Set<String> {
        CoreWordSets.all.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
    }

    /// Which set of words, if any, the structure step puts on a home page.
    ///
    /// **`.none` is the default, and that is the point.** Generation used to
    /// inject a core cluster and four category pages silently, which made a
    /// generated scene impossible to reason about: you could not tell what the
    /// model had produced from what we had added, and the only way to remove any
    /// of it was a toggle that rebuilt the scene and dropped every page you had
    /// made yourself. Now nothing is added unless someone asks for it, and what
    /// they asked for is visible in the sheet that asked.
    ///
    /// ## Words only — pages are chosen separately
    ///
    /// There used to be a third case, "Full core board", which both put words on
    /// the home page **and** brought the people / food / drinks / body-health
    /// pages with it. That was the last place two decisions were still bundled
    /// together, and the structure step already offers pages of its own, each
    /// with its home-page link minted for it. So a bundle now means exactly one
    /// thing: a strip of words. Wanting a Food page is a separate tick, and the
    /// `eat`→food link it used to carry is better served by that page's own link
    /// tile, which at least looks like a page link.
    ///
    /// ## Why two sets and not one
    ///
    /// They are genuinely different things, and the old naming hid it. **Core
    /// words** are high-frequency and combinable — they work on any topic, which
    /// is what the AAC literature means by the term. **Basic needs & feelings**
    /// are states to report: useful, wanted, and on none of the four published
    /// lists we checked. Calling the second one "min-core" oversold it to exactly
    /// the reader who knows what core means.
    enum ChromeBundle: String, CaseIterable, Identifiable, Sendable {
        /// Just the scene's own tiles. Nothing supplied.
        case none
        /// How the child is doing and what they need — hungry, hurt, all done.
        case needs
        /// The words AAC research calls core: want, go, more, stop, not, same.
        case core

        public var id: String { rawValue }

        /// The set this bundle draws from, or nil for `.none`.
        var wordSet: CoreWordSet? {
            switch self {
            case .none:  return nil
            case .needs: return CoreWordSets.set(id: CoreWordSets.needsID)
            case .core:  return CoreWordSets.set(id: CoreWordSets.coreID)
            }
        }

        var title: String {
            switch self {
            case .none:  return "Nothing"
            case .needs: return wordSet?.displayName ?? "Basic needs & feelings"
            case .core:  return wordSet?.displayName ?? "Core words"
            }
        }

        var summary: String {
            switch self {
            case .none:
                return "Only the words this scene is about. Add words and pages yourself."
            default:
                return wordSet?.summary ?? ""
            }
        }

        /// Home-page words this bundle appends after the scene's own tiles.
        var clusterKeys: [String] { wordSet?.keys ?? [] }
    }

    /// Build the canonical scene: a topical home page, optionally followed by a
    /// strip of core words. Returns the original scene unchanged only if the
    /// model produced no usable topical content.
    ///
    /// Pages are not this function's business any more — the structure step adds
    /// them, each with its own link tile. `allTiles` is the live vocabulary;
    /// `validKeys` is its key set, used to confirm a word exists before placing
    /// a tile that would otherwise render a gap.
    static func scaffold(_ scene: GeneratedScene, allTiles: [TileModel], validKeys: Set<String>,
                         chrome: ChromeBundle = .none) -> GeneratedScene {
        // Keys we supply ourselves — never carried over from the model's tiles.
        // Reserve every core set's words regardless of which bundle was chosen,
        // so "what is this scene's own content" gives the same answer whatever
        // strip is on it. Refinement reads that answer.
        var reserved = structuralNavKeys.union(allCoreSetKeys)

        // 1. Topical tiles: every model tile that isn't navigation or something
        //    a core set provides, de-duplicated in first-seen order.
        var topical: [GeneratedTile] = []
        for page in scene.pages {
            for tile in page.tiles where !isStructuralNav(tile) && !reserved.contains(tile.key) {
                guard reserved.insert(tile.key).inserted else { continue }
                topical.append(GeneratedTile(key: tile.key, isAudible: true, link: "",
                                             displayName: tile.displayName, wordClass: tile.wordClass))
            }
        }
        // An empty topical set is only meaningful when there is a strip to wrap
        // around it; with none there is nothing to build and the scene stands.
        guard !topical.isEmpty else { return scene }

        let pageKeys = scene.pages.map(\.key)
        let homeKey: String = pageKeys.contains(scene.homePageKey) ? scene.homePageKey : (pageKeys.first ?? "home")

        // 2. The chosen strip, after the scene's own words.
        var homeTiles = topical
        for key in chrome.clusterKeys where validKeys.contains(key) {
            homeTiles.append(GeneratedTile(key: key, isAudible: true, link: ""))
        }

        return GeneratedScene(
            name: scene.name,
            description: scene.description,
            homePageKey: homeKey,
            pages: [GeneratedPage(key: homeKey, tiles: homeTiles)],
            newWords: scene.newWords
        )
    }

    /// Keys the app supplies itself — any core set's words, plus structural
    /// navigation. Everything else on a home page is the scene's own content.
    ///
    /// Deliberately the union across *every* set rather than the one in use: a
    /// scene that was given the needs strip and later the core words must give
    /// the same answer to "what is this scene about", or a refine would treat
    /// `hungry` as topical and rewrite around it.
    static var injectedKeys: Set<String> {
        structuralNavKeys.union(allCoreSetKeys)
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
