// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneIdentityBackfill.swift
//  claudeBlast
//
//  One-shot: stamp a decentralized identity (sceneID/slug/version) onto scenes
//  that predate the identity fields, so existing installs show provenance and
//  bind scripts by a stable id — not just newly-created scenes. Idempotent
//  (skips anything already stamped); safe to run every launch.
//

import SwiftData
import Foundation

enum SceneIdentityBackfill {
    static func run(context: ModelContext) {
        guard let scenes = try? context.fetch(FetchDescriptor<BlasterScene>()) else { return }
        var changed = false
        // Mint the device author id only if we actually need it for a user scene.
        var deviceAuthorID: String?
        let deviceAuthorName = DeviceProfileStore.authorName(context: context)

        // Titles of BlasterAI's bundled starter scenes → their first-party slug.
        let starterByTitle = Dictionary(
            StarterSceneCatalog.all.map { ($0.title, $0.id) }, uniquingKeysWith: { first, _ in first })

        for scene in scenes where scene.sceneID.isEmpty {
            if !scene.systemSceneKey.isEmpty {
                scene.markFirstPartyIdentity()                       // bundled system scene
            } else if scene.isDefault {
                scene.slug = "empty"                                 // the default "Empty" scene
                scene.sceneID = SceneIdentity.id(authority: SceneIdentity.firstPartyAuthority, slug: "empty")
                scene.sceneVersion = "1.0.0"
            } else if scene.isImported, let starterSlug = starterByTitle[scene.name] {
                // A bundled starter imported before it carried an id — credit
                // BlasterAI (first-party) and capture its current baseline.
                scene.slug = starterSlug
                scene.sceneID = SceneIdentity.id(authority: SceneIdentity.firstPartyAuthority, slug: starterSlug)
                scene.sceneVersion = "1.0.0"
                scene.importedContentHash = scene.contentHash
            } else if scene.isImported {
                continue   // legacy import of unknown provenance — don't claim authorship
            } else {
                let authorID = deviceAuthorID ?? DeviceProfileStore.ensureAuthorID(context: context)
                deviceAuthorID = authorID
                scene.ensureIdentity(authorID: authorID, authorName: deviceAuthorName)
            }
            changed = true
        }

        // Ensure first-party scenes have a pristine baseline (so "modified locally"
        // works) even if they were stamped in an earlier build without one.
        for scene in scenes where scene.isFirstParty && scene.importedContentHash.isEmpty {
            scene.importedContentHash = scene.contentHash
            changed = true
        }

        if changed { try? context.save() }
    }
}
