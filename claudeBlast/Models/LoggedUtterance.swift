// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LoggedUtterance.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Persisted record of a finalized tile group — what the child "said," when, and how many
/// times the same combo escalated before commit. Therapist/partner-facing review log.
/// No `@Attribute(.unique)` so the schema stays CloudKit-compatible.
@Model
final class LoggedUtterance {
    var id: String = UUID().uuidString
    var tileKeys: [String] = []
    var sentence: String = ""
    var createdAt: Date = Date.now
    var repetitionCount: Int = 0
    /// Display-name SNAPSHOT of the scene at commit time. Deliberately
    /// denormalized: it's the only thing that still reads correctly after the
    /// scene is deleted. Never use it to identify a scene — use `sceneID`.
    /// **Empty means "no scene recorded".**
    var sceneName: String = ""
    /// `BlasterScene.sceneID` — the rename-proof identity from PR #44.
    /// **Empty** for rows written with no active scene, or for scenes with no
    /// stamped identity. Use for joining/filtering history to a scene; use
    /// `sceneName` only for display fallback.
    var sceneID: String = ""
    /// `ChildProfile.id` whose interaction produced this utterance.
    /// **Empty means "unknown"** — therapist analytics that filter by child
    /// should treat it as unknown rather than "any."
    var childID: String = ""

    init(
        tileKeys: [String],
        sentence: String,
        repetitionCount: Int = 0,
        sceneName: String? = nil,
        sceneID: String? = nil,
        childID: String? = nil,
        createdAt: Date = .now
    ) {
        self.tileKeys = tileKeys
        self.sentence = sentence
        self.repetitionCount = repetitionCount
        self.sceneName = sceneName ?? ""
        self.sceneID = sceneID ?? ""
        self.childID = childID ?? ""
        self.createdAt = createdAt
    }

    /// Scene label for review UI, resilient to both rename and deletion:
    ///
    /// 1. Scene still exists → its CURRENT name (a rename is reflected in history).
    /// 2. Scene was deleted → the name snapshot captured at commit time.
    /// 3. Neither → nil (caller omits the attribution rather than showing a
    ///    dangling identifier).
    func sceneDisplayName(resolving scenes: [BlasterScene]) -> String? {
        if !sceneID.isEmpty,
           let live = scenes.first(where: { $0.sceneID == sceneID }) {
            return live.name
        }
        return sceneName.isEmpty ? nil : sceneName
    }
}
