// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BlasterScene.swift
//  claudeBlast
//

import SwiftData
import Foundation
import CryptoKit
import os

@Model
final class BlasterScene {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var homePageKey: String = "home"
    var isDefault: Bool = false
    var isActive: Bool = false
    var isImported: Bool = false
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

    /// The grid this scene was designed for — `DesignedLayout.rawValue`, e.g.
    /// `"ipad-10x6"`. Empty when undeclared.
    ///
    /// A non-optional String with an empty sentinel, per the schema rules in
    /// `SchemaVersions.swift`: additive, defaulted, and written for every row so
    /// the CloudKit field exists.
    var designedFor: String = ""

    /// The declared grid, typed. Nil when undeclared or unrecognised.
    var designedLayout: DesignedLayout? { DesignedLayout(rawValue: designedFor) }

    // MARK: - Templates

    /// Other scenes can be built on this one (`TemplateChain`): its pages and
    /// navigation bar are theirs to link to and draw, as BlasterAI 60's are
    /// for every scene. BlasterAI 60 is the template that ships with the app;
    /// this marks a caregiver's own. Defaulted Bool, per `SchemaVersions`.
    var isTemplate: Bool = false

    /// The `sceneID` of the template this scene is built on. Empty means
    /// BlasterAI 60 — every scene before templates. A template that is gone
    /// (deleted, not yet synced) falls back to BlasterAI 60 too, so a stale id
    /// is never a broken board. Defaulted String, per `SchemaVersions`.
    var templateID: String = ""

    // MARK: - Levels (graded reveal)

    /// How many levels the board declares; 0 means it has none. Authored, like
    /// `designedFor`: it joins `contentHash` only when set.
    var revealLevelCount: Int = 0

    /// The level the board is at — 1…`revealLevelCount` whenever the board has
    /// levels. Synced, so the child's iPad and a parent's phone agree; copied by
    /// duplicate; carried by a shared file, which opens at it.
    ///
    /// There is no separate "default": a board is always *at* a level, and
    /// whoever moves it moves it. Every writer goes through `setRevealLevel` or
    /// `setRevealLevelCount`, which keep it in range.
    ///
    /// State, not content: it is deliberately **not** in `contentHash`, so
    /// stepping a board up or down never reads as editing it, and it is the one
    /// caregiver-owned value a system scene carries — `updateSystemScene`
    /// preserves it across bundle updates.
    var revealLevel: Int = 0

    /// Most levels a board may declare.
    static let maxRevealLevels = 10

    /// The level to draw at, or nil when the board has no levels. A stored level
    /// out of range — 0 from a scene written before levels were declared —
    /// reads as the top, which hides nothing.
    var effectiveRevealLevel: Int? {
        guard revealLevelCount > 0 else { return nil }
        return (1...revealLevelCount).contains(revealLevel) ? revealLevel : revealLevelCount
    }

    /// Move the board to `level`, clamped to the levels it has.
    func setRevealLevel(_ level: Int) {
        guard revealLevelCount > 0 else { return }
        revealLevel = min(max(level, 1), revealLevelCount)
    }

