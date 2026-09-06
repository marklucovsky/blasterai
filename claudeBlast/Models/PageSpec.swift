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

    init(key: String, link: String = "", isAudible: Bool = true,
         isConcealed: Bool = false) {
        self.key = key
        self.link = link
        self.isAudible = isAudible
        self.isConcealed = isConcealed
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        isAudible = try container.decodeIfPresent(Bool.self, forKey: .isAudible) ?? true
        isConcealed = try container.decodeIfPresent(Bool.self, forKey: .isConcealed) ?? false
    }
}
