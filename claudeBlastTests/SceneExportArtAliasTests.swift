// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExportArtAliasTests.swift
//  claudeBlastTests
//
//  A tile that borrows another key's art must keep borrowing it after a share.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneExportArtAliasTests {

    private func scene(with entry: TileEntry) -> BlasterScene {
        let scene = BlasterScene(name: "S", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: [entry])]
        return scene
    }

    /// A page link for a bundled pack aliases `packcover_<slug>` — that is where
    /// its picture is. Without the alias the cover resolves against the tile's
    /// own key, finds nothing, and every page link on Home renders as a letter
    /// placeholder on the receiving device.
    @Test func aPageLinkCarriesItsCoverAlias() {
        let tile = TileModel(key: "page_space", value: "Space", wordClass: "page_link")
        tile.bundleImage = "packcover_space"

        let exported = SceneExporter.export(
            scene(with: TileEntry(key: "page_space", link: "space", isAudible: false)),
            defaultTileKeys: BundledVocabulary.keys,
            tileLookup: [tile.key: tile]
        )

        let carried = try! #require(exported.tiles?.first { $0.key == "page_space" })
        #expect(carried.bundleImage == "packcover_space")
    }

    /// A word alias travels too — `him` borrows `he`'s art. Same mechanism,
    /// quieter failure, since a missing picture on one word reads as art nobody
    /// generated rather than as a bug.
    @Test func aWordAliasIsCarried() {
        let tile = TileModel(key: "him", value: "him", wordClass: "core")
        tile.bundleImage = "he"

        let exported = SceneExporter.export(
            scene(with: TileEntry(key: "him", link: "", isAudible: true)),
            defaultTileKeys: [],
            tileLookup: [tile.key: tile]
        )

        #expect(exported.tiles?.first?.bundleImage == "he")
    }

    /// The ordinary case writes nothing. An alias equal to the key is the
    /// default; carrying it would add a redundant field to every tile in every
    /// file, and would make "has an alias" untestable by presence.
    @Test func aTileWithNoAliasWritesNoField() {
        let tile = TileModel(key: "rocket", value: "rocket", wordClass: "object")

        let exported = SceneExporter.export(
            scene(with: TileEntry(key: "rocket", link: "", isAudible: true)),
            defaultTileKeys: [],
            tileLookup: [tile.key: tile]
        )

        #expect(exported.tiles?.first?.bundleImage == nil)
    }

    /// Round-trips through JSON, which is the only form that actually ships.
    /// A field present on the struct but absent from `CodingKeys` would pass
    /// every in-memory assertion above and still arrive empty.
    @Test func theAliasSurvivesJSON() throws {
        let tile = TileModel(key: "page_space", value: "Space", wordClass: "page_link")
        tile.bundleImage = "packcover_space"

        let data = try SceneExporter.exportJSON(
            scene(with: TileEntry(key: "page_space", link: "space", isAudible: false)),
            defaultTileKeys: BundledVocabulary.keys,
            tileLookup: [tile.key: tile]
        )
        let decoded = try JSONDecoder().decode(ExportableScene.self, from: data)

        #expect(decoded.tiles?.first?.bundleImage == "packcover_space")
    }

    /// An older file has no alias field at all, and must decode as "no alias"
    /// rather than failing.
    @Test func aFileWithoutTheFieldStillDecodes() throws {
        let json = """
        {"@type":"application/vnd.claudeblast.scene+json","version":"1.0.0",
         "name":"Old","description":"","homePageKey":"home",
         "pages":[{"key":"home","tiles":[{"key":"rocket","isAudible":true,"link":""}]}],
         "tiles":[{"key":"rocket","wordClass":"object","displayName":"Rocket"}]}
        """
        let decoded = try JSONDecoder().decode(ExportableScene.self,
                                               from: Data(json.utf8))
        #expect(decoded.tiles?.first?.bundleImage == nil)
    }
}
}
