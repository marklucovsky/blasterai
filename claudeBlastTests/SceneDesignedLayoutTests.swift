// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneDesignedLayoutTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
import CoreGraphics
@testable import claudeBlast

extension SerialTests {

/// A scene's declared grid (`BlasterScene.designedFor`): what it means, where it
/// applies, and that every path a scene travels carries it.
@MainActor
@Suite(.serialized)
struct SceneDesignedLayoutTests {

    private func scene(in context: ModelContext, designedFor: String = "") -> BlasterScene {
        let s = BlasterScene(name: "Ward", descriptionText: "", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]
        s.designedFor = designedFor
        context.insert(s)
        return s
    }

    // MARK: - The value

    @Test func everyDeclarableGridRoundTrips() {
        #expect(DesignedLayout.all.map(\.rawValue) == [
            "ipad-12x5", "ipad-10x4", "ipad-9x4",
            "phone-4x5", "phone-3x4", "phone-2x4",
        ])
        for designed in DesignedLayout.all {
            #expect(DesignedLayout(rawValue: designed.rawValue) == designed)
        }
    }

    /// Empty is undeclared; a grid this build has never heard of is treated as
    /// undeclared rather than guessed at.
    @Test func unknownOrEmptyIsUndeclared() {
        #expect(DesignedLayout(rawValue: "") == nil)
        #expect(DesignedLayout(rawValue: "ipad-14x6") == nil)
    }

    // MARK: - Where it applies

    @Test func liveBoardHonoursAMatchingDevice() {
        let ward = DesignedLayout(rawValue: "phone-2x4")
        #expect(GridLayoutCalculator.liveLayout(designed: ward, isPhone: true,
                                                deviceLayout: .standard, honorSceneLayouts: true) == .largest)
    }

    /// A caregiver may want Large for a child with low vision, whatever the
    /// author chose.
    @Test func aDeviceCanOptOut() {
        let ward = DesignedLayout(rawValue: "phone-2x4")
        #expect(GridLayoutCalculator.liveLayout(designed: ward, isPhone: true,
                                                deviceLayout: .large, honorSceneLayouts: false) == .large)
    }

    /// A phone board cannot keep its positions on an iPad's grid, so the iPad
    /// uses its own layout.
    @Test func theOtherKindOfDeviceUsesItsOwn() {
        let ward = DesignedLayout(rawValue: "phone-2x4")
        #expect(GridLayoutCalculator.liveLayout(designed: ward, isPhone: false,
                                                deviceLayout: .standard, honorSceneLayouts: true) == .standard)
    }

    /// The preview and page editor show the declared grid on any device — a
    /// phone board is designed on an iPad.
    @Test func authoringShowsTheDeclaredGridAnywhere() {
        let ward = DesignedLayout(rawValue: "phone-2x4")
        let onPad = GridLayoutCalculator.authoringGrid(designed: ward, isPhone: false, deviceLayout: .standard)
        #expect(onPad.cols == 2 && onPad.rows == 4)
        let undeclared = GridLayoutCalculator.authoringGrid(designed: nil, isPhone: false, deviceLayout: .large)
        #expect(undeclared.cols == 10 && undeclared.rows == 4)
    }

    @Test func anExplicitGridIsExact() {
        let spec = GridLayoutCalculator.compute(geo: CGSize(width: 700, height: 900),
                                                grid: (cols: 12, rows: 5))
        #expect(spec.cols == 12 && spec.rows == 5)
        let scrolling = GridLayoutCalculator.compute(geo: CGSize(width: 700, height: 1),
                                                     grid: (cols: 12, rows: 5), fitHeight: false)
        #expect(scrolling.tileSize > 40, "width-only sizing must not be squeezed by a 1pt height")
    }

    // MARK: - Every path carries it

    @Test func theBundledBoardIsDesignedForTheIPad() {
        let result = BootstrapLoader.loadDefaultVocabulary(context: TestStore.freshContainer().mainContext)
        #expect(result.scene.designedFor == "ipad-12x5")
    }

    /// `ExportableScene` lists its keys by hand, so a field left out of
    /// `CodingKeys` is silently dropped both ways. Export, then import into a
    /// fresh store.
    @Test func exportAndImportCarryIt() throws {
        let source = scene(in: TestStore.freshContainer().mainContext, designedFor: "phone-3x4")
        let data = try SceneExporter.exportJSON(source, tileLookup: [:])
        #expect(String(decoding: data, as: UTF8.self).contains("\"designedFor\" : \"phone-3x4\""))

        let result = try SceneImporter.importJSON(data, context: TestStore.freshContainer().mainContext)
        #expect(result.scene.designedFor == "phone-3x4")
    }

    @Test func undeclaredExportsNoKey() throws {
        let source = scene(in: TestStore.freshContainer().mainContext)
        let data = try SceneExporter.exportJSON(source, tileLookup: [:])
        #expect(!String(decoding: data, as: UTF8.self).contains("designedFor"))
    }

    @Test func cloneAndDuplicateCarryIt() {
        let context = TestStore.freshContainer().mainContext
        let source = scene(in: context, designedFor: "ipad-9x4")
        #expect(BlasterScene.cloneForEditing(source, in: context, authorID: "a", authorName: "A")
                    .designedFor == "ipad-9x4")
        #expect(BlasterScene.duplicate(of: source, in: context, authorID: "a", authorName: "A")
                    .designedFor == "ipad-9x4")
    }

    /// Undeclared leaves the content hash as it was before the field existed,
    /// so no existing scene starts reading "modified locally". Declaring one is
    /// a real change and moves it.
    @Test func undeclaredDoesNotMoveTheContentHash() {
        let context = TestStore.freshContainer().mainContext
        let s = scene(in: context)
        let before = s.contentHash
        s.designedFor = ""
        #expect(s.contentHash == before)
        s.designedFor = "ipad-12x5"
        #expect(s.contentHash != before)
    }
}
}
