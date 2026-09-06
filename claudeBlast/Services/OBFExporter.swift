// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OBFExporter.swift
//  claudeBlast
//
//  A board, in the format the rest of the AAC world reads.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
enum OBFExporter {

    /// The vocabulary word the app's injected Home cell renders
    /// (`wordClass: navigation`). Used to give an exported sub-board its way
    /// back, since OBF has no equivalent of injected chrome.
    static let homeTileKey = "home"

    /// A board id that is unique across every scene, not just within one.
    ///
    /// **A bare page key is not safe as a board id.** Cboard's importer skips any
    /// board whose id it already holds:
    ///
    /// ```js
    /// tempBoard.id !== 'root' && !allBoardsIds.includes(tempBoard.id)
    /// ```
    ///
    /// Page keys are generic and repeat across scenes — `body_health`,
    /// `vehicles`, `home` — so importing a second scene silently dropped every
    /// page whose name had been seen before, and re-importing a corrected export
    /// dropped all of it. No error; the boards just were not there.
    ///
    /// Qualifying with the scene's identity makes "the same board" mean the same
    /// board, which is the behaviour that check is reaching for. `sceneID` is
    /// already globally unique (author id + slug); `/` becomes `_` so the id is
    /// safe anywhere an id is used.
    ///
    /// `ext_blasterai_page_key` still carries the bare key for anything importing
    /// back into Blaster.
    static func boardID(for pageKey: String, in scene: BlasterScene) -> String {
        let identity = scene.sceneID.isEmpty
            ? (scene.slug.isEmpty ? scene.name.sanitizedFilename.lowercased() : scene.slug)
            : scene.sceneID
        guard !identity.isEmpty else { return pageKey }
        return "\(identity)_\(pageKey)".replacingOccurrences(of: "/", with: "_")
    }

    /// Grid shape for a board of `count` buttons.
    ///
    /// OBF pins buttons to a fixed rows × columns grid; our boards reflow to
    /// whatever device they are on, so there is no "true" answer to carry across
    /// — this is a rendering choice made once, at export. Slightly wider than
    /// tall, matching how the app lays a page out on a landscape tablet, which is
    /// what most AAC readers assume.
    static func grid(for count: Int) -> (rows: Int, columns: Int) {
        guard count > 0 else { return (1, 1) }
        let columns = max(1, Int(ceil(sqrt(Double(count) * 1.4))))
        return (max(1, Int(ceil(Double(count) / Double(columns)))), columns)
    }

