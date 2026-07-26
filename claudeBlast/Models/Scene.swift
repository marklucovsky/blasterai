// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BlasterScene.swift
//  claudeBlast
//

import SwiftData
import Foundation
import CryptoKit

@Model
final class BlasterScene {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var homePageKey: String = "home"
    var isDefault: Bool = false
    var isActive: Bool = false
    var isImported: Bool = false
    /// When true, the scene is scaffolded with the lean "Focused" board (topical
    /// tiles + a minimal needs strip + the body & health page) instead of the
    /// full familiar Core board. Toggled in the editor; preserved across AI
    /// refinements so they re-scaffold at the same level. See SceneNavigation.
    var isFocused: Bool = false
    var created: Date = Date.now
    var lastModified: Date = Date.now
    /// Source URL if the scene was imported from a web link.
    var sourceURL: String = ""

    /// Non-empty for system-defined scenes backed by a bundled JSON file
    /// (e.g. "core_first"). Empty for user-created or duplicated scenes.
    /// Drives the AdminView "system scene" label and the bundle-update
    /// affordance — only a scene with a systemSceneKey can be force-refreshed
    /// from the bundle.
    var systemSceneKey: String = ""

    // MARK: - Decentralized identity (see SceneIdentity)

    /// Qualified id `"<authority>/<slug>"` — the author's self-generated id for
    /// user scenes, `scenes.blasterai.app` for first-party. Stable across renames
    /// and the primary key for TileScript resolution + import dedupe. Empty on
    /// legacy scenes predating this field → they resolve by name (back-compat).
    var sceneID: String = ""
    /// Short slug (UI + TileScript), derived from the name at stamp time.
    var slug: String = ""
    /// Semantic version for import dedupe (bumped on an edit-and-reshare).
    var sceneVersion: String = ""
    /// The author's self-asserted display name, carried in from an import.
    /// May be empty. Shown as "by <authorName>" provenance.
    var authorName: String = ""
    /// Local-only label the receiver assigns when an import has no `authorName`
    /// ("from Greta") — like naming a contact. Never travels back out.
    var receivedLabel: String = ""

    /// `contentHash` captured at import time. On a later re-import of the same
    /// `sceneID`, `contentHash != importedContentHash` means the receiver edited
    /// their copy — so an incoming update must not silently overwrite it. Empty
    /// for scenes not created via import (or imported before this field existed).
    var importedContentHash: String = ""

