// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileArtKeyTests.swift
//  claudeBlastTests
//
//  Art is keyed by the picture, not by the tile.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct TileArtKeyTests {

    @Test("A tile with no alias keys art on itself")
    func plainTileKeysOnItself() {
        let tile = TileModel(key: "cow", wordClass: "animal")
        #expect(tile.artKey == "cow")
    }

    /// The case the whole fix is about. A page cover aliases the pack's cover
    /// picture, and several pages can point at the same one — art belongs to the
    /// picture so they share it.
    @Test("An aliased tile keys art on the picture it points at")
    func aliasedTileKeysOnThePicture() {
        let cover = TileModel(key: "page_farm", wordClass: PageLink.wordClass)
        cover.bundleImage = "packcover_farm"
        #expect(cover.artKey == "packcover_farm")
    }

    /// The field failure: art generated for a page cover was stored under
    /// `page_farm` while every reader looked under `packcover_farm`, so the tile
    /// reported "needs art" forever and generating again wrote another unread
    /// row. Sharing the scene carried the art and reproduced it on the recipient.
    @Test("Imported art lands where the reader looks")
    func importedArtLandsUnderTheAlias() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext

        let png = Data("not-a-real-png-but-non-empty".utf8).base64EncodedString()
        let json = """
        {"@type":"\(BlasterSceneFormat.mediaType)","version":"\(BlasterSceneFormat.currentVersion)",\
        "name":"Farm","description":"","homePageKey":"home",\
        "pages":[{"key":"home","tiles":[{"key":"page_farm","isAudible":false,"link":"farm"}]},\
        {"key":"farm","tiles":[]}],\
        "tiles":[{"key":"page_farm","displayName":"Farm","wordClass":"\(PageLink.wordClass)",\
        "bundleImage":"packcover_farm",\
        "art":[{"imageSet":"classic","imageData":"\(png)"}]}]}
        """

        _ = try SceneImporter.importJSON(Data(json.utf8), context: context)

        let variants = try context.fetch(FetchDescriptor<TileArtVariant>())
        let keys = Set(variants.map(\.tileKey))
        #expect(keys.contains("packcover_farm"),
                "art was stored somewhere no reader looks; keys were \(keys.sorted())")
        #expect(!keys.contains("page_farm"),
                "art stored under the tile key is unreachable — that is the bug")
    }
}
}
