// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptValidator.swift
//  claudeBlast
//
//  Preflight check for a TileScript: confirms its target scene exists and that
//  every tile/page it references is present, so a demo never plays half-broken
//  (silently dropping tiles / no-op navigations) against the wrong scene.
//

import Foundation
import SwiftData

enum TileScriptValidator {
    /// Sentinel `scene:` value meaning "the built-in default scene" — rename-proof
    /// (resolves to the `isDefault` scene rather than a literal name).
    static let defaultSceneSentinel = "<default>"

    struct Result: Equatable {
        /// A named target scene that doesn't exist (nil if the scene resolved).
        var missingScene: String?
        var missingTiles: [String]
        var missingPages: [String]

        var isValid: Bool { missingScene == nil && missingTiles.isEmpty && missingPages.isEmpty }
    }

    /// Resolve a script's `scene` value to a concrete scene: the `<default>`
    /// sentinel → the `isDefault` scene; nil value → the currently active scene;
    /// otherwise a resolution ladder **sceneID → slug → displayName**. The ladder
    /// makes a shared script bind to the intended (e.g. Greta's) scene by its
    /// stable id even if locally renamed, while older name-only references — and
    /// hand-authored scripts — still resolve by name.
    static func resolveScene(_ value: String?, in scenes: [BlasterScene]) -> BlasterScene? {
        guard let value else { return scenes.first { $0.isActive } }
        if value == defaultSceneSentinel { return scenes.first { $0.isDefault } }
        return scenes.first { $0.sceneID == value }
            ?? scenes.first { !$0.slug.isEmpty && $0.slug == value }
            ?? scenes.first { $0.name == value }
    }

    static func validate(_ script: TileScript, context: ModelContext) -> Result {
        let scenes = (try? context.fetch(FetchDescriptor<BlasterScene>())) ?? []
        let tileKeys = Set(((try? context.fetch(FetchDescriptor<TileModel>())) ?? []).map(\.key))

        // A declared (named, non-sentinel) scene that isn't present is the root
        // problem — report it and skip page checks (they'd all spuriously fail).
        var missingScene: String?
        if let declared = script.scene, declared != defaultSceneSentinel,
           resolveScene(declared, in: scenes) == nil {
            missingScene = declared
        }

        let target = resolveScene(script.scene, in: scenes)
        let pageKeys = Set((target?.pages.map(\.key) ?? []) + ["home"])

        var missingTiles = Set<String>()
        var missingPages = Set<String>()
        for command in script.commands {
            guard case .tiles(let rows) = command else { continue }
            for row in rows {
                for action in row.actions {
                    switch action {
                    case .tap(let key):
                        if !tileKeys.contains(key) { missingTiles.insert(key) }
                    case .navigate(let key):
                        if !pageKeys.contains(key) { missingPages.insert(key) }
                    case .audibleNavigate(let key):   // taps the key AND navigates to it
                        if !pageKeys.contains(key) { missingPages.insert(key) }
                        if !tileKeys.contains(key) { missingTiles.insert(key) }
                    case .replay, .noclose:
                        break
                    }
                }
            }
        }
        if missingScene != nil { missingPages.removeAll() }
        return Result(missingScene: missingScene,
                      missingTiles: missingTiles.sorted(),
                      missingPages: missingPages.sorted())
    }
}