    /// Stable fingerprint of the scene's user-visible content (name + home page +
    /// pages). Used only to detect local edits vs. the imported baseline.
    var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(name.utf8))
        hasher.update(data: Data(homePageKey.utf8))
        hasher.update(data: pagesData)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Provenance to show in lists: the author's name, else the local tag, else "".
    var authorDisplay: String { authorName.isEmpty ? receivedLabel : authorName }

    /// How first-party (BlasterAI-shipped) content is credited in the UI.
    static let firstPartyAuthorDisplay = "BlasterAI"

    /// True for scenes BlasterAI ships — built-ins (bootstrapped, `systemSceneKey`)
    /// and bundled starters (id under the `scenes.blasterai.app` authority).
    var isFirstParty: Bool {
        !systemSceneKey.isEmpty || sceneID.hasPrefix(SceneIdentity.firstPartyAuthority + "/")
    }

    /// True once the local user has edited this scene away from its pristine
    /// baseline (the bundled or imported content it started as). Only meaningful
    /// when a baseline was captured — user-authored-from-scratch scenes have none.
    var isLocallyModified: Bool {
        !importedContentHash.isEmpty && contentHash != importedContentHash
    }

    /// Provenance line for the scenes list: "by BlasterAI", "by Greta",
    /// "by BlasterAI, modified locally", etc. Empty when there's nothing to say.
    /// Display fallbacks (display-only — stored `authorName` stays empty so
    /// exports never carry a fabricated author).
    static let unknownAuthorDisplay = "Unknown"   // others, unnamed
    static let selfAuthorDisplay = "Me"           // mine, unnamed

    /// How the scene got onto this device (persists with the scene) — drives the
    /// list's provenance dot + label:
    /// - `.firstParty` — BlasterAI-shipped (a built-in or bundled starter);
    /// - `.imported` — arrived as a shared `.blasterscene` file (`isImported`),
    ///   *regardless of who originally authored it*;
    /// - `.local` — authored on this device, living in the user's iCloud.
    enum Provenance { case firstParty, local, imported }

    var provenance: Provenance {
        if isFirstParty { return .firstParty }
        return isImported ? .imported : .local
    }

    /// Attribution label: "by BlasterAI" / "by Mark" / "by Greta" / "by Me"
    /// (local, unnamed) / "by Unknown" (imported, unnamed), plus ", modified
    /// locally" once edited past the baseline. The dot color conveys origin;
    /// this text conveys authorship.
    var attribution: String {
        let who: String
        switch provenance {
        case .firstParty: who = Self.firstPartyAuthorDisplay
        case .local:      who = authorDisplay.isEmpty ? Self.selfAuthorDisplay : authorDisplay
        case .imported:   who = authorDisplay.isEmpty ? Self.unknownAuthorDisplay : authorDisplay
        }
        return isLocallyModified ? "by \(who), modified locally" : "by \(who)"
    }

    /// The most-specific, rename-proof value to write into a TileScript's
    /// `scene:` field — the stable `sceneID` when present, else the name
    /// (back-compat for legacy scenes). Resolved at playback via the id→slug→name
    /// ladder, so a shared script binds to the intended scene, not "whatever's active".
    var scriptReference: String { sceneID.isEmpty ? name : sceneID }

    /// Human-readable provenance shown once in the editor right after creation:
    /// "⚡ Served from cache" for an unedited bundled starter, or
    /// "Generated · N tokens" for a live AI pass. Purely informational; the
    /// editor lets the caregiver dismiss it (clears the string).
    var creationSummary: String = ""

    /// JSON-encoded [PageSpec], stored inline. Exposed via `pages` accessor.
    /// Kept as Data (not [PageSpec] direct) for CloudKit compatibility — SwiftData's
    /// CloudKit mirror is conservative about Codable arrays-as-attributes.
    private var pagesData: Data = Data()

    /// Inline page list — replaces the prior PageModel relationship. Pages are
    /// scene-scoped (their `key` is unique only within this scene). No cross-scene
    /// sharing, no SwiftData @Relationship inverse, no deletion-rule fragility.
    var pages: [PageSpec] {
        get {
            guard !pagesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([PageSpec].self, from: pagesData)) ?? []
        }
        set {
            pagesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            lastModified = .now
        }
    }

    init(name: String, descriptionText: String = "", homePageKey: String = "home",
         isDefault: Bool = false, isActive: Bool = false) {
        self.name = name
        self.descriptionText = descriptionText
        self.homePageKey = homePageKey
        self.isDefault = isDefault
        self.isActive = isActive
    }

    // MARK: - Identity

    /// Idempotently stamp a decentralized identity for a user-authored scene.
    /// No-op once `sceneID` is set. `authorID` is the device's self-generated id.
    func ensureIdentity(authorID: String, authorName: String = "") {
        guard sceneID.isEmpty else { return }
        let s = SceneIdentity.slug(from: name)
        slug = s
        sceneID = SceneIdentity.id(authority: authorID, slug: s)
        if sceneVersion.isEmpty { sceneVersion = "1.0.0" }
        if self.authorName.isEmpty { self.authorName = authorName }
    }

    /// Stamp a first-party identity for a bundled system scene (keyed by
    /// `systemSceneKey`). No-op for non-system scenes.
    func markFirstPartyIdentity() {
        guard !systemSceneKey.isEmpty else { return }
        slug = systemSceneKey
        sceneID = SceneIdentity.id(authority: SceneIdentity.firstPartyAuthority, slug: systemSceneKey)
        if sceneVersion.isEmpty { sceneVersion = "1.0.0" }
    }

    // MARK: - Page mutations (helpers for editor views)

    /// Append a tile to the page with `pageKey`. No-op if the page doesn't exist.
    func appendTile(_ entry: TileEntry, toPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        pages[idx].tiles.append(entry)
        self.pages = pages
    }

    /// Remove every tile matching `key` from page `pageKey`.
    func removeTile(withKey key: String, fromPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        pages[idx].tiles.removeAll { $0.key == key }
        self.pages = pages
    }

    /// Reorder a tile within a page.
    func moveTile(from source: Int, to destination: Int, inPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        guard source != destination,
              pages[idx].tiles.indices.contains(source),
              pages[idx].tiles.indices.contains(destination) else { return }
        let moved = pages[idx].tiles.remove(at: source)
        pages[idx].tiles.insert(moved, at: destination)
        self.pages = pages
    }

    /// Find a page by key in this scene.
    func page(withKey key: String) -> PageSpec? {
        pages.first { $0.key == key }
    }

    /// Activate this scene, deactivating any other active scene in the context.
    func activate(context: ModelContext) throws {
        let allScenes = try context.fetch(FetchDescriptor<BlasterScene>())
        for scene in allScenes where scene.isActive {
            scene.isActive = false
        }
        self.isActive = true
    }

    /// Deactivate this scene and restore the default scene.
    func deactivateAndRestoreDefault(context: ModelContext) throws {
        self.isActive = false
        let defaultScenes = try context.fetch(
            FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.isDefault })
        )
        if let defaultScene = defaultScenes.first {
            defaultScene.isActive = true
        }
    }

    // MARK: - Duplicate

    /// Create a peer copy of `source`. The new scene is inserted into `context`
    /// and returned.
    ///
    /// Conventions:
    /// - name: "duplicate-of:{source.name}" with a "-2", "-3", … suffix if
    ///   that name is already taken (collision avoidance).
    /// - description: "duplicated from {source.name}::{ISO8601 source.created}"
    ///   so provenance survives even if the source is later renamed or deleted.
    /// - created: now.
    /// - isDefault / isActive / isImported: false (a fresh duplicate is never
    ///   the active scene and is never marked as the default).
    /// - systemSceneKey: empty. Duplicates of a system scene are user-owned
    ///   copies; they're not protected by the force-refresh path and won't
    ///   be touched by bundled updates.
    /// - pages: deep copy of the source's PageSpec list.
    @discardableResult
    static func duplicate(of source: BlasterScene, in context: ModelContext) -> BlasterScene {
        let baseName = "duplicate-of:\(source.name)"
        let existingNames: Set<String> = (try? context.fetch(FetchDescriptor<BlasterScene>()))
            .map { Set($0.map(\.name)) } ?? []
        var candidate = baseName
        var n = 2
        while existingNames.contains(candidate) {
            candidate = "\(baseName)-\(n)"
            n += 1
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let originStamp = iso.string(from: source.created)

        let copy = BlasterScene(
            name: candidate,
            descriptionText: "duplicated from \(source.name)::\(originStamp)",
            homePageKey: source.homePageKey,
            isDefault: false,
            isActive: false
        )
        copy.pages = source.pages  // deep copy via Codable round-trip in the setter
        // A duplicate is a new, locally-owned scene: give it a fresh identity
        // under this device's author id (sceneID starts empty → ensureIdentity
        // mints a new one from the duplicate's name).
        copy.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: context),
                            authorName: DeviceProfileStore.authorName(context: context))
        context.insert(copy)
        return copy
    }
}
