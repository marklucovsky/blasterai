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

    /// Why this tile was hidden, when it was hidden automatically — e.g. the
    /// moderation gate's reason ("not appropriate for a young board"). Nil for
    /// caregiver-initiated hides. Surfaced in the Vocab manager so a caregiver can
    /// see the record of what was auto-blocked (and restore a false positive).
    var retiredReason: String?

    /// Set when the moderation review FLAGGED this word (added via Add-Tiles,
    /// where there's no Accept gate) — the caregiver must keep or remove it. Like
    /// a blocked (`isRetired`) word, a `needsReview` word is INVISIBLE in running
    /// scenes until the caregiver resolves it; the page editor shows it 🟡 and the
    /// scene's page list surfaces the count. Cleared on Keep; retired (hidden) on
    /// Hide — never hard-deleted. Defaulted Bool → clean CloudKit migration.
    var needsReview: Bool = false

    /// The single named safety invariant: a tile is invisible to the child in a
    /// running scene when it's retired (hidden) OR still awaiting the caregiver's
    /// keep/hide decision. Every child-facing surface must honor this.
    var isHiddenFromChild: Bool { isRetired || needsReview }

    // MARK: - Review-state transitions
    // Centralized so the review surfaces (Vocab manager, page editor, Add-Tiles
    // audit) can't diverge on which flags a transition touches. Callers that hide
    // for safety also purge the word's cached sentences and save the context.

    /// Retire (hide) the word — reversible. `reason` records an automatic
    /// (moderation) hide; nil for a caregiver-initiated one.
    func retire(reason: String? = nil) {
        isRetired = true
        retiredReason = reason
        needsReview = false
    }

    /// Un-hide a retired word.
    func restore() {
        isRetired = false
        retiredReason = nil
    }

    /// Resolve review as approved — the word is clean and visible to the child again.
    func approveReview() {
        needsReview = false
        isRetired = false
        retiredReason = nil
    }

    /// Flag the word for caregiver review (hidden from the child until resolved).
    func flagForReview() {
        needsReview = true
    }

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
