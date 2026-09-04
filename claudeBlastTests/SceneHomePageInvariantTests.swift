// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneHomePageInvariantTests.swift
//  claudeBlastTests
//
//  A scene must never be able to name a home page that does not exist.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneHomePageInvariantTests {

    /// The first page a scene gets becomes its home page.
    ///
    /// A scene whose home page names nothing renders no board, and since Admin
    /// is reached by long-pressing Home — which lives on the board — that scene
    /// cannot be edited or deactivated from the device it is active on.
    @Test func theFirstPageBecomesHomeWhenHomeNamesNothing() {
        let scene = BlasterScene(name: "S", homePageKey: "")
        scene.pages = [PageSpec(key: "vehicles", tiles: [])]
        #expect(scene.homePageKey == "vehicles")
    }

    /// A home page that does resolve is left alone — the invariant repairs, it
    /// does not reorder.
    @Test func aValidHomePageIsNotMoved() {
        let scene = BlasterScene(name: "S", homePageKey: "home")
        scene.pages = [PageSpec(key: "vehicles", tiles: []),
                       PageSpec(key: "home", tiles: [])]
        #expect(scene.homePageKey == "home")
    }

    /// Deleting the page that happened to be home repairs rather than bricks.
    @Test func deletingTheHomePageAdoptsAnother() {
        let scene = BlasterScene(name: "S", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: []),
                       PageSpec(key: "space", tiles: [])]
        scene.pages = scene.pages.filter { $0.key != "home" }
        #expect(scene.homePageKey == "space")
    }

    /// An empty scene has nothing to adopt and must not crash reaching for it.
    @Test func anEmptySceneKeepsItsKeyAndDoesNotTrap() {
        let scene = BlasterScene(name: "S", homePageKey: "home")
        scene.pages = []
        #expect(scene.homePageKey == "home")
    }

    /// Activation is the last line of defence: a scene can arrive with
    /// `homePageKey` written AFTER its pages — an importer assigning fields in
    /// field order does exactly that — which slips past the `pages` setter.
    /// Activation is where an unreachable home page becomes a board that will
    /// not draw, so it is checked again there.
    @Test func activationRepairsAHomePageWrittenAfterThePages() throws {
        let container = try ModelContainer(
            for: BlasterScene.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let scene = BlasterScene(name: "S", homePageKey: "home")
        scene.pages = [PageSpec(key: "space", tiles: [])]
        // Field-order assignment, after the setter has already run.
        scene.homePageKey = "does_not_exist"
        context.insert(scene)

        try scene.activate(context: context)

        #expect(scene.homePageKey == "space")
        #expect(scene.isActive)
    }
}
}
