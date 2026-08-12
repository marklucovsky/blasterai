// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SystemSceneImmutabilityTests.swift
//  claudeBlastTests
//
//  System-owned scenes (non-empty systemSceneKey) are immutable: the caregiver
//  edits a CLONE instead. This closes two problems at once — app updates can
//  replace the bundled board without destroying user work, and the multi-device
//  dedup that collapses system scenes by key can never delete anything a
//  caregiver authored. See BlasterScene.isSystemOwned.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SystemSceneImmutabilityTests {

    private func makeScene(_ name: String, systemKey: String = "",
                           active: Bool = false) -> BlasterScene {
        let s = BlasterScene(name: name, homePageKey: "home",
                             isDefault: false, isActive: active)
        s.systemSceneKey = systemKey
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "eat", link: "", isAudible: true)])]
        return s
    }

    // MARK: - Ownership

    @Test func systemSceneKeyMarksOwnership() {
        #expect(makeScene("Core-First - System Supplied", systemKey: "core_first").isSystemOwned)
        #expect(!makeScene("My Board").isSystemOwned)
    }

    /// Bundled STARTERS are first-party but have no systemSceneKey — they are
    /// meant to be edited, which is their whole purpose. Immutability must key
    /// on systemSceneKey, never on isFirstParty.
    @Test func bundledStartersAreNotSystemOwned() {
        let starter = makeScene("Farm Visit")
        starter.sceneID = SceneIdentity.id(authority: SceneIdentity.firstPartyAuthority, slug: "farm")
        #expect(starter.isFirstParty)
        #expect(!starter.isSystemOwned)
    }

    // MARK: - Naming

    @Test func baseNameStripsTheSystemSuppliedMarker() {
        #expect(makeScene("Core-First" + BlasterScene.systemSuppliedSuffix).baseName == "Core-First")
        #expect(makeScene("My Board").baseName == "My Board")
    }

    // MARK: - Clone-on-write

    @Test func cloneIsUserOwnedAndIndependent() throws {
        let ctx = TestStore.freshContext()
        let system = makeScene("Core-First" + BlasterScene.systemSuppliedSuffix,
                               systemKey: "core_first")
        system.importedContentHash = system.contentHash
        ctx.insert(system)

        let copy = BlasterScene.cloneForEditing(system, in: ctx,
                                                authorID: "author-1", authorName: "Mark")

        // The copy is editable, deletable, and invisible to system-scene dedup.
        #expect(copy.systemSceneKey.isEmpty)
        #expect(!copy.isSystemOwned)
        #expect(!copy.isDefault)
        #expect(!copy.isImported)
        #expect(copy.name == "Core-First" + BlasterScene.myCopySuffix)
        // Content carried over...
        #expect(copy.pages.count == system.pages.count)
        #expect(copy.homePageKey == system.homePageKey)
        // ...but with its own identity, so two devices cloning don't collide.
        #expect(!copy.sceneID.isEmpty)
        #expect(copy.sceneID != system.sceneID)
        // A brand-new copy must not read as "modified locally".
        #expect(copy.importedContentHash.isEmpty)
        #expect(!copy.isLocallyModified)
    }

    @Test func cloneDoesNotStackSuffixes() throws {
        let ctx = TestStore.freshContext()
        let system = makeScene("Core-First" + BlasterScene.systemSuppliedSuffix,
                               systemKey: "core_first")
        ctx.insert(system)
        let copy = BlasterScene.cloneForEditing(system, in: ctx,
                                                authorID: "a", authorName: "")
        #expect(!copy.name.contains(BlasterScene.systemSuppliedSuffix))
    }

    @Test func secondCloneGetsADistinctName() throws {
        let ctx = TestStore.freshContext()
        let system = makeScene("Core-First" + BlasterScene.systemSuppliedSuffix,
                               systemKey: "core_first")
        ctx.insert(system)

        let first = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")
        try ctx.save()
        let second = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")

        #expect(first.name != second.name)
        #expect(second.name.hasPrefix("Core-First" + BlasterScene.myCopySuffix))
    }

    /// Editing the clone must leave the system scene byte-identical to its
    /// pristine baseline — that is what makes collapsing system duplicates safe.
    @Test func editingTheCloneLeavesTheSystemScenePristine() throws {
        let ctx = TestStore.freshContext()
        let system = makeScene("Core-First" + BlasterScene.systemSuppliedSuffix,
                               systemKey: "core_first")
        system.importedContentHash = system.contentHash
        ctx.insert(system)

        let copy = BlasterScene.cloneForEditing(system, in: ctx, authorID: "a", authorName: "")
        copy.appendTile(TileEntry(key: "pizza", link: "", isAudible: true), toPage: "home")

        #expect(copy.pages.first?.tiles.count == 2)
        #expect(system.pages.first?.tiles.count == 1)
        #expect(!system.isLocallyModified)          // untouched baseline
    }

    // MARK: - Active-scene resolution

    /// The bug this fixes: a freshly-installed device bootstraps the system
    /// scene as active, so its lastModified is NEWER than the user's board,
    /// which was chosen earlier. A pure most-recently-modified rule therefore
    /// switched the family back to the built-in board when they added a device.
    @Test func userSceneBeatsSystemSceneForActive_evenWhenSystemIsNewer() throws {
        let ctx = TestStore.freshContext()
        let mine = makeScene("My Board", active: true)
        mine.lastModified = .init(timeIntervalSinceReferenceDate: 100)   // older
        let system = makeScene("Core-First" + BlasterScene.systemSuppliedSuffix,
                               systemKey: "core_first", active: true)
        system.lastModified = .init(timeIntervalSinceReferenceDate: 900) // newer
        ctx.insert(mine); ctx.insert(system)

        CloudKitDedupReconciler.reconcile(context: ctx)

        #expect(mine.isActive)
        #expect(!system.isActive)
    }

    /// Between peers of the same kind, most-recently-modified still wins.
    @Test func betweenUserScenesMostRecentlyModifiedStillWins() throws {
        let ctx = TestStore.freshContext()
        let older = makeScene("A", active: true)
        older.lastModified = .init(timeIntervalSinceReferenceDate: 100)
        let newer = makeScene("B", active: true)
        newer.lastModified = .init(timeIntervalSinceReferenceDate: 900)
        ctx.insert(older); ctx.insert(newer)

        CloudKitDedupReconciler.reconcile(context: ctx)

        #expect(newer.isActive)
        #expect(!older.isActive)
    }
}
}
