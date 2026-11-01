// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneCover.swift
//  claudeBlast
//
//  The tile that stands for a whole scene where something links to it — a
//  topic on My Topics today. The scene-level twin of a pack's cover
//  (`packcover_<slug>`), needed now that scenes are mountable (Mark,
//  2026-10-31).
//

import Foundation
import SwiftData

/// A scene's cover is a `TileModel` keyed from its `sceneID`, minted on first
/// use the way `PageLink.mint` mints a page's.
///
/// ## Why a tile and not a field on the scene
///
/// A tile already has everything a cover needs: a picture that is either an
/// alias of another word's art (`bundleImage`) or a caregiver photo
/// (`userImageData`), a label, and a place on a page. Every board surface
/// already draws it. And a new `TileModel` row syncs today, where a new
/// `BlasterScene` field would wait on a CloudKit schema deploy.
///
/// It is a `page_link` tile: structural, never a word, kept out of the
/// sentence vocabulary and moderation like every other folder.
///
/// ## Defaults
///
/// Until a caregiver picks one, a cover borrows the first word on the scene's
/// home page. Because the cover has its own key, two topics may borrow the
/// same picture without colliding on a page.
enum SceneCover {
    static let prefix = "scenecover_"

    /// The cover's tile key. `sceneID` is `authority/slug`, so it is folded to
    /// the lowercase, underscore form every tile key has.
    static func key(for scene: BlasterScene) -> String {
        prefix + scene.sceneID.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    static func find(for scene: BlasterScene, context: ModelContext) -> TileModel? {
        let k = key(for: scene)
        let fetch = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == k })
        return (try? context.fetch(fetch))?.first
    }

    /// The scene's cover, minted if it has none. Its label follows the
    /// scene's name; its picture is left alone once it exists.
    @discardableResult
    static func ensure(for scene: BlasterScene, context: ModelContext) -> TileModel {
        if let tile = find(for: scene, context: context) {
            if tile.displayName != scene.name, !scene.name.isEmpty { tile.displayName = scene.name }
            return tile
        }
        let tile = TileModel(key: key(for: scene), value: scene.name, wordClass: PageLink.wordClass)
        tile.isSystem = false
        if let word = defaultWord(of: scene) { tile.bundleImage = word }
        context.insert(tile)
        return tile
    }

    /// The first word on the scene's home page (else anywhere in it): what a
    /// cover shows until someone picks.
    static func defaultWord(of scene: BlasterScene) -> String? {
        candidateWords(of: scene).first
    }

    /// Words a caregiver can take a cover picture from: every word in the
    /// scene, home page first, each once.
    static func candidateWords(of scene: BlasterScene) -> [String] {
        let home = scene.page(withKey: scene.homePageKey).map { [$0] } ?? []
        let rest = scene.pages.filter { $0.key != scene.homePageKey }
        var seen = Set<String>()
        return words(of: home + rest).filter { seen.insert($0).inserted }
    }

    /// Point the cover at `word`'s picture, replacing any photo.
    static func use(word: String, on cover: TileModel) {
        cover.bundleImage = word
        cover.userImageData = Data()
    }

    private static func words(of pages: [PageSpec]) -> [String] {
        pages.flatMap(\.tiles)
            .filter { !$0.isEmptyCell && $0.link.isEmpty && !$0.key.hasPrefix("<") }
            .map(\.key)
    }
}
