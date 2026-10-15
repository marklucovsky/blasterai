// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ScenePagesCacheTests.swift
//  claudeBlastTests
//
//  `BlasterScene.pages` serves repeat reads from a decode cache keyed by the
//  stored bytes. A cache that answers fast and wrong is worse than the decode
//  it replaced, so these pin that every write is seen.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ScenePagesCacheTests {

    private func scene(_ pages: [PageSpec]) -> BlasterScene {
        let scene = BlasterScene(name: "Cache")
        scene.pages = pages
        return scene
    }

    @Test func repeatReadsAgree() {
        let s = scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])])
        #expect(s.pages.map(\.key) == ["home"])
        #expect(s.pages.map(\.key) == ["home"])
        #expect(s.pages.first?.tiles.map(\.key) == ["eat"])
    }

    /// Every editor writes the read-modify-write way; the read after must see it.
    @Test func aWriteIsSeenByTheNextRead() {
        let s = scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])])
        _ = s.pages  // warm the cache

        var pages = s.pages
        pages[0].tiles.append(TileEntry(key: "drink"))
        pages.append(PageSpec(key: "food", tiles: []))
        s.pages = pages

        #expect(s.pages.map(\.key) == ["home", "food"])
        #expect(s.pages.first?.tiles.map(\.key) == ["eat", "drink"])
    }

    /// A caller mutating its copy without writing back must not change what the
    /// next reader sees — the cache hands out values, not a shared buffer.
    @Test func mutatingAReadCopyDoesNotLeak() {
        let s = scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])])
        var copy = s.pages
        copy[0].tiles.removeAll()
        copy.append(PageSpec(key: "stray", tiles: []))

        #expect(s.pages.map(\.key) == ["home"])
        #expect(s.pages.first?.tiles.map(\.key) == ["eat"])
    }

    @Test func clearingIsSeen() {
        let s = scene([PageSpec(key: "home", tiles: [])])
        _ = s.pages
        s.pages = []
        #expect(s.pages.isEmpty)
    }

    /// Two scenes never share a cache.
    @Test func scenesAreIndependent() {
        let a = scene([PageSpec(key: "a", tiles: [])])
        let b = scene([PageSpec(key: "b", tiles: [])])
        _ = a.pages
        _ = b.pages
        #expect(a.pages.map(\.key) == ["a"])
        #expect(b.pages.map(\.key) == ["b"])
    }
}
}
