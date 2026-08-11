// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceCache.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class SentenceCache {
    var id: String = UUID().uuidString
    var cacheKey: String = ""
    var tileKeys: [String] = []
    var sentence: String = ""
    var hitCount: Int = 0
    var isPinned: Bool = false

    /// Version-INDEPENDENT identity (sorted tile keys + child) — see
    /// `CacheKeyPolicy.stableKey`. Set on every entry at creation so a durable
    /// caregiver override can be matched regardless of the model/prompt/grade/class
    /// that shaped `cacheKey`. Empty for legacy rows written before this field.
    var stableKey: String = ""

    /// Caregiver-typed the sentence themselves — an authoritative override that
    /// serves for this tile combination regardless of what the model would produce.
    var isCaregiverEdited: Bool = false

    /// Caregiver blocked this tile combination's cached output. A suppressed entry
    /// is never served or stored as canonical; the engine regenerates live each
    /// time so a bad cached answer can't stick.
    var isSuppressed: Bool = false

    /// Caregiver kept a refined/try-again result. Pinned + TTL-immune; served via
    /// the version-independent override path so it survives prompt-version bumps.
    var caregiverAccepted: Bool = false

    /// True when the entry carries deliberate caregiver intent (hand-typed,
    /// suppressed, or accepted-refine) — the durable-override set. These are
    /// matched on `stableKey` and exempt from eviction (`isPinned` set alongside).
    var isOverride: Bool { isCaregiverEdited || isSuppressed || caregiverAccepted }

    /// Tie-break when more than one override shares a `stableKey`: an explicit
    /// hand-edit or suppress outranks an auto-accepted refine.
    var overrideRank: Int {
        if isCaregiverEdited { return 3 }
        if isSuppressed { return 2 }
        if caregiverAccepted { return 1 }
        return 0
    }
    /// Set at creation; read by `CloudKitDedupReconciler.dedupeSentenceCache` as
    /// the tie-breaker when two synced duplicates share a `hitCount` (keep the
    /// newer). NOT vestigial — do not remove without updating that dedup order.
    var created: Date = Date.now
    var lastUsed: Date = Date.now
    /// `ChildProfile.id` whose interaction produced this cache entry.
    /// **Empty means "unknown child"** (no active profile at write time).
    /// Reserved for per-child cache filtering / analytics; v1 lookups ignore it.
    /// Not optional, per the no-optionals rule on `BlasterSchemaV1` — callers
    /// still pass `String?` and it is coerced here.
    var childID: String = ""
    /// `CacheKeyPolicy.versionToken` (model id + prompt version) at write time.
    /// Drives stale-entry eviction: a model/prompt-version change leaves old
    /// entries with a mismatched token, swept at launch and on demand. Empty
    /// for legacy entries written before this field existed → treated as stale.
    var keyVersion: String = ""

    init(tiles: [TileSelection], grade: Int, sentence: String, childID: String? = nil) {
        self.tileKeys = tiles.map(\.key)
        self.cacheKey = CacheKeyPolicy.key(for: tiles, grade: grade)
        self.stableKey = CacheKeyPolicy.stableKey(for: tiles, childID: childID)
        self.sentence = sentence
        self.childID = childID ?? ""
        self.keyVersion = CacheKeyPolicy.versionToken
    }
}
