// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneEditingTests.swift
//  claudeBlastTests
//
//  Phase 1 editing primitives: bulk delete/move + same-scene page duplicate.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneEditingTests {

    private func makeContext() throws -> ModelContext {
        return TestStore.freshContext()
    }

    private func entry(_ k: String) -> TileEntry { TileEntry(key: k, link: "", isAudible: true) }

    private func sceneWithHome(_ ctx: ModelContext, _ keys: String...) -> BlasterScene {
        let s = BlasterScene(name: "T")
        s.pages = [PageSpec(key: "home", tiles: keys.map(entry))]
        ctx.insert(s)
        return s
    }

    private func homeKeys(_ s: BlasterScene) -> [String] {
        s.page(withKey: "home")?.tiles.map(\.key) ?? []
    }

    // MARK: - Bulk delete

    @Test func removeTilesRemovesOnlySelected() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a", "b", "c", "d")
        s.removeTiles(withKeys: ["b", "d"], fromPage: "home")
        #expect(homeKeys(s) == ["a", "c"])
    }

    @Test func removeTilesEmptyIsNoOp() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a", "b")
        s.removeTiles(withKeys: [], fromPage: "home")
        #expect(homeKeys(s) == ["a", "b"])
    }

    // MARK: - Bulk move

    @Test func moveTilesToFrontPreservesRelativeOrder() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a", "b", "c", "d")
        s.moveTiles(withKeys: ["b", "d"], toFront: true, inPage: "home")
        #expect(homeKeys(s) == ["b", "d", "a", "c"])
    }

    @Test func moveTilesToEndPreservesRelativeOrder() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a", "b", "c", "d")
        s.moveTiles(withKeys: ["a", "c"], toFront: false, inPage: "home")
        #expect(homeKeys(s) == ["b", "d", "a", "c"])
    }

    // MARK: - Duplicate page

    @Test func duplicatePageIndependentCopyDedupedKey() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a", "b")
        let newKey = s.duplicatePage("home")
        #expect(newKey == "home_2")
        #expect(s.pages.count == 2)
        #expect(s.page(withKey: "home_2")?.tiles.map(\.key) == ["a", "b"])
        // Editing the copy must not touch the original.
        s.removeTiles(withKeys: ["a"], fromPage: "home_2")
        #expect(homeKeys(s) == ["a", "b"])
        #expect(s.page(withKey: "home_2")?.tiles.map(\.key) == ["b"])
    }

    @Test func duplicatePageDedupIncrements() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a")
        _ = s.duplicatePage("home")          // home_2
        #expect(s.duplicatePage("home") == "home_3")
    }

    @Test func duplicateMissingPageReturnsNil() throws {
        let ctx = try makeContext()
        let s = sceneWithHome(ctx, "a")
        #expect(s.duplicatePage("nope") == nil)
        #expect(s.pages.count == 1)
    }

    // MARK: - Home toggle-off fallback

    /// The reported case: the current home IS the "home"-keyed page in slot 0.
    /// Toggling off must NOT stick on it — it hands home to the first other page.
    @Test func toggleOffHomeKeyedPageInSlot0PicksFirstOther() throws {
        let ctx = try makeContext()
        let s = BlasterScene(name: "T", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: []),
                   PageSpec(key: "people", tiles: []),
                   PageSpec(key: "food", tiles: [])]
        ctx.insert(s)
        #expect(s.homeKeyAfterTogglingOffCurrent() == "people")
    }

    /// Toggling off a non-"home" home prefers the conventional "home"-keyed page.
    @Test func toggleOffNonHomePagePrefersHomeKeyedPage() throws {
        let ctx = try makeContext()
        let s = BlasterScene(name: "T", homePageKey: "actions")
        s.pages = [PageSpec(key: "people", tiles: []),
                   PageSpec(key: "home", tiles: []),
                   PageSpec(key: "actions", tiles: [])]
        ctx.insert(s)
        #expect(s.homeKeyAfterTogglingOffCurrent() == "home")
    }

    /// A sole page has nowhere to hand home to — stays home.
    @Test func toggleOffSolePageReturnsNil() throws {
        let ctx = try makeContext()
        let s = BlasterScene(name: "T", homePageKey: "home")
        s.pages = [PageSpec(key: "home", tiles: [])]
        ctx.insert(s)
        #expect(s.homeKeyAfterTogglingOffCurrent() == nil)
    }
}
}
