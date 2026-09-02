// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OBFModels.swift
//  claudeBlast
//
//  Open Board Format — the interchange format the AAC world already speaks.
//  https://www.openboardformat.org
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A single board. Declared but not offered as an export destination: a bare
    /// `.obf` references images it does not carry, so ours would arrive as a
    /// board of broken pictures. `.obz` is what we ship.
    static let openBoard = UTType(exportedAs: "org.openboardformat.obf", conformingTo: .json)
    /// A zipped board set with its images inside.
    static let openBoardZip = UTType(exportedAs: "org.openboardformat.obz", conformingTo: .archive)
}

enum OBFFormat {
    /// The format string every OBF document must carry. 0.1 is the current
    /// published revision.
    static let version = "open-board-0.1"
    static let boardExtension = "obf"
    static let packageExtension = "obz"

    /// Namespace for our own fields.
    ///
    /// OBF permits vendor extensions on any object as long as they are prefixed
    /// `ext_<vendor>_`. Everything of ours that OBF has no home for goes here
    /// rather than being dropped — a board that round-trips through another app
    /// and back should not arrive stripped of its own provenance.
    static let extensionPrefix = "ext_blasterai_"
}

// MARK: - Board

/// One board — a page, in our terms.
struct OBFBoard: Codable {
    var format: String = OBFFormat.version
    /// Stable within the package. We use the page key.
    let id: String
    /// BCP-47. Fixed at `en` until localisation ships; the field is required.
    var locale: String = "en"
    let name: String
    var description_html: String?
    var buttons: [OBFButton]
    var grid: OBFGrid
    var images: [OBFImage]
    var sounds: [OBFSound] = []

    // Ours, namespaced.
    var ext_blasterai_scene_id: String?
    var ext_blasterai_page_key: String?
}

/// OBF lays buttons out on a fixed grid and addresses them by id, with `null`
/// for an empty cell. Our boards reflow to whatever device they are on, so the
/// grid written here is a rendering *choice* — see `docs/obf-interop.md`.
struct OBFGrid: Codable {
    let rows: Int
    let columns: Int
    /// `rows` arrays of `columns` entries; nil is an empty cell.
    let order: [[String?]]
}

struct OBFButton: Codable {
    let id: String
    let label: String
    var image_id: String?
    /// What the button says when pressed. Omitted for a navigation button, which
    /// travels rather than speaks.
    var vocalization: String?
    /// `rgb(r, g, b)` — OBF's colour syntax, not hex.
    var background_color: String?
    var border_color: String?
    /// Set on a button that opens another board.
    var load_board: OBFLoadBoard?

    // Ours, namespaced.
    var ext_blasterai_word_class: String?
    var ext_blasterai_tile_key: String?
}

struct OBFLoadBoard: Codable {
    let id: String
    /// Path inside the `.obz`, relative to the package root.
    let path: String
    var name: String?
}

struct OBFImage: Codable {
    let id: String
    /// Path inside the `.obz`. Mutually exclusive with `data` and `url`; we
    /// always package the file rather than inline base64, because an `.obz`
    /// holding 500 data URIs is far larger than the same images as files.
    var path: String?
    var width: Int?
    var height: Int?
    let content_type: String
    var license: OBFLicense?
}

struct OBFSound: Codable {
    let id: String
}

/// Travels inside every exported file, so it has to be true.
///
/// Bundled art is the project's own and reports Apache-2.0. A word the caregiver
/// generated on their own OpenAI key is **theirs** under OpenAI's terms — so it
/// is attributed to them and asserts no licence, because that is not ours to
/// grant on their behalf in a file they may be sending to a stranger.
struct OBFLicense: Codable {
    let type: String
    var copyright_notice_url: String?
    var author_name: String?
    var author_url: String?
    var source_url: String?

    static let projectURL = "https://blasterai.app"
    static let apacheURL = "https://www.apache.org/licenses/LICENSE-2.0"

    static let firstParty = OBFLicense(
        type: "Apache-2.0",
        copyright_notice_url: apacheURL,
        author_name: "BlasterAI",
        author_url: projectURL,
        source_url: projectURL)

    /// Caregiver-generated art: say who made it, grant nothing.
    static func caregiver(author: String) -> OBFLicense {
        OBFLicense(type: "private",
                   copyright_notice_url: nil,
                   author_name: author.isEmpty ? "Unknown" : author,
                   author_url: nil,
                   source_url: projectURL)
    }
}

// MARK: - Package

/// `manifest.json` at the root of an `.obz`.
///
/// ## Why this encodes by hand
///
/// `root` is the spec's answer to "which board opens first", and a conforming
/// reader honours it. **Cboard does not** — verified 2026-09-02 against a real
/// export whose `root` correctly named `boards/farm.obf`, and which still opened
/// on `body_health`. It takes the first board it encounters instead.
///
/// A JSON object has no defined key order, so nothing *guarantees* which board
/// that is. But a reader taking "the first" will take whichever we write first,
/// and `JSONEncoder.sortedKeys` was writing them alphabetically — which is how a
/// page called `body_health` beat the actual home page.
///
/// So the boards map is written with the root first. Readers that honour `root`
/// are unaffected; readers that don't now land somewhere sensible.
struct OBFManifest {
    var format: String = OBFFormat.version
    /// Path of the board a reader should open first.
    let root: String
    /// Board ids in the order they should be written — root first.
    let boardOrder: [String]
    /// `{id: path}`
    let boards: [String: String]
    let images: [String: String]

    /// Serialized by hand, because key order is the point.
    ///
    /// `JSONEncoder` gives no ordering guarantee for a keyed container — it
    /// builds an unordered dictionary internally, so a custom `encode(to:)` that
    /// writes the root first still comes out in whatever order the encoder
    /// chooses. The only way to control it is to write the JSON.
    func jsonData() throws -> Data {
        var ids = boardOrder.filter { boards[$0] != nil }
        ids += boards.keys.filter { !ids.contains($0) }.sorted()

        var out = "{\n"
        out += "  \"format\": \(Self.quote(format)),\n"
        out += "  \"root\": \(Self.quote(root)),\n"
        out += "  \"paths\": {\n"
        out += "    \"boards\": {\n"
        out += ids.compactMap { id in
            boards[id].map { "      \(Self.quote(id)): \(Self.quote($0))" }
        }.joined(separator: ",\n")
        out += "\n    },\n"
        out += "    \"images\": {\n"
        out += images.sorted { $0.key < $1.key }
            .map { "      \(Self.quote($0.key)): \(Self.quote($0.value))" }
            .joined(separator: ",\n")
        out += "\n    }\n"
        out += "  }\n}\n"
        return Data(out.utf8)
    }

    /// A JSON string literal, escaped by the system rather than by hand.
    private static func quote(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        text.removeFirst()   // [
        text.removeLast()    // ]
        // `JSONSerialization` escapes forward slashes, so every path comes out as
        // `boards\/home.obf`. Legal JSON and decodes identically, but these are
        // paths a person reads while debugging an import. `\/` and `/` mean the
        // same thing inside a JSON string, so unescaping is safe.
        return text.replacingOccurrences(of: "\\/", with: "/")
    }
}

/// Reading a manifest back — for tests, and for whoever builds import.
struct OBFManifestRead: Decodable {
    let format: String
    let root: String
    let paths: [String: [String: String]]
}
