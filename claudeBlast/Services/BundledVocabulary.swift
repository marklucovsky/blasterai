// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BundledVocabulary.swift
//  claudeBlast
//
//  What every install already has, without being sent it.
//

import Foundation

/// The keys in `Resources/vocabulary.json` — the words a fresh install owns.
///
/// ## Why this is not `TileModel.isSystem`
///
/// Export uses this to decide which words a scene must carry: a word the
/// recipient already has needs only its key, and one they do not have must
/// travel with its identity or the page arrives empty.
///
/// `isSystem` looks like the same question and is not. It marks *first-party
/// provenance* — "we made this word, the caregiver did not" — and
/// `PackInstaller` sets it on bundled **pack** words for that reason, correctly.
/// But a pack installs on demand. Its words are first-party and absent from a
/// fresh install at the same time, so treating `isSystem` as "they already have
/// it" silently drops every pack word from an export.
///
/// That was a real failure, not a hypothetical: a scene built from the Space,
/// Vehicles, Tide Pools and Dinosaurs packs exported 43 page references and
/// **6** tiles — the only survivors being two words added by hand and the four
/// page links. Every page arrived empty on the far side, and because the board
/// had nothing to draw, the receiving device had no way back into Admin.
///
/// Bundled ART is a separate matter and needs no help here: pack art ships in
/// the binary under the word's own key, so a carried pack word renders on the
/// recipient with no image bytes sent.
enum BundledVocabulary {

    /// Decoded once. The file is ~500 entries and export asks per share.
    static let keys: Set<String> = {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TileModelCodable].self, from: data)
        else { return [] }
        return Set(decoded.map(\.key))
    }()

    /// Whether a fresh install would already own this word.
    ///
    /// An empty `keys` — a missing or unreadable bundle resource — answers false
    /// for everything, so an export carries too much rather than too little. The
    /// costs are not symmetric: a fat file is a slow share, a thin one is an
    /// empty board.
    static func contains(_ key: String) -> Bool { keys.contains(key) }
}
