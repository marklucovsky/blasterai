// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneMaterializer.swift
//  claudeBlast
//
//  Materializes a SceneJSON (with DSL commands) into concrete PageSpec
//  values for storage on BlasterScene. DSL commands run in document
//  order against a working tile list; later commands can observe and
//  modify earlier results.
//
//  Eager expansion at import time, per design discussion: the in-memory
//  scene holds concrete tile lists, not unevaluated DSL. If the bundled
//  vocabulary changes, scenes must be re-imported (handled by the
//  hash-based bootstrap detection in a later step).
//
//  Distinct from `SceneImporter` (which handles user-facing .blasterscene
//  file import/export between devices).
//

import Foundation

enum SceneMaterializer {

    /// Errors surfaced during materialization. Distinct from DecodingError
    /// so callers can render them in admin UI when scene authoring goes
    /// live.
    enum MaterializeError: Error, CustomStringConvertible {
        case unknownVocabularyKey(String)
        case unknownVocabularyClass(String)
        case homePageNotFound(String)

        var description: String {
            switch self {
            case .unknownVocabularyKey(let k): return "Unknown vocabulary key: \(k)"
            case .unknownVocabularyClass(let c): return "Unknown vocabulary class: \(c)"
            case .homePageNotFound(let k): return "homePageKey not present in pages: \(k)"
            }
        }
    }

    /// One-stop result type — what the materializer hands back. Carries
    /// the scene metadata alongside materialized pages so the caller can
    /// instantiate a BlasterScene directly.
    struct MaterializedScene {
        let key: String
        let name: String
        let description: String
        let homePageKey: String
        let isDefault: Bool
        let pages: [PageSpec]
    }

    /// Materialize a SceneJSON into concrete pages.
    ///
    /// - Parameters:
    ///   - scene: parsed scene JSON.
    ///   - vocabulary: ordered list of all available vocabulary entries
    ///     (as decoded from vocabulary.json). Vocab-file order is
    ///     preserved so `orderBy: .vocab` works deterministically.
    /// - Throws: `MaterializeError` for missing vocab references or a
    ///   homePageKey that doesn't match any page in the file.
    static func materialize(scene: SceneJSON,
                            vocabulary: [TileModelCodable]) throws -> MaterializedScene {

        let keySet   = Set(vocabulary.map(\.key))
        let classSet = Set(vocabulary.map(\.wordClass))

        var materializedPages: [PageSpec] = []
        for page in scene.pages {
            var tiles: [TileEntry] = []
            for cmd in page.tiles {
                try applyCommand(cmd, to: &tiles,
                                 vocabulary: vocabulary,
                                 keySet: keySet, classSet: classSet)
            }
            materializedPages.append(PageSpec(key: page.key, tiles: tiles))
        }

        guard materializedPages.contains(where: { $0.key == scene.homePageKey }) else {
            throw MaterializeError.homePageNotFound(scene.homePageKey)
        }

        return MaterializedScene(
            key: scene.key,
            name: scene.name,
            description: scene.description ?? "",
            homePageKey: scene.homePageKey,
            isDefault: scene.isDefault,
            pages: materializedPages
        )
    }

    // MARK: - Command expansion

    private static func applyCommand(
        _ cmd: PageBuildCommand,
        to tiles: inout [TileEntry],
        vocabulary: [TileModelCodable],
        keySet: Set<String>,
        classSet: Set<String>
    ) throws {
        switch cmd {

        case .classSelector(let classes, let exclude, let limit, let orderBy):
            for c in classes where !classSet.contains(c) {
                throw MaterializeError.unknownVocabularyClass(c)
            }
            let excludeSet = Set(exclude)
            var matches = vocabulary
                .filter { classes.contains($0.wordClass) && !excludeSet.contains($0.key) }
                .map(\.key)
            switch orderBy {
            case .vocab: break    // already in declaration order
            case .name:  matches.sort()
            case .score: break    // placeholder — vocab has no score yet
            }
            if let limit { matches = Array(matches.prefix(limit)) }
            for key in matches where !tiles.contains(where: { $0.key == key }) {
                tiles.append(TileEntry(key: key))
            }

        case .keys(let keys):
            for key in keys {
                guard keySet.contains(key) else {
                    throw MaterializeError.unknownVocabularyKey(key)
                }
                if !tiles.contains(where: { $0.key == key }) {
                    tiles.append(TileEntry(key: key))
                }
            }

        case .link(let key, let to, let audible):
            guard keySet.contains(key) else {
                throw MaterializeError.unknownVocabularyKey(key)
            }
            if let idx = tiles.firstIndex(where: { $0.key == key }) {
                // Update in place — preserves position the earlier command set.
                tiles[idx].link = to
                tiles[idx].isAudible = audible
            } else {
                tiles.append(TileEntry(key: key, link: to, isAudible: audible))
            }

        case .remove(let key):
            tiles.removeAll { $0.key == key }

        case .space(let count):
            // Appended without any dedupe check, unlike every other command
            // here. Those guard against placing the same word twice, which is
            // a mistake; two gaps in a row is a layout, and `TileEntry.spacer()`
            // mints a fresh random key each time so their identities differ.
            for _ in 0..<count {
                tiles.append(TileEntry.spacer())
            }
        }
    }
}
