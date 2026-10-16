// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageSpec.swift
//  claudeBlast
//
//  Codable inline page + tile types that will replace the PageModel /
//  PageTileModel SwiftData entities. Stored as an array attribute on
//  BlasterScene; no relationships, no cross-scene sharing fragility.
//
//  This is the *materialized* form (post-DSL-expansion). The on-disk
//  JSON shape — which carries DSL commands like {"selectAll": "actions"} —
//  lives in SceneJSON.swift. The SceneImporter (TBD) converts SceneJSON
//  → [PageSpec] at bootstrap time.
//

import Foundation

/// A page within a scene. `key` is scene-scoped — two scenes can both have
/// a page keyed "home" with no global collision.
struct PageSpec: Codable, Hashable, Identifiable {
    var id: String { key }

    /// Scene-scoped identity. **Never changes**, including on rename.
    ///
    /// Far too much points at it for it to be editable: every `TileEntry.link`
    /// aiming here, `BlasterScene.homePageKey`, the page-link tile minted as
    /// `page_<key>`, TileScript navigation steps, `.obf` filenames on export,
    /// and `LoggedUtterance.pageKeys` — which is an immutable historical record
    /// and must never be rewritten to match a later rename. Renaming edits
    /// `displayName` instead, exactly as `BlasterScene` separates `name` from
    /// `systemSceneKey`.
    var key: String

    /// What a caregiver calls this page. **Empty means "derive from the key"**,
    /// which is the state every page starts in.
    ///
    /// Unique keys, non-unique names — deliberately. Two pages may both be
    /// called "Food"; the key keeps them apart, and forbidding it would only
    /// invite "Food " with a trailing space.
    ///
    /// Exists because people name pages before they know what a page is. By the
    /// time a caregiver understands the model well enough to want better names,
    /// the board is full of the guesses they made on day one — and until now
    /// there was no way to change them.
    var displayName: String

    var tiles: [TileEntry]

    init(key: String, displayName: String = "", tiles: [TileEntry]) {
        self.key = key
        self.displayName = displayName
        self.tiles = tiles
    }

    /// The name to show. The single resolution point — no surface should reach
    /// for `key` or `displayName` directly to label a page.
    var title: String {
        displayName.isEmpty ? PageNaming.displayName(key) : displayName
    }

    /// True when the caregiver has named this page rather than inheriting the
    /// key's title-cased form.
    var hasCustomName: Bool { !displayName.isEmpty }

    /// Hand-written for the same reason `TileEntry`'s is: Swift's synthesized
    /// decoder calls `decode` for a non-optional and throws on a missing key, so
    /// a scene file written before rename existed would fail to import.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        tiles = try container.decodeIfPresent([TileEntry].self, forKey: .tiles) ?? []
    }
}

/// Reserved `TileEntry` keys and links. Angle brackets are not legal in a
/// vocabulary key (which is lowercase letters, digits and underscores), so a
/// token can never be mistaken for a word.
enum TileToken {
    /// A link that resolves to the active scene's `homePageKey` at navigation
    /// time, so a page can point Home without hardcoding which page that is.
    static let home = "<home>"

    /// Prefix for a deliberate gap. **Not a bare token**: every spacer carries a
    /// unique suffix.
    ///
    /// Four grid surfaces render tiles with `ForEach(tiles, id: \.key)`, and a
    /// `TileEntry`'s identity *is* its key. Two bare `<spacer>` entries on one
    /// page would be one SwiftUI identity, which misrenders silently rather than
    /// failing — and this file's identity has bitten before (see the note in
    /// `TileGridView` about a press animation finishing on the wrong page).
    static let spacerPrefix = "<spacer>#"

    /// A fresh spacer key. Random rather than positional so it survives reorder.
    static func newSpacerKey() -> String {
        spacerPrefix + UUID().uuidString.prefix(8).lowercased()
    }
}

/// A single tile placement on a page. The vocabulary key identifies the
/// underlying TileModel (which still holds display name + wordClass).
///
/// `link`:
///   - empty string → terminal tile (audible only)
///   - a page key → navigate to that page within the same scene
///   - `TileToken.home` → magic link; resolves to the active scene's
///     homePageKey at navigation time
struct TileEntry: Codable, Hashable, Identifiable {
    var id: String { key }
    var key: String
    var link: String
    var isAudible: Bool

