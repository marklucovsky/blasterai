// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CodableTypes.swift
//  claudeBlast
//
//  Lightweight Codable struct for decoding vocabulary.json. Scene/page
//  decoding lives in SceneJSON.swift now that pages are inline.
//

import Foundation

struct TileModelCodable: Codable {
    let key: String
    let wordClass: String
    /// Another word's art, reused for this one.
    ///
    /// `him` and `he` are the same picture and different grammar, as are
    /// `her`/`she`, `them`/`they`, `us`/`we`. Generating a second image would
    /// cost money to produce something a child cannot tell apart, and would
    /// drift from its twin the next time either is regenerated.
    ///
    /// Absent for almost every word, where the key *is* the asset name.
    var bundleImage: String?
    /// What the tile reads, when spelling it from the key gets it wrong.
    ///
    /// A key is lowercase and space-free by rule, and the label is normally the
    /// key with underscores as spaces. That is wrong for `i` (the pronoun is
    /// always "I"), `i_dont_know` (capital and an apostrophe), and `tv`. The
    /// key stays as it is: it names the art and the cache, and changing it
    /// would orphan both.
    ///
    /// Absent for almost every word.
    var label: String?

    /// The label a tile from this entry starts with.
    var resolvedLabel: String {
        if let label, !label.isEmpty { return label }
        return TileModelCodable.defaultLabel(forKey: key)
    }

    /// The key spelled as a label, which is what every tile got before `label`
    /// existed — and so what an existing install still shows.
    static func defaultLabel(forKey key: String) -> String {
        TileModel.normalizeKey(key)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
