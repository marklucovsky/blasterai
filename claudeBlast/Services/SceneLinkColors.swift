// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneLinkColors.swift
//  claudeBlast
//
//  Keeping automatic folder colors true to the pages they describe.
//

import Foundation
import SwiftData

/// Applies `LinkColorResolver` across a whole scene.
///
/// ## The problem this solves
///
/// A folder's color is resolved once and stored, never computed when drawn —
/// otherwise a folder would change color under a child because someone added
/// three nouns to the page behind it, and motor planning needs invariants.
///
/// But pages genuinely do change. A caregiver who turns a folder of nouns into a
/// folder of verbs should see the folder follow, or the board starts lying about
/// itself. So a stored color is re-resolved at exactly one moment: when the page
/// it describes is edited — and only for links whose color was derived rather
/// than chosen. `TileEntry.linkColorIsAuto` is what tells those apart.
///
/// ## Why it is idempotent, and why that matters
///
/// The editor calls this after a page changes, and applying it writes
/// `scene.pages`, which is itself a change. `refresh` returns whether it altered
/// anything and writes nothing when it did not, so a second pass is a no-op and
/// the cycle terminates on its own rather than through a flag someone has to
/// remember to set.
enum SceneLinkColors {

    /// Re-resolve every automatic link in `pages`.
    ///
    /// - Returns: true when at least one color changed, so a caller can skip
    ///   writing — see the note above about not looping.
    static func refresh(_ pages: inout [PageSpec],
                        vocabulary: [String],
                        partOfSpeech: (String) -> PartOfSpeech?) -> Bool {
        let background = LinkColorResolver.background(for: vocabulary,
                                                      partOfSpeech: partOfSpeech)
        let byKey = Dictionary(pages.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        var changed = false
        for pageIndex in pages.indices {
            for tileIndex in pages[pageIndex].tiles.indices {
                let tile = pages[pageIndex].tiles[tileIndex]
                guard !tile.link.isEmpty, tile.linkColorIsAuto else { continue }
                // `<home>` resolves at navigation time and names no page here.
                // A nil destination is not an error: an audible link is colored
                // by its own word regardless, and a silent one with nowhere to
                // point is wayfinding by definition.
                let slot = LinkColorResolver.slot(for: tile,
                                                  destination: byKey[tile.link]?.tiles,
                                                  partOfSpeech: partOfSpeech,
                                                  background: background)
                if tile.linkColor != slot.rawValue {
                    pages[pageIndex].tiles[tileIndex].linkColor = slot.rawValue
                    changed = true
                }
            }
        }
        return changed
    }

    /// Resolve one link against a scene, for the moment a link is created or
    /// repointed — before any page has changed, so a new folder is never briefly
    /// the wrong color.
    ///
    /// `isAudible` matters here too: a link that speaks takes its own word's
    /// color. Toggling "Add to sentence tray" therefore changes the tile's
    /// color, which is correct — it changes what the tile *is*.
    static func slot(forLinkTo pageKey: String,
                     spokenAs key: String = "",
                     isAudible: Bool = false,
                     in pages: [PageSpec],
                     vocabulary: [String],
                     partOfSpeech: (String) -> PartOfSpeech?) -> TileColorSlot {
        let background = LinkColorResolver.background(for: vocabulary,
                                                      partOfSpeech: partOfSpeech)
        let entry = TileEntry(key: key, link: pageKey, isAudible: isAudible)
        return LinkColorResolver.slot(
            for: entry,
            destination: pages.first(where: { $0.key == pageKey })?.tiles,
            partOfSpeech: partOfSpeech,
            background: background)
    }

    // MARK: - Convenience over the store

    /// The vocabulary keys and part-of-speech lookup the resolver needs, taken
    /// from the store so a correction a therapist made to a word's type is
    /// reflected in the folders that word sits behind.
    @MainActor
    static func refresh(scene: BlasterScene, context: ModelContext) {
        let descriptor = FetchDescriptor<TileModel>()
        let tiles = (try? context.fetch(descriptor)) ?? []
        var pages = scene.pages
        let changed = refresh(&pages,
                              vocabulary: tiles.map(\.key),
                              partOfSpeech: { PartOfSpeechIndex.partOfSpeech(for: $0) })
        if changed { scene.pages = pages }
    }
}