    /// Present on the board but not available: the cell is drawn empty and does
    /// not respond, and the word behind it is untouched.
    ///
    /// ## Conceal is not hide
    ///
    /// `TileModel.isHiddenFromChild` (retired / needs review) is the *word*-level
    /// safety hide: the tile is filtered out of the grid entirely, everywhere,
    /// and the board reflows around the gap. This is the opposite, and it is
    /// per-*placement*: the cell stays exactly where it is, and the same word can
    /// be concealed on the school board and available at home.
    ///
    /// ## Why hold the cell rather than remove the tile
    ///
    /// Motor planning — the same argument that pins Home to cell 0. Removing a
    /// word reflows the board and moves every other word with it, so a child who
    /// had learned where `want` lives has to find it again. Concealing moves
    /// nothing. That makes conceal the normal way to take a word off a board and
    /// deletion the rare one, and it is what makes "grow the board by revealing"
    /// a workable teaching method rather than a rebuild every week.
    var isConcealed: Bool

    /// For a link tile, the `TileColorSlot.rawValue` this folder is colored as —
    /// `"verb"` for a page of doing words, `"wayfinding"` for a page of folders.
    /// Nil on a word tile, and nil on any link authored before folders could
    /// carry a color, which draws as wayfinding.
    ///
    /// ## Why a slot and not a hex
    ///
    /// Storing `"#4CB859"` would freeze the folder at one green while the child's
    /// palette moved underneath it. Storing `verb` means the folder follows
    /// whatever that child's palette says doing words look like — including on
    /// the bundled Core-First board, whose *data* is immutable but whose colors
    /// still come from the per-child palette layered over it.
    ///
    /// ## Why it is resolved here rather than computed when drawn
    ///
    /// The value is decided once, by whoever authored the link, and written
    /// down. Recomputing it at render would mean a folder changing color because
    /// a caregiver added three nouns to the page behind it — the same motor
    /// planning argument that pins Home to cell 0 and that makes `isConcealed`
    /// hold the cell. Colors are as much an invariant as positions.
    ///
    /// `"auto"` is an *authoring* instruction, never a stored value:
    /// `tools/resolve_link_colors.py` rewrites it to a concrete slot, and
    /// `--check` fails the build if any survives into a shipped scene.
    var linkColor: String?

    /// Whether `linkColor` was worked out from the destination or chosen by a
    /// person.
    ///
    /// **Why the bit is needed at all.** A folder's color is resolved once and
    /// written down, never recomputed when drawn — see `linkColor`. But a page's
    /// contents do change, and when a caregiver turns a folder of nouns into a
    /// folder of verbs, a color that was *derived* should follow and a color
    /// that was *chosen* must not. Without this flag the two are
    /// indistinguishable after the fact, because a manual pick overwrites the
    /// automatic answer and leaves nothing behind to compare against.
    ///
    /// Defaults to true, so a link that predates the flag re-resolves rather
    /// than freezing at whatever it happens to hold.
    var linkColorIsAuto: Bool

    /// The board level this placement first appears at. 0 means always shown —
    /// every placement before levels existed, and every placement on a scene
    /// that does not use them.
    ///
    /// Graded reveal: a scene declares levels (`BlasterScene.revealLevelCount`)
    /// and a current level, and a placement whose level is above the current
    /// one draws exactly as a concealed cell does — it keeps its place, so the
    /// board grows by revealing rather than reflowing. Per placement, like
    /// `isConcealed`: `eat` can be an L1 word on Home and an L4 word on Food.
    ///
    /// `isConcealed` stays the caregiver's override and wins at every level.
    var revealLevel: Int

    init(key: String, link: String = "", isAudible: Bool = true,
         isConcealed: Bool = false, linkColor: String? = nil,
         linkColorIsAuto: Bool = true, revealLevel: Int = 0) {
        self.key = key
        self.link = link
        self.isAudible = isAudible
        self.isConcealed = isConcealed
        self.linkColor = linkColor
        self.linkColorIsAuto = linkColorIsAuto
        self.revealLevel = revealLevel
    }

