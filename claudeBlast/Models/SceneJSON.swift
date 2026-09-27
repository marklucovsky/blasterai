// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneJSON.swift
//  claudeBlast
//
//  On-disk JSON shape for bundled scenes. The SceneImporter reads these,
//  applies the embedded DSL commands against vocabulary.json, and emits
//  materialized BlasterScene + [PageSpec] for SwiftData storage.
//
//  Each entry in a page's `tiles` array is a *command*, not a literal tile
//  struct. Commands run in document order against a working tile list, so
//  later commands can observe and modify earlier ones (e.g. makeLink on a
//  key already added by selectAll converts that tile to a link in place).
//

import Foundation

/// Root of one bundled scene file (e.g. Resources/scenes/core_first.json).
struct SceneJSON: Codable {
    let key: String                 // scene identifier, e.g. "core_first"
    let name: String                // display name, e.g. "Core-First"
    let description: String?
    let homePageKey: String         // must match one of the pages' keys
    let isDefault: Bool
    let pages: [PageJSON]
}

struct PageJSON: Codable {
    let key: String
    let tiles: [PageBuildCommand]
}

/// Sum type of DSL commands applied to a page's working tile list. Each
/// entry in a page's `tiles` array is one command. Encoded with implicit
/// tagging — the present root key (class / keys / link / remove / space)
/// determines the case.
///
/// JSON shapes:
///   {"class": "actions"}                                          // single class
///   {"class": ["food","drinks"], "exclude": ["pizza"], "limit": 8, "orderBy": "name"}
///   {"keys": ["i","me","you"]}                                    // explicit list
///   {"link": "people", "to": "people", "audible": false}          // link tile
///   {"remove": "stop"}                                            // drop a tile
///   {"space": 3}                                                  // three empty cells
///   {"space": true}                                               // one empty cell
enum PageBuildCommand: Codable, Hashable {
    /// `class`: pull every vocabulary tile whose wordClass matches one of
    /// `classes`. Appended as audible (no link). Use exclude/limit/orderBy
    /// to refine. (Named `classSelector` in Swift to avoid the `class`
    /// keyword.)
    case classSelector(classes: [String], exclude: [String], limit: Int?, orderBy: OrderBy)

    /// `keys`: explicit list of vocabulary keys. Each appended as audible
    /// (no link).
    case keys([String])

    /// `link`: add or update a single tile that navigates to a page. If
    /// `key` is already present (e.g. via a prior class/keys command),
    /// update it in place — preserves position. Otherwise append.
    ///
    /// `color` is an optional `TileColorSlot.rawValue` — `"verb"` for a folder
    /// of doing words, `"wayfinding"` for a folder of folders. Absent means
    /// wayfinding, which is what every link was before folders could be
    /// colored. The literal `"auto"` asks `tools/resolve_link_colors.py` to
    /// work the answer out from the destination page and write it back here;
    /// it is an authoring instruction and must not survive into a shipped
    /// scene. See `TileEntry.linkColor`.
    case link(key: String, to: String, audible: Bool, color: String?)

    /// `remove`: remove the tile with this key from the working list, if
    /// present. No-op when the key is absent.
    case remove(String)

    /// `space`: append N deliberate gaps — cells that are drawn empty and do
    /// not respond.
    ///
    /// The app has had spacers since the grid editor shipped (`TileEntry`'s
    /// `<spacer>#…` token, `isEmptyCell`, and the no-filter rule in
    /// `TileGridView`), but a bundled scene had no way to ask for one. So a
    /// board authored in JSON could only be laid out by counting words, and any
    /// alignment it achieved was accidental — add a word anywhere earlier and
    /// every column below it shifts.
    ///
    /// That matters because the grid reflows. A cluster only reads as a block
    /// if it begins at a multiple of the column count, and the only way to
    /// arrange that without spacers is to pad with vocabulary, which spends a
    /// cell on a word nobody chose.
    ///
    /// Each gap gets its own random key, because `TileEntry`'s identity *is*
    /// its key and two identical ones would collide.
    case space(Int)

    enum OrderBy: String, Codable {
        case vocab   // declaration order in vocabulary.json (default)
        case name    // alphabetical by key
        case score   // future: a `score` field on vocab entries
    }

    // MARK: - Codable

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static func k(_ s: String) -> DynamicKey { DynamicKey(stringValue: s)! }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)

        if c.contains(.k("class")) {
            // Value is either a string (single class) or [String] (multi-class).
            let classes: [String]
            if let single = try? c.decode(String.self, forKey: .k("class")) {
                classes = [single]
            } else {
                classes = try c.decode([String].self, forKey: .k("class"))
            }
            let exclude = (try? c.decode([String].self, forKey: .k("exclude"))) ?? []
            let limit = try? c.decode(Int.self, forKey: .k("limit"))
            let orderBy: OrderBy
            if let raw = try? c.decode(String.self, forKey: .k("orderBy")),
               let parsed = OrderBy(rawValue: raw) {
                orderBy = parsed
            } else {
                orderBy = .vocab
            }
            self = .classSelector(classes: classes, exclude: exclude, limit: limit, orderBy: orderBy)
            return
        }

        if c.contains(.k("keys")) {
            let keys = try c.decode([String].self, forKey: .k("keys"))
            self = .keys(keys)
            return
        }

        if c.contains(.k("space")) {
            // `{"space": 3}` for three gaps, or `{"space": true}` for one —
            // the bare form is what an author reaches for when nudging a
            // cluster onto a row boundary by a single cell.
            if let count = try? c.decode(Int.self, forKey: .k("space")) {
                self = .space(max(0, count))
            } else {
                self = .space(1)
            }
            return
        }

        if c.contains(.k("link")) {
            let key = try c.decode(String.self, forKey: .k("link"))
            let to = try c.decode(String.self, forKey: .k("to"))
            let audible = try c.decode(Bool.self, forKey: .k("audible"))
            let color = try? c.decode(String.self, forKey: .k("linkColor"))
            self = .link(key: key, to: to, audible: audible, color: color)
            return
        }

        if c.contains(.k("remove")) {
            let key = try c.decode(String.self, forKey: .k("remove"))
            self = .remove(key)
            return
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unknown PageBuildCommand (no recognized key)"
        ))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case .classSelector(let classes, let exclude, let limit, let orderBy):
            if classes.count == 1 {
                try c.encode(classes[0], forKey: .k("class"))
            } else {
                try c.encode(classes, forKey: .k("class"))
            }
            if !exclude.isEmpty { try c.encode(exclude, forKey: .k("exclude")) }
            if let limit { try c.encode(limit, forKey: .k("limit")) }
            if orderBy != .vocab { try c.encode(orderBy.rawValue, forKey: .k("orderBy")) }
        case .keys(let keys):
            try c.encode(keys, forKey: .k("keys"))
        case .link(let key, let to, let audible, let color):
            try c.encode(key, forKey: .k("link"))
            try c.encode(to, forKey: .k("to"))
            try c.encode(audible, forKey: .k("audible"))
            try c.encodeIfPresent(color, forKey: .k("linkColor"))
        case .remove(let key):
            try c.encode(key, forKey: .k("remove"))
        case .space(let count):
            try c.encode(count, forKey: .k("space"))
        }
    }
}
