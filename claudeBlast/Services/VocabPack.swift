// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftData
import Foundation

/// A vocabulary pack: a named, installable set of words that EXTENDS the base
/// vocabulary. A pack is pure vocab — words only; its art ships as ordinary set
/// assets (p3d_/cls_), so an installed pack word is a first-class multi-set tile.
/// (For now system packs are bundled; a portable "carry-your-own-art" form is a
/// later swap behind this same abstraction.)
struct VocabPackWord: Decodable, Hashable {
    let key: String
    let wordClass: String
    let displayName: String
}

struct VocabPack: Identifiable, Decodable, Hashable {
    /// Namespaced, globally-unique id, e.g. "packs.blasterai.app/space".
    let id: String
    let slug: String
    let displayName: String
    let version: String
    /// Slug for the pack's thematic cover image: Resources/packicon_<icon>.png.
    let icon: String
    let words: [VocabPackWord]
}

enum PackCatalog {
    private struct Entry: Decodable { let id, slug, displayName, version, file: String }

    /// All bundled system packs, decoded once from packs.json + pack_<slug>.json.
    static let all: [VocabPack] = {
        guard let url = Bundle.main.url(forResource: "packs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.compactMap { entry in
            guard let u = Bundle.main.url(forResource: entry.file, withExtension: "json"),
                  let d = try? Data(contentsOf: u) else { return nil }
            return try? JSONDecoder().decode(VocabPack.self, from: d)
        }
    }()

    static func pack(id: String) -> VocabPack? { all.first { $0.id == id } }

    /// Image key for the pack's two-set thematic cover (p3d_packcover_<slug> /
    /// cls_packcover_<slug>). A page built from a pack aliases this on its
    /// page_link tile (via bundleImage) so the cover switches with the active set,
    /// exactly like a pack word.
    static func coverKey(for pack: VocabPack) -> String { "packcover_\(pack.slug)" }
}

enum PackInstaller {
    /// Insert any of the pack's words not already present as TileModels. Idempotent.
    /// Pack words are system vocab; `bundleImage == key` (default) so the bundled
    /// p3d_/cls_ art resolves and switches with the active set.
    @discardableResult
    static func install(_ pack: VocabPack, context: ModelContext, existing: [String: TileModel]) -> Int {
        var added = 0
        for w in pack.words where existing[w.key] == nil {
            let tile = TileModel(key: w.key, value: w.displayName, wordClass: w.wordClass)
            tile.isSystem = true
            context.insert(tile)
            added += 1
        }
        return added
    }
}

// Note: page-tile production for packs / copied pages / class & key sets now
// lives in `CollectionSource` (Services/CollectionSource.swift).
