// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneActivationTests.swift
//  claudeBlastTests
//
//  Repair what is unambiguous, refuse what is not, never silently do either.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneActivationTests {

    /// Note the order: pages first, then the home key.
    ///
    /// `BlasterScene.pages`'s setter calls `adoptHomePageIfNeeded`, so a scene
    /// built the other way round repairs itself on assignment and can never
    /// exhibit the fault. That is the invariant working — and it is also why the
    /// repair path in `SceneActivation` is reached mainly by scenes arriving
    /// from storage, import or sync, where no setter ran.
    private func scene(_ pages: [PageSpec], home: String = "home") -> BlasterScene {
        let scene = BlasterScene(name: "Test", descriptionText: "", homePageKey: "home")
        scene.pages = pages
        scene.homePageKey = home
        return scene
    }

    // MARK: - Refusal

    /// The only genuinely unusable state. There is nothing to adopt as a home
    /// page and nothing to draw, so a repair is not available — unlike every
    /// other fault, which the board can now survive.
    @Test("A scene with no pages is refused")
    func noPagesIsRefused() {
        #expect(throws: SceneActivation.Refusal.noPages) {
            _ = try SceneActivation.check(scene([]), vocabulary: ["eat"])
        }
    }

    /// Refusal has to say what is wrong. "Cannot activate" with no reason is
    /// how a caregiver ends up thinking the app is broken.
    @Test("A refusal explains itself")
    func refusalExplainsItself() {
        let message = SceneActivation.Refusal.noPages.errorDescription ?? ""
        #expect(message.contains("no pages"))
        #expect(message.contains("Add a page"))
    }

    /// Validation runs before anything is mutated, so a refused activation must
    /// leave the previously active scene alone — otherwise refusing is a second
    /// way to end up with no board.
    @Test("A refused activation does not deactivate the current scene")
    func refusalLeavesTheBoardAlone() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        context.insert(TileModel(key: "eat", wordClass: "actions"))

        let good = scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])])
        context.insert(good)
        _ = try good.activate(context: context)
        #expect(good.isActive)

        let empty = scene([])
        context.insert(empty)
        #expect(throws: (any Error).self) { try empty.activate(context: context) }

        #expect(good.isActive, "the working scene was deactivated by a failed activation")
        #expect(!empty.isActive)
    }

    // MARK: - Repair

    /// Unambiguous: pages exist, so one of them can be home. The fault that
    /// caused the first lockout — a hand-built scene whose homePageKey named
    /// no page.
    @Test("A dangling home page is repaired to the first page")
    func danglingHomeIsRepaired() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "farm", tiles: [TileEntry(key: "cow")])], home: "nowhere"),
            vocabulary: ["cow"])
        #expect(outcome.repairs == [.adoptedHomePage("farm")])
    }

    /// The clause that was missing. `activate` already did this repair — quietly
    /// — so a caregiver's board changed under them with no explanation.
    @Test("A repair is reported, not silent")
    func repairIsReported() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "farm", tiles: [TileEntry(key: "cow")])], home: "nowhere"),
            vocabulary: ["cow"])
        let message = try #require(outcome.message)
        #expect(message.contains("farm"))
        #expect(!outcome.isClean)
    }

    @Test("A healthy scene reports nothing")
    func healthySceneIsClean() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]),
            vocabulary: ["eat"])
        #expect(outcome.isClean)
        #expect(outcome.message == nil)
    }

    // MARK: - Warnings

    /// The second lockout: a scene imported from a file whose words had been
    /// dropped by the export bug. Populated in the editor, empty on the board.
    @Test("Words missing from this device are named")
    func missingWordsAreNamed() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [TileEntry(key: "cow"), TileEntry(key: "eat")])]),
            vocabulary: ["eat"])
        #expect(outcome.warnings.contains(.missingWords(["cow"])))
    }

    @Test("A scene with nothing pressable warns")
    func nothingPressableWarns() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [])]), vocabulary: ["eat"])
        #expect(outcome.warnings.contains(.noReachableWords))
    }

    /// A gap is not a word, so a page of gaps is as empty as a page of nothing.
    @Test("A page of only spacers is not reachable vocabulary")
    func spacersAreNotWords() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [TileEntry.spacer(), TileEntry.spacer()])]),
            vocabulary: ["eat"])
        #expect(outcome.warnings.contains(.noReachableWords))
        // And they must not be reported as missing words either — they name none.
        #expect(!outcome.warnings.contains { if case .missingWords = $0 { return true }; return false })
    }

    /// A wholly concealed board draws empty for the child, which is worth
    /// saying — even though it is survivable now and may be deliberate.
    @Test("A wholly concealed page warns rather than refusing")
    func whollyConcealedWarns() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat", isConcealed: true)])]),
            vocabulary: ["eat"])
        #expect(outcome.warnings.contains(.noReachableWords))
        #expect(outcome.repairs.isEmpty)
    }

    /// A caller with no vocabulary in hand should get the structural checks
    /// only, not every word reported missing.
    @Test("An empty vocabulary skips the word checks")
    func emptyVocabularySkipsWordChecks() throws {
        let outcome = try SceneActivation.check(
            scene([PageSpec(key: "home", tiles: [TileEntry(key: "eat")])]), vocabulary: [])
        #expect(outcome.isClean)
    }

    // MARK: - Activation applies what it reported

    @Test("Activation applies the repair it reported")
    func activationAppliesTheRepair() throws {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        context.insert(TileModel(key: "cow", wordClass: "animal"))

        let s = scene([PageSpec(key: "farm", tiles: [TileEntry(key: "cow")])], home: "nowhere")
        context.insert(s)
        let outcome = try s.activate(context: context)

        #expect(s.homePageKey == "farm")
        #expect(s.isActive)
        #expect(outcome.repairs == [.adoptedHomePage("farm")])
    }

}
}