    /// Stable fingerprint of the scene's user-visible content (name + home page +
    /// pages, and the designed-for grid when one is declared). Used only to
    /// detect local edits vs. the imported baseline.
    ///
    /// `designedFor` joins the hash only when set, so every scene that predates
    /// it keeps the hash it had — otherwise each one would start reading as
    /// "modified locally" against its stored baseline.
    var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(name.utf8))
        hasher.update(data: Data(homePageKey.utf8))
        hasher.update(data: pagesData)
        if !designedFor.isEmpty { hasher.update(data: Data(designedFor.utf8)) }
        // Same rule as designedFor: absent unless declared, so older scenes keep
        // their hash. The current level is state and never joins.
        if revealLevelCount > 0 {
            hasher.update(data: Data("levels:\(revealLevelCount)".utf8))
        }
        // Templates, the same way: only when set.
        if !templateID.isEmpty { hasher.update(data: Data("template:\(templateID)".utf8)) }
        if isTemplate { hasher.update(data: Data("isTemplate".utf8)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Provenance to show in lists: the author's name, else the local tag, else "".
    var authorDisplay: String { authorName.isEmpty ? receivedLabel : authorName }

    /// How first-party (BlasterAI-shipped) content is credited in the UI.
    static let firstPartyAuthorDisplay = "BlasterAI"

    // MARK: - System ownership (immutability)

    /// Marker appended to the name of a bundle-backed scene we own.
    static let systemSuppliedSuffix = " - System Supplied"

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
    /// "BlasterAI 60 - System Supplied" is named "BlasterAI 60 (1)" rather than
    /// carrying the marker along.
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

    /// The last decode of `pagesData`, valid while the bytes still match.
    ///
    /// Keyed by the bytes rather than invalidated in the setter, because the
    /// setter is not the only writer: a CloudKit import replaces `pagesData`
    /// underneath us. Comparing ~60 KB is a memcmp, far below a JSON decode.
    ///
    /// A class, so filling it from inside a getter is not a model change.
    /// Writing an observed property during a view's body would schedule another
    /// render; mutating the box's contents does not.
    @Transient private var decodedPages = DecodedPagesCache()

    /// Inline page list — replaces the prior PageModel relationship. Pages are
    /// scene-scoped (their `key` is unique only within this scene). No cross-scene
    /// sharing, no SwiftData @Relationship inverse, no deletion-rule fragility.
    ///
    /// Reads are served from `decodedPages` while the bytes are unchanged. Every
    /// read used to decode the whole scene — ~1 ms for a full board — and
    /// editors read this per cell and per binding access: one Add Word cost
    /// thousands of decodes on an iPad mini.
    ///
    /// The scene's own row 1 (`ownRow`) is stored among them and left out
    /// here: it is not a page anything opens, lists or exports as one.
    var pages: [PageSpec] {
        get { decodedAll().pages }
        set {
            write(newValue.filter { $0.key != Self.rowPageKey }, row: ownRow)
            adoptHomePageIfNeeded(newValue)
        }
    }

    /// Key of the stored row page. Angle brackets keep it clear of every key
    /// a page can be given.
    static let rowPageKey = "<row>"

    /// The scene's own system row, drawn across every page in place of
    /// BlasterAI 60's (`BoardChrome.row(for:)`); nil when the scene inherits
    /// that one. Kept in `pagesData` as a page with a reserved key, so it
    /// syncs with the pages and needs no schema change. A copy of BlasterAI
    /// 60's row, made when a caregiver makes the row their own
    /// (`makeRowOwn`) — copy-on-write, like a page (`PageSpec.shadows`).
    var ownRow: PageSpec? {
        get { decodedAll().row }
        set {
            var row = newValue
            row?.key = Self.rowPageKey
            write(pages, row: row)
        }
    }

    private func decodedAll() -> (pages: [PageSpec], row: PageSpec?) {
        let data = pagesData
        guard !data.isEmpty else { return ([], nil) }
        if let hit = decodedPages.pages(for: data) { return (hit, decodedPages.row) }
        let state = PerfSignposts.signposter.beginInterval(
            "pages.decode", "\(data.count) bytes")
        defer { PerfSignposts.signposter.endInterval("pages.decode", state) }
        let all = (try? JSONDecoder().decode([PageSpec].self, from: data)) ?? []
        let pages = all.filter { $0.key != Self.rowPageKey }
        let row = all.first { $0.key == Self.rowPageKey }
        decodedPages.store(pages, row: row, for: data)
        return (pages, row)
    }

    private func write(_ pages: [PageSpec], row: PageSpec?) {
        pagesData = (try? JSONEncoder().encode(pages + (row.map { [$0] } ?? []))) ?? Data()
        lastModified = .now
    }

    /// The pages as a child at `level` sees them: placements above the level
    /// come back concealed, so every consumer that already draws a concealed
    /// cell as an empty one in place handles levels with no change. Nil `level`
    /// is the identity.
    ///
    /// Editors read `pages`; anything drawing the child's board reads this.
    /// Cached with the decode, so it costs nothing per render.
    func pages(atLevel level: Int?) -> [PageSpec] {
        let all = pages
        guard let level else { return all }
        let data = pagesData
        if let hit = decodedPages.projection(for: data, level: level) { return hit }
        let state = PerfSignposts.signposter.beginInterval("pages.project", "L\(level)")
        defer { PerfSignposts.signposter.endInterval("pages.project", state) }
        let projected = Self.project(all, atLevel: level)
        decodedPages.storeProjection(projected, for: data, level: level)
        return projected
    }

    /// The board at its current level.
    var visiblePages: [PageSpec] { pages(atLevel: effectiveRevealLevel) }

    /// Change how many levels the board has, as its author.
    ///
    /// Turning levels on starts the board at the top, so nothing disappears
    /// until a caregiver steps down. A lowered top brings the board's level and
    /// any placement above it down to it — otherwise a word would sit above
    /// every level the board can reach and never show again, lost with nothing
    /// on screen to say where. Turning levels off (0) leaves placement levels
    /// alone; they are ignored until levels come back.
    func setRevealLevelCount(_ count: Int) {
        let count = min(max(count, 0), Self.maxRevealLevels)
        let wasOn = revealLevelCount > 0
        revealLevelCount = count
        guard count > 0 else { return }
        if !wasOn || !(1...count).contains(revealLevel) {
            revealLevel = wasOn ? min(max(revealLevel, 1), count) : count
        }
        var all = pages
        var changed = false
        for p in all.indices {
            for t in all[p].tiles.indices where all[p].tiles[t].revealLevel > count {
                all[p].tiles[t].revealLevel = count
                changed = true
            }
        }
        if changed { pages = all }
    }

    /// Take an incoming level count — a bundle update, or a re-import of a
    /// shared scene — while keeping the caregiver's level. The count is content
    /// and follows the source; the level is the caregiver's, kept, and brought
    /// down only when the source no longer reaches it. A board gaining levels
    /// for the first time starts at `initial` (the source's own level), or the
    /// top when the source has none.
    func applyLevelDeclaration(count: Int, initial: Int?) {
        let wasOn = revealLevelCount > 0
        revealLevelCount = count
        guard count > 0 else { revealLevel = 0; return }
        let start = wasOn && revealLevel > 0 ? revealLevel : (initial ?? count)
        revealLevel = min(max(start, 1), count)
    }

    static func project(_ pages: [PageSpec], atLevel level: Int?) -> [PageSpec] {
        guard let level else { return pages }
        return pages.map { page in
            var page = page
            page.tiles = page.tiles.map { entry in
                guard entry.isAboveLevel(level) else { return entry }
                var hidden = entry
                hidden.isConcealed = true
                return hidden
            }
            return page
        }
    }

    /// Placements a child at `level` can actually press — words and folders,
    /// not gaps. CoughDrop shows the same count beside its level control.
    func visibleTileCount(atLevel level: Int?) -> Int {
        pages(atLevel: level).reduce(0) { $0 + $1.tiles.count { !$0.isEmptyCell } }
    }

    /// Keep `homePageKey` pointing at a page that exists.
    ///
    /// A scene whose home page names nothing renders no board — and since Admin
    /// is reached by long-pressing Home, and Home lives on the board, that scene
    /// cannot be edited or deactivated from the device it is active on. The only
    /// exit was delete-and-reinstall.
    ///
    /// Enforced here rather than at the call sites because this setter is the one
    /// choke point every page mutation passes through: creation, adding the first
    /// page, deleting the page that happened to be home, import, materialisation.
    /// A guard per site is a guard someone forgets to add to the eleventh.
    ///
    /// The first page wins when there is no valid home. Arbitrary, and better
    /// than the alternative by a wide margin: a scene opening on the wrong page
    /// is a nuisance a caregiver can fix in seconds, and one opening on no page
    /// is a device that needs wiping.
    private func adoptHomePageIfNeeded(_ pages: [PageSpec]) {
        guard let first = pages.first else { return }
        if !pages.contains(where: { $0.key == homePageKey }) {
            homePageKey = first.key
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

    /// A page the editors can open: one of the scene's pages, or its own row
    /// 1 under `rowPageKey`.
    func editablePage(_ key: String) -> PageSpec? {
        key == Self.rowPageKey ? ownRow : page(withKey: key)
    }

    /// Change the editable page `key` in place — a page, or the scene's own
    /// row. One write, so an editor's change is one undoable step.
    func updatePage(_ key: String, _ change: (inout PageSpec) -> Void) {
        if key == Self.rowPageKey {
            guard var row = ownRow else { return }
            change(&row)
            ownRow = row
            return
        }
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == key }) else { return }
        change(&pages[idx])
        self.pages = pages
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
    ///
    /// The last line of defence for the home-page invariant. The `pages` setter
    /// normally holds it, but a scene can arrive with `homePageKey` written
    /// *after* its pages — an importer assigning fields in field order will do
    /// exactly that — and the moment of activation is the one that matters:
    /// this is where an unreachable home page becomes a board that will not
    /// draw.
    /// Make this the child's board.
    ///
    /// Returns what it had to do to get there — repairs applied, warnings worth
    /// showing — and throws `SceneActivation.Refusal` when the scene genuinely
    /// cannot be shown. **The result is `@discardableResult` but the message is
    /// not decorative:** a scene that quietly repaired itself is the state
    /// `docs/s4-cleanup.md` §9 was written about, where a caregiver's board
    /// changed under them with no explanation.
    ///
    /// Validation happens *before* anything is mutated, so a refused activation
    /// leaves the previously active scene alone rather than deactivating it and
    /// then failing — which would be a second way to end up with no board.
    @discardableResult
    func activate(context: ModelContext) throws -> SceneActivation.Outcome {
        let vocabulary = Set(
            ((try? context.fetch(FetchDescriptor<TileModel>())) ?? []).map(\.key))
        let outcome = try SceneActivation.check(self, vocabulary: vocabulary)

        let allScenes = try context.fetch(FetchDescriptor<BlasterScene>())
        for scene in allScenes where scene.isActive {
            scene.isActive = false
        }
        for repair in outcome.repairs {
            switch repair {
            case .adoptedHomePage(let key): homePageKey = key
            }
        }
        self.isActive = true
        return outcome
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

    // MARK: - Copy names

    /// The name a copy is numbered under: `name` with any copy number and any
    /// earlier copy marker removed. "BlasterAI 60 (3)" → "BlasterAI 60".
    ///
    /// Also reads the names copies used to get — "X - My Copy" from Make My
    /// Copy, "duplicate-of:X-2" from Duplicate — so copying a scene made by an
    /// earlier build joins the same numbering instead of stacking markers.
    static func copyRoot(of name: String) -> String {
        var root = name
        if root.hasSuffix(systemSuppliedSuffix) { root = String(root.dropLast(systemSuppliedSuffix.count)) }
        if let range = root.range(of: #" \(\d+\)$"#, options: .regularExpression) {
            root.removeSubrange(range)
        }
        if root.hasPrefix(legacyDuplicatePrefix) {
            root = String(root.dropFirst(legacyDuplicatePrefix.count))
            // Its collision suffix, "-2", only ever followed this prefix.
            if let range = root.range(of: #"-\d+$"#, options: .regularExpression) { root.removeSubrange(range) }
        }
        if root.hasSuffix(legacyMyCopySuffix) { root = String(root.dropLast(legacyMyCopySuffix.count)) }
        return root
    }

    private static let legacyMyCopySuffix = " - My Copy"
    private static let legacyDuplicatePrefix = "duplicate-of:"

    /// "BlasterAI 60 (n)", one past the highest number in use under the same
    /// root — so a copy of "(1)", with "(2)" already taken, is "(3)". Gaps are
    /// never filled, but deleting the highest copy frees its number; no
    /// counter is stored, because a new synced field is a CloudKit deploy.
    ///
    /// The name says which board it is, not where it came from: the lineage
    /// is the "Copied from" line (`copyProvenance`), which stays true when
    /// someone renames a copy, where a lineage spelled into the name would not.
    static func copyName(of source: BlasterScene, in context: ModelContext) -> String {
        let root = copyRoot(of: source.name)
        let names = (try? context.fetch(FetchDescriptor<BlasterScene>()))?.map(\.name) ?? []
        let prefix = root + " ("
        let used = names.compactMap { name -> Int? in
            guard name.hasPrefix(prefix), name.hasSuffix(")") else { return nil }
            return Int(name.dropFirst(prefix.count).dropLast())
        }
        return "\(root) (\((used.max() ?? 0) + 1))"
    }

    /// What a copy's row says about where it came from.
    static func copyProvenance(of source: BlasterScene) -> String {
        "Copied from \(source.name)"
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
    ///
    /// A copy of BlasterAI 60 is sparse — see `copiedPages(of:alsoShadowing:)`.
    static func cloneForEditing(_ source: BlasterScene, in context: ModelContext,
                                authorID: String, authorName: String,
                                alsoShadowing: String? = nil) -> BlasterScene {
        let copy = BlasterScene(
            name: copyName(of: source, in: context),
            descriptionText: copyProvenance(of: source),
            homePageKey: source.homePageKey,
            isDefault: false,
            isActive: false
        )
        copy.pages = copiedPages(of: source, alsoShadowing: alsoShadowing)
        copy.ownRow = source.ownRow
        copy.designedFor = source.designedFor
        copy.revealLevelCount = source.revealLevelCount
        copy.revealLevel = source.revealLevel
        copy.systemSceneKey = ""            // ← user-owned from here on
        copy.isImported = false
        copy.importedContentHash = ""
        copy.ensureIdentity(authorID: authorID, authorName: authorName)
        context.insert(copy)
        return copy
    }

    // MARK: - Copy-on-write

    /// The pages a copy of `source` starts with.
    ///
    /// Any scene but BlasterAI 60 copies whole. A copy of BlasterAI 60 is
    /// sparse: its Home, plus the page being edited when the copy was made
    /// for Edit This Page. Every other page is still BlasterAI 60's, reached
    /// through `<system>:` links, and keeps following its updates until a
    /// caregiver edits it (`shadowSystemPage`). Duplicate and Make a Copy both
    /// come here, so they make the same copy. Copied whole, the pages were
    /// unreachable: row 1 and every folder open BlasterAI 60's own.
    static func copiedPages(of source: BlasterScene, alsoShadowing: String? = nil) -> [PageSpec] {
        guard source.isDefault else { return source.pages }
        let systemHome = source.homePageKey
        guard var home = source.page(withKey: systemHome) else { return source.pages }
        home.tiles = home.tiles.map { linkedIntoSystem($0, systemHomePageKey: systemHome) }
        var pages = [home]
        if let key = alsoShadowing, key != systemHome, let page = source.page(withKey: key) {
            pages.append(shadow(of: page, systemHomePageKey: systemHome, key: key))
        }
        return pages
    }

    /// `entry` as it reads once its page leaves BlasterAI 60: a link to one of
    /// the core board's pages names it as such, and one to its Home is Home.
    static func linkedIntoSystem(_ entry: TileEntry, systemHomePageKey: String) -> TileEntry {
        let link = entry.link
        guard !link.isEmpty, link != TileToken.home,
              TileToken.systemPageKey(link) == nil,
              TileToken.scenePageKey(link) == nil else { return entry }
        var out = entry
        out.link = link == systemHomePageKey ? TileToken.home : TileToken.systemLink(to: link)
        return out
    }

    /// The scene's own copy of BlasterAI 60's `page`, standing in for it.
    static func shadow(of page: PageSpec, systemHomePageKey: String, key: String) -> PageSpec {
        var copy = page
        copy.key = key
        copy.shadows = page.key
        copy.tiles = page.tiles.map { linkedIntoSystem($0, systemHomePageKey: systemHomePageKey) }
        return copy
    }

    /// The scene's page standing in for BlasterAI 60's `systemKey`, if any.
    func shadowPage(for systemKey: String) -> PageSpec? {
        pages.first { $0.shadows == systemKey }
    }

    /// The BlasterAI 60 pages this scene has its own copy of.
    var shadowedSystemKeys: Set<String> {
        Set(pages.compactMap { $0.isShadow ? $0.shadows : nil })
    }

    /// Copy BlasterAI 60's `page`, or a template's (`TemplateChain.pages`),
    /// into this scene to stand in for it, and
    /// return the copy's key. Copy-on-write: called when a caregiver edits a
    /// core-board page from this scene. A page already copied is returned as
    /// it is. The copy takes the system key when the scene has no page by
    /// that name, else the next free `key_2`, `key_3`.
    @discardableResult
    func shadowSystemPage(_ page: PageSpec, systemHomePageKey: String) -> String {
        if let existing = shadowPage(for: page.key) { return existing.key }
        var pages = self.pages
        let taken = Set(pages.map(\.key))
        // A template's page (`template:random`) is copied as `random`.
        let base = TileToken.bareKey(page.key)
        var key = base
        var n = 2
        while taken.contains(key) { key = "\(base)_\(n)"; n += 1 }
        pages.append(Self.shadow(of: page, systemHomePageKey: systemHomePageKey, key: key))
        self.pages = pages
        return key
    }

    // MARK: - Duplicate

    /// Create a peer copy of `source`. The new scene is inserted into `context`
    /// and returned.
    ///
    /// Conventions:
    /// - name: the next copy number under the source's root, `copyName`.
    /// - description: "Copied from {source.name}", `copyProvenance` — so the
    ///   lineage survives the source being renamed or deleted later.
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
        let copy = BlasterScene(
            name: copyName(of: source, in: context),
            descriptionText: copyProvenance(of: source),
            homePageKey: source.homePageKey,
            isDefault: false,
            isActive: false
        )
        copy.pages = copiedPages(of: source)
        copy.ownRow = source.ownRow
        copy.designedFor = source.designedFor
        copy.revealLevelCount = source.revealLevelCount
        copy.revealLevel = source.revealLevel
        // A duplicate is a new, locally-owned scene: give it a fresh identity
        // under this device's author id (sceneID starts empty → ensureIdentity
        // mints a new one from the duplicate's name).
        copy.ensureIdentity(authorID: authorID, authorName: authorName)
        context.insert(copy)
        return copy
    }
}

/// `BlasterScene.pages`' decode cache, plus the level projection over it. See
/// `decodedPages`.
final class DecodedPagesCache {
    private var data: Data?
    private var pages: [PageSpec] = []
    private(set) var row: PageSpec?
    private var projectionData: Data?
    private var projectionLevel: Int?
    private var projected: [PageSpec] = []

    func pages(for data: Data) -> [PageSpec]? {
        self.data == data ? pages : nil
    }

    func store(_ pages: [PageSpec], row: PageSpec?, for data: Data) {
        self.data = data
        self.pages = pages
        self.row = row
    }

    func projection(for data: Data, level: Int) -> [PageSpec]? {
        projectionData == data && projectionLevel == level ? projected : nil
    }

    func storeProjection(_ pages: [PageSpec], for data: Data, level: Int) {
        projectionData = data
        projectionLevel = level
        projected = pages
    }
}
