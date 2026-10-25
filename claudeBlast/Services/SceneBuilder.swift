// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneBuilder.swift
//  claudeBlast
//
//  Materializes a GeneratedScene (AI output) into BlasterScene + inline
//  [PageSpec]. Inserts the scene in a single transaction.
//

import Foundation
import SwiftData

enum SceneBuilder {
    /// Materialize proposed NEW words (declared `displayName` + `wordClass`, not
    /// yet in vocabulary) as caregiver-owned, artless `TileModel`s
    /// (`isSystem = false`) so they can be added like any existing tile and are
    /// picked up by the scene-wide "generate art for new words" pass. Skips words
    /// already present in `existing`. Returns the keys actually created.
    @discardableResult
    static func materializeNewWords(_ newWords: [GeneratedNewWord],
                                    into context: ModelContext,
                                    existing: inout [String: TileModel]) -> [String] {
        var created: [String] = []
        for nw in newWords where existing[nw.key] == nil
            && !nw.displayName.isEmpty && !nw.wordClass.isEmpty {
            let tile = TileModel(key: nw.key, value: nw.displayName, wordClass: nw.wordClass)
            tile.isSystem = false
            context.insert(tile)
            existing[nw.key] = tile
            created.append(nw.key)
        }
        return created
    }

    /// Build a BlasterScene from AI output, insert it into `context`, and return it.
    /// Proposed NEW words (tiles carrying displayName + wordClass that aren't in
    /// `tileLookup`) are materialized as caregiver TileModels (isSystem=false)
    /// before the pages are mapped, so they wire up like any existing tile.
    /// - Parameters:
    ///   - generated: The AI-generated scene structure.
    ///   - tileLookup: Existing tile key → TileModel.
    ///   - context: The ModelContext to insert into.
    @discardableResult
    static func build(
        from generated: GeneratedScene,
        tileLookup: [String: TileModel],
        context: ModelContext
    ) throws -> BlasterScene {
        let scene = BlasterScene(
            name: generated.name,
            descriptionText: generated.description,
            homePageKey: generated.homePageKey,
            isDefault: false,
            isActive: false
        )

        try context.transaction {
            var lookup = tileLookup

            // Materialize any proposed-new words first (dedupe by key).
            for genPage in generated.pages {
                for genTile in genPage.tiles where genTile.isProposedNew {
                    guard lookup[genTile.key] == nil,
                          let displayName = genTile.displayName,
                          let wordClass = genTile.wordClass else { continue }
                    let tile = TileModel(key: genTile.key, value: displayName, wordClass: wordClass)
                    tile.isSystem = false
                    context.insert(tile)
                    lookup[genTile.key] = tile
                }
            }

            // A templated scene's pages are laid into the scheme on BlasterAI
            // 60's home. A tile with no vocabulary entry is dropped from a flat
            // page, and becomes a gap on a placed one so no later cell moves.
            scene.pages = generated.placedPages(systemHome: systemHome(in: context), lookup: lookup)
                .map { page in
                    var page = page
                    let placed = PageTemplate.kind(of: page, homePageKey: generated.homePageKey) != nil
                    page.tiles = page.tiles.compactMap { entry in
                        if entry.isSpacer || lookup[entry.key] != nil { return entry }
                        return placed ? .spacer() : nil
                    }
                    return page
                }
            if generated.template != nil { scene.designedFor = PageTemplate.designedFor }

            scene.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: context),
                                 authorName: DeviceProfileStore.authorName(context: context))
            context.insert(scene)
        }

        return scene
    }

    /// BlasterAI 60's home page, which a templated page takes its system row
    /// and core frame from.
    static func systemHome(in context: ModelContext) -> PageSpec? {
        let system = try? context.fetch(FetchDescriptor<BlasterScene>(
            predicate: #Predicate { $0.isDefault })).first
        return system.flatMap { $0.page(withKey: $0.homePageKey) }
    }

    /// Apply a (re-scaffolded) GeneratedScene to an EXISTING scene in place —
    /// used by iterative refinement. Materializes any new topical words, then
    /// replaces the scene's pages and home key. The scene's identity, name,
    /// description, and active/default flags are preserved (refinement changes
    /// content, not the scene record).
    static func update(
        _ scene: BlasterScene,
        from generated: GeneratedScene,
        tileLookup: [String: TileModel],
        context: ModelContext
    ) throws {
        try context.transaction {
            var lookup = tileLookup

            for genPage in generated.pages {
                for genTile in genPage.tiles where genTile.isProposedNew {
                    guard lookup[genTile.key] == nil,
                          let displayName = genTile.displayName,
                          let wordClass = genTile.wordClass else { continue }
                    let tile = TileModel(key: genTile.key, value: displayName, wordClass: wordClass)
                    tile.isSystem = false
                    context.insert(tile)
                    lookup[genTile.key] = tile
                }
            }

            // A refine regenerates every placement, and the model knows nothing
            // of conceal or levels. A word that survives on the same page keeps
            // the caregiver's choices; only genuinely new placements start shown.
            var prior: [String: TileEntry] = [:]
            for page in scene.pages {
                for entry in page.tiles { prior["\(page.key)/\(entry.key)"] = entry }
            }
            scene.pages = generated.pages.map { genPage in
                let tiles = genPage.tiles.compactMap { genTile -> TileEntry? in
                    guard lookup[genTile.key] != nil else { return nil }
                    let was = prior["\(genPage.key)/\(genTile.key)"]
                    return TileEntry(key: genTile.key, link: genTile.link, isAudible: genTile.isAudible,
                                     isConcealed: was?.isConcealed ?? false,
                                     revealLevel: was?.revealLevel ?? 0)
                }
                return PageSpec(key: genPage.key, displayName: genPage.displayName, tiles: tiles)
            }
            scene.homePageKey = generated.homePageKey
        }
    }
}
