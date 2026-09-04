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
}
