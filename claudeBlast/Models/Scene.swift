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
    ///
    /// It is also the **immutability marker** — see `isSystemOwned`.
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

    // MARK: - System ownership (immutability)

    /// Marker appended to the name of a bundle-backed scene we own.
    static let systemSuppliedSuffix = " - System Supplied"
    /// Marker appended when a caregiver takes an editable copy of one.
    static let myCopySuffix = " - My Copy"

    /// **System-owned scenes are immutable.** They are bundle-backed, we ship
    /// them, and the caregiver edits a *copy* instead (`cloneForEditing`).
    ///
    /// This exists to close two problems with one rule:
    ///
    /// 1. **App updates.** We change the bundled board between releases. If a
    ///    caregiver's edits lived in it, refreshing from the bundle would destroy
    ///    their work — so the refresh had to ask permission and offer to save a
    ///    copy first. With nothing of theirs inside, the bundle is free to change.
    /// 2. **Multi-device sync.** `needsBootstrap()` gates on a per-device
    ///    UserDefaults flag that never syncs, so every fresh install bootstraps
    ///    its own copy of the system scenes. `CloudKitDedupReconciler` then
    ///    collapses them by `systemSceneKey` — and whichever copy it keeps, the
    ///    other is deleted. That was destroying caregiver edits: a *fresh*
    ///    bootstrap is always newer than a prior edit, so "keep most recently
    ///    modified" systematically preferred the pristine newcomer.
    ///
    /// The invariant that makes this airtight: **the set of scenes the reconciler
    /// may collapse is exactly the set that can never diverge.** `dedupeSystemScenes`
    /// groups on a non-empty `systemSceneKey` and skips everything else, which is
    /// precisely the set marked immutable here. A collapse can therefore never
    /// destroy user work, because no user work can be in there.
    var isSystemOwned: Bool { !systemSceneKey.isEmpty }

    /// The name without the system-supplied marker, so a copy of
    /// "Core-First - System Supplied" is named "Core-First - My Copy" rather than
    /// stacking both suffixes.
    var baseName: String {
        name.hasSuffix(Self.systemSuppliedSuffix)
            ? String(name.dropLast(Self.systemSuppliedSuffix.count))
            : name
    }

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

    /// Remove every tile whose key is in `keys` from page `pageKey` (bulk delete).
    func removeTiles(withKeys keys: Set<String>, fromPage pageKey: String) {
        guard !keys.isEmpty else { return }
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        pages[idx].tiles.removeAll { keys.contains($0.key) }
        self.pages = pages
    }

    /// Move the tiles whose keys are in `keys` to the front or end of page
    /// `pageKey`, preserving their existing relative order (bulk reorder).
    func moveTiles(withKeys keys: Set<String>, toFront: Bool, inPage pageKey: String) {
        guard !keys.isEmpty else { return }
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        let moving = pages[idx].tiles.filter { keys.contains($0.key) }
        let rest = pages[idx].tiles.filter { !keys.contains($0.key) }
        pages[idx].tiles = toFront ? moving + rest : rest + moving
        self.pages = pages
    }

    /// Duplicate page `pageKey` within this scene under a fresh, de-duped key
    /// (`<key>_2`, `_3`, …). Same-scene structural copy — tiles are value types,
    /// so the copy is independent; no link placement. Returns the new key.
    @discardableResult
    func duplicatePage(_ pageKey: String) -> String? {
        var pages = self.pages
        guard let src = pages.first(where: { $0.key == pageKey }) else { return nil }
        let existing = Set(pages.map(\.key))
        var n = 2
        var candidate = "\(pageKey)_\(n)"
        while existing.contains(candidate) { n += 1; candidate = "\(pageKey)_\(n)" }
        pages.append(PageSpec(key: candidate, tiles: src.tiles))
        self.pages = pages
        return candidate
    }

    /// The key that should become home when the current home page is toggled off.
    /// Prefer a page keyed "home" (unless the current home IS that page — then
    /// don't get stuck on it), otherwise the first other page in the list.
    /// `nil` when there is no other page (a sole page stays home).
    func homeKeyAfterTogglingOffCurrent() -> String? {
        let current = homePageKey
        if let named = pages.first(where: { $0.key == "home" && $0.key != current })?.key {
            return named
        }
        return pages.first(where: { $0.key != current })?.key
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

    // MARK: - Naming

    /// `base`, or `base-2` / `base-3` / … if that name is already taken.
    static func availableName(basedOn base: String, in context: ModelContext) -> String {
        let taken: Set<String> = (try? context.fetch(FetchDescriptor<BlasterScene>()))
            .map { Set($0.map(\.name)) } ?? []
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    // MARK: - Clone-on-write

    /// Take a user-owned, editable copy of a system-owned scene.
    ///
    /// The copy is a genuinely independent, locally-authored scene — it drops
    /// `systemSceneKey`, which is what makes it editable, deletable, and
    /// invisible to `dedupeSystemScenes`. It gets a fresh identity under this
    /// device's author id, so two devices cloning the same system scene produce
    /// two distinct scenes rather than a collision.
    ///
    /// `importedContentHash` is deliberately cleared: the copy has no pristine
    /// baseline to diverge from, so `isLocallyModified` stays false and the
    /// scenes list doesn't label a brand-new copy as "modified locally".
    ///
    /// Inserts into `context` and returns the copy; the caller activates it.
    @discardableResult
    static func cloneForEditing(_ source: BlasterScene, in context: ModelContext,
                                authorID: String, authorName: String) -> BlasterScene {
        let copy = BlasterScene(
            name: availableName(basedOn: source.baseName + myCopySuffix, in: context),
            descriptionText: source.descriptionText,
            homePageKey: source.homePageKey,
            isDefault: false,
            isActive: false
        )
        copy.isFocused = source.isFocused
        copy.pages = source.pages           // deep copy via the Codable round-trip
        copy.systemSceneKey = ""            // ← user-owned from here on
        copy.isImported = false
        copy.importedContentHash = ""
        copy.ensureIdentity(authorID: authorID, authorName: authorName)
        context.insert(copy)
        return copy
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
    /// - authorID / authorName: the duplicating device's identity, resolved by
    ///   the caller (`DeviceProfileStore.ensureAuthorID` / `.authorName`). Passed
    ///   in rather than fetched here so this model method stays free of any store
    ///   dependency — `DeviceProfile` lives in a separate schema-split config, and
    ///   inserting one from an arbitrary context is what made this untestable.
    @discardableResult
    static func duplicate(of source: BlasterScene, in context: ModelContext,
                          authorID: String, authorName: String) -> BlasterScene {
        let candidate = availableName(basedOn: "duplicate-of:\(source.name)", in: context)

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
        copy.ensureIdentity(authorID: authorID, authorName: authorName)
        context.insert(copy)
        return copy
    }
}
