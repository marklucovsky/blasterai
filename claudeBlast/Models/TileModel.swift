// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileModel.swift
//  claudeBlast
//

import SwiftData
import SwiftUI
import Foundation

enum TileType: String, Codable {
    case word
    case phrase
}

@Model
final class TileModel: Identifiable {
    var id: String = UUID().uuidString
    var created: Date = Date.now

    // Display
    var displayName: String = ""
    var bundleImage: String = ""
    var userImageData: Data?

    // Value
    var value: String = ""
    var type: TileType = TileType.word
    var key: String = ""
    var wordClass: String = ""

    /// True for tiles seeded from the bundled vocabulary (BootstrapLoader);
    /// false for caregiver-added words and tiles brought in by scene import.
    /// Lets authoring surfaces distinguish system vocabulary from extensions.
    /// Defaulted Bool so the schema migrates cleanly under CloudKit (same
    /// shape as `ChildProfile.isSystem`).
    var isSystem: Bool = false

    /// Reversible retirement (hide) — the default removal path for a word a
    /// caregiver no longer wants surfaced (e.g. a term a school disallows). A
    /// retired tile is hidden from pickers/grids and must not be added to new
    /// pages, but the record survives so CloudKit sync stays additive and history
    /// (`LoggedUtterance.tileKeys`, `MetricEvent`) can still render it. Un-retiring
    /// restores it. Hard delete remains a separate, explicit destructive path.
    /// Retiring for safety also purges the word's cached sentences
    /// (`SentenceCacheManager.invalidate(containingTileKey:)`) so a later un-retire
    /// can't resurrect a stale sentence. Defaulted Bool → clean CloudKit migration.
    var isRetired: Bool = false

    var userImage: UIImage? {
        guard let userImageData else { return nil }
        return UIImage(data: userImageData)
    }

    /// Canonical tile key from arbitrary text: lowercased, trimmed, with internal
    /// whitespace collapsed to underscores. The key is the asset/reference id, so
    /// it must be stable and space-free; the human label lives in `displayName`.
    static func normalizeKey(_ raw: String) -> String {
        raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "_")
    }

    convenience init(key: String, wordClass: String) {
        let normalizedKey = TileModel.normalizeKey(key)
        let normalizedValue = normalizedKey
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(key: normalizedKey, value: normalizedValue, wordClass: wordClass)
    }

    init(key: String, value: String, wordClass: String) {
        self.displayName = value
        self.value = value
        self.key = key
        self.bundleImage = key
        self.wordClass = wordClass
    }

    convenience init(from codable: TileModelCodable) {
        self.init(key: codable.key, wordClass: codable.wordClass)
    }
}