    /// Hidden by the board's level: above `level` and not always-shown. Nil
    /// `level` means the scene has no levels, so nothing is level-hidden.
    func isAboveLevel(_ level: Int?) -> Bool {
        guard let level, revealLevel > 0 else { return false }
        return revealLevel > level
    }

    /// A deliberate gap: real estate with no word behind it.
    static func spacer() -> TileEntry {
        TileEntry(key: TileToken.newSpacerKey(), link: "", isAudible: false)
    }

    /// True for a gap. Prefix-matched against a reserved token, **never** "this
    /// key did not resolve to a tile".
    ///
    /// That distinction is load-bearing. `docs/s4-cleanup.md` §9 records a page
    /// that looked populated in the editor and drew empty on the board, because
    /// an export bug dropped the words its tiles named — unresolvable keys are
    /// the signature of corruption. If unresolvable silently meant "spacer", we
    /// would destroy the only signal that separates a broken board from an
    /// intentional one.
    var isSpacer: Bool { key.hasPrefix(TileToken.spacerPrefix) }

    /// Draws as an empty cell on the child's board, and does not respond to a
    /// tap. Both kinds still consume their real estate — that is the point.
    var isEmptyCell: Bool { isConcealed || isSpacer }

    // MARK: - Codable

    /// Hand-written so a missing `isConcealed` decodes as `false`.
    ///
    /// Swift's synthesized decoder calls `decode` (not `decodeIfPresent`) for a
    /// non-optional property and throws on a missing key — a default value does
    /// not save it. Two real sources predate this field: scene blobs already
    /// written to `BlasterScene.pagesData`, and **scene files shared from another
    /// device**, which is the one that would fail in a stranger's hands rather
    /// than in a migration we control.
    ///
    /// **Every new field has to be added here by hand, and forgetting is
    /// silent.** `linkColor` was added to the struct, the scene DSL and the
    /// materializer, and still arrived nil on every board: `BlasterScene.pages`
    /// round-trips through `pagesData`, so this decoder is the only way a value
    /// survives being stored. Nothing warned — the field simply decoded as nil
    /// and every folder drew wayfinding blue, which looks exactly like a feature
    /// nobody had turned on yet. `committedColorsMatchSwift` is what caught it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        isAudible = try container.decodeIfPresent(Bool.self, forKey: .isAudible) ?? true
        isConcealed = try container.decodeIfPresent(Bool.self, forKey: .isConcealed) ?? false
        linkColor = try container.decodeIfPresent(String.self, forKey: .linkColor)
        linkColorIsAuto = try container.decodeIfPresent(Bool.self, forKey: .linkColorIsAuto) ?? true
        revealLevel = try container.decodeIfPresent(Int.self, forKey: .revealLevel) ?? 0
    }

    /// Declared because both halves of Codable are hand-written, which stops
    /// Swift synthesizing it. A new field needs a case here too.
    private enum CodingKeys: String, CodingKey {
        case key, link, isAudible, isConcealed, linkColor, linkColorIsAuto, revealLevel
    }

    /// Hand-written only to leave `revealLevel` out when it is 0.
    ///
    /// Scenes store these bytes, and `BlasterScene.contentHash` hashes them. A
    /// synthesized encoder would add `"revealLevel":0` to every placement of
    /// every scene, moving every hash, and every imported scene would start
    /// reading as "modified locally" against its stored baseline. Every other
    /// key is written exactly as the synthesized encoder wrote it, in the same
    /// order — `LegacyTileEntryEncodingTests` pins that byte for byte.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(link, forKey: .link)
        try container.encode(isAudible, forKey: .isAudible)
        try container.encode(isConcealed, forKey: .isConcealed)
        try container.encodeIfPresent(linkColor, forKey: .linkColor)
        try container.encode(linkColorIsAuto, forKey: .linkColorIsAuto)
        if revealLevel != 0 { try container.encode(revealLevel, forKey: .revealLevel) }
    }
}