    /// OBF writes colours as `rgb(r, g, b)`, not hex.
    static func rgbString(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))"
    }

    /// Build the board documents for a scene, plus the set of tile keys whose
    /// pictures the package has to carry.
    ///
    /// Pure, so the mapping can be tested without writing a zip.
    static func boards(for scene: BlasterScene,
                       tileLookup: [String: TileModel]) -> (boards: [OBFBoard], imageKeys: [String]) {
        var imageKeys: [String] = []
        var seenImages = Set<String>()

        let boards: [OBFBoard] = scene.pages.map { page in
            var buttons: [OBFButton] = []
            var images: [OBFImage] = []
            var order: [String?] = []

            // Home has to be written out, because OBF has no chrome.
            //
            // In the app, Home is not a tile: the grid injects it at cell 0 of
            // every page, so it never appears in `page.tiles`. Export it as-is
            // and a board set arrives with no way back — every sub-board a
            // one-way trip, which is worse than useless to a child.
            //
            // Cell 0 matches the app exactly, and for the same reason: an
            // invariant position is what makes it motor-planned rather than
            // hunted for.
            var pageEntries = page.tiles
            if page.key != scene.homePageKey,
               scene.pages.contains(where: { $0.key == scene.homePageKey }),
               !page.tiles.contains(where: { $0.link == scene.homePageKey || $0.link == "<home>" }) {
                pageEntries.insert(TileEntry(key: OBFExporter.homeTileKey,
                                             link: scene.homePageKey, isAudible: false),
                                   at: 0)
            }

            for entry in pageEntries {
                // Both kinds of gap leave as a gap: `grid.order` takes null for
                // a cell with nothing in it. No button, no image, no id.
                //
                // ## Why a concealed word is not exported as `hidden: true`
                //
                // OBF has the field, we emitted it, and it is the more faithful
                // statement — the word is on the board and unavailable. CoughDrop
                // honours it. **Cboard does not**, on a button that also carries
                // `load_board`, and shows the word anyway.
                //
                // That asymmetry decides it. A reader that ignores `hidden`
                // hands the child vocabulary a therapist deliberately took away,
                // on a board they believe is the one they configured. A reader
                // that sees a gap is merely missing a word. We cannot control
                // which reader opens the file, so the export states the thing
                // that is safe to misread.
                //
                // The cost is real and one-directional: the concealed word does
                // NOT travel in the .obz, so an .obz is not a lossless copy of a
                // board that uses conceal. `.blasterscene` is — it carries
                // `isConcealed` per placement — and it is the right format for
                // moving a board between Blaster devices. See
                // `docs/obf-interop.md`.
                if entry.isEmptyCell {
                    order.append(nil)
                    continue
                }
                guard let tile = tileLookup[entry.key] else { continue }
                let buttonID = entry.key

                // A page link becomes a real navigation button here. Unlike a
                // vocabulary pack — where a link means nothing outside its scene
                // and is dropped — an .obz carries the whole scene, so the target
                // board travels with it and the link stays meaningful.
                var loadBoard: OBFLoadBoard?
                if !entry.link.isEmpty {
                    let target = entry.link == "<home>" ? scene.homePageKey : entry.link
                    if scene.pages.contains(where: { $0.key == target }) {
                        // `path` is what Cboard matches on, and it must equal the
                        // zip entry key exactly. `id` is for readers that resolve
                        // by id instead.
                        // The destination's own name, not one derived from its
                        // key — a renamed page should read the same on the link
                        // as on the board it opens.
                        let targetTitle = scene.pages.first { $0.key == target }?.title
                            ?? PageNaming.displayName(target)
                        loadBoard = OBFLoadBoard(id: boardID(for: target, in: scene),
                                                 path: "boards/\(target).\(OBFFormat.boardExtension)",
                                                 name: targetTitle)
                    }
                }

                if seenImages.insert(tile.bundleImage).inserted {
                    imageKeys.append(tile.bundleImage)
                }
                images.append(OBFImage(id: tile.bundleImage,
                                       path: "images/\(tile.bundleImage).png",
                                       width: 512, height: 512,
                                       content_type: "image/png",
                                       license: license(for: tile, scene: scene)))

                let accent = loadBoard != nil ? TileColorResolver.navigation
                                              : TileColorResolver.color(for: tile)
                buttons.append(OBFButton(
                    id: buttonID,
                    label: tile.displayName.isEmpty ? tile.key : tile.displayName,
                    image_id: tile.bundleImage,
                    // A navigation button travels rather than speaks, so it
                    // carries no vocalization. Same for a tile the caregiver
                    // silenced: OBF has no "present but silent" concept, and an
                    // absent vocalization is the closest true statement.
                    vocalization: (loadBoard == nil && entry.isAudible)
                        ? (tile.value.isEmpty ? tile.displayName : tile.value)
                        : nil,
                    background_color: rgbString(accent.opacity(1)),
                    border_color: rgbString(accent),
                    load_board: loadBoard,
                    ext_blasterai_word_class: tile.wordClass,
                    ext_blasterai_tile_key: tile.key))
                order.append(buttonID)
            }

            let shape = grid(for: order.count)
            var rows: [[String?]] = []
            for row in 0..<shape.rows {
                let start = row * shape.columns
                let slice = (0..<shape.columns).map { column -> String? in
                    let index = start + column
                    return index < order.count ? order[index] : nil
                }
                rows.append(slice)
            }

            return OBFBoard(
                id: boardID(for: page.key, in: scene),
                name: page.title,
                description_html: scene.descriptionText.isEmpty ? nil : scene.descriptionText,
                buttons: buttons,
                grid: OBFGrid(rows: shape.rows, columns: shape.columns, order: rows),
                images: images,
                ext_blasterai_scene_id: scene.sceneID.isEmpty ? nil : scene.sceneID,
                ext_blasterai_page_key: page.key)
        }

        return (boards, imageKeys)
    }

    /// Bundled art is the project's own; a caregiver's generated word is theirs.
    static func license(for tile: TileModel, scene: BlasterScene) -> OBFLicense {
        tile.isSystem ? .firstParty : .caregiver(author: scene.authorDisplay)
    }

    // MARK: - Package

    /// Write the scene as an `.obz`.
    ///
    /// `.obz` rather than `.obf` because a bare board references images it does
    /// not carry: ours would open anywhere else as a board of broken pictures.
    /// The zip holds the boards, the manifest, and a PNG per tile.
    static func exportOBZ(scene: BlasterScene,
                          tileLookup: [String: TileModel],
                          imageSet: ImageSetID,
                          resolver: TileImageResolver,
                          basename: String,
                          progress: @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> URL {
        let built = boards(for: scene, tileLookup: tileLookup)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        // Entries are assembled with their final paths and written as one
        // archive, because an `.obz` reader expects `manifest.json` at the ROOT.
        // Zipping a staging folder nests everything under it, which is invisible
        // locally and fatal on the far side.
        var entries: [(path: String, data: Data)] = []

        // The home board is written first.
        //
        // `manifest.root` is the spec's answer to "which board opens", and a
        // conforming reader honours it. Not every reader does — some take the
        // first board they encounter, and a JSON object's key order is not
        // meaningful, so ordering the *archive* is the only lever we have.
        // Costs nothing and removes a whole class of "it opened on the wrong
        // page" from readers we cannot test.
        var ordered = built.boards
        if let home = ordered.firstIndex(where: { $0.ext_blasterai_page_key == scene.homePageKey }) {
            ordered.insert(ordered.remove(at: home), at: 0)
        }

        var boardPaths: [String: String] = [:]
        for board in ordered {
            // Paths stay page-key based so a person reading the archive can tell
            // what they are looking at; only the *id* is qualified.
            let path = "boards/\(board.ext_blasterai_page_key ?? board.id).\(OBFFormat.boardExtension)"
            entries.append((path, try encoder.encode(board)))
            boardPaths[board.id] = path
        }

        // PNG, not our HEIC: this is the one direction where the recipient is
        // explicitly not Blaster, and a HEIC an OBF reader cannot decode is worse
        // than a larger file it can.
        var imagePaths: [String: String] = [:]
        let total = built.imageKeys.count
        progress(0, total)
        for (index, key) in built.imageKeys.enumerated() {
            try Task.checkCancellation()
            if let png = ExportArtResolver.renderedPNG(key, in: imageSet, resolver: resolver) {
                let path = "images/\(key).png"
                entries.append((path, png))
                imagePaths[key] = path
            }
            progress(index + 1, total)
            await Task.yield()
        }

        // The home page is the board a reader opens first. If `homePageKey` names
        // a page that no longer exists — a home page deleted without the key
        // being repointed — fall back to the first board rather than writing a
        // root that resolves to nothing.
        let rootBoard = boardPaths[boardID(for: scene.homePageKey, in: scene)]
            ?? ordered.first.flatMap { boardPaths[$0.id] }
            ?? "boards/\(scene.homePageKey).\(OBFFormat.boardExtension)"
        let manifest = OBFManifest(root: rootBoard,
                                   boardOrder: ordered.map(\.id),
                                   boards: boardPaths,
                                   images: imagePaths)
        entries.insert(("manifest.json", try manifest.jsonData()), at: 0)

        return try ZipWriter.zip(entries: entries,
                                 named: "\(basename).\(OBFFormat.packageExtension)")
    }
}
