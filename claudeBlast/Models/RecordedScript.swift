// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  RecordedScript.swift
//  claudeBlast
//

import Foundation
import SwiftData

@Model
final class RecordedScript {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var yamlContent: String = ""
    /// The scene this script binds to, as a `BlasterScene.scriptReference` — the
    /// stable `sceneID` when the scene has one, falling back to its name only for
    /// legacy scenes predating PR #44. Resolved at playback through the
    /// id→slug→name ladder, so a shared script follows the intended scene across
    /// renames.
    ///
    /// NOT a display name: never look a scene up by matching this against
    /// `BlasterScene.name`. It was called `sceneName` until the pre-promotion
    /// schema audit, which is a name that would have been frozen into the
    /// CloudKit schema forever while holding an identifier.
    var sceneRef: String = ""
    var created: Date = Date.now

    init(name: String, descriptionText: String = "", yamlContent: String, sceneRef: String) {
        self.id = UUID().uuidString
        self.name = name
        self.descriptionText = descriptionText
        self.yamlContent = yamlContent
        self.sceneRef = sceneRef
        self.created = .now
    }
}
