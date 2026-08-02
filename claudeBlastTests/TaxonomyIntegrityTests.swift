// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TaxonomyIntegrityTests.swift
//  claudeBlastTests
//
//  Guards the word-class taxonomy after the 2026-08 collapse (meals/fruit/veggie/
//  snacks folded into `food`) + `plant` addition + `object` tightening. The
//  class string is injected into the sentence prompt and drives tile color, so a
//  tile carrying a class not in `VocabularyClasses.all` silently renders gray and
//  hands the LLM a meaningless hint. This test fails the build if that ever ships.
//

import Testing
import Foundation
@testable import claudeBlast

@Suite struct TaxonomyIntegrityTests {

    /// Every `wordClass` carried by a bundled tile — core vocabulary.json plus the
    /// top-level `tiles`/`words` of every starter_*/pack_* manifest.
    private func bundledWordClasses() throws -> Set<String> {
        struct Entry: Decodable { let wordClass: String? }
        struct Manifest: Decodable { let tiles: [Entry]?; let words: [Entry]? }
        var classes = Set<String>()

        let vocabURL = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
                                    "vocabulary.json missing from the app bundle")
        try JSONDecoder().decode([Entry].self, from: Data(contentsOf: vocabURL))
            .compactMap(\.wordClass).forEach { classes.insert($0) }

        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("starter_")
                            || url.lastPathComponent.hasPrefix("pack_") {
            guard let m = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)) else { continue }
            (m.tiles ?? []).compactMap(\.wordClass).forEach { classes.insert($0) }
            (m.words ?? []).compactMap(\.wordClass).forEach { classes.insert($0) }
        }
        return classes
    }

    @Test func everyBundledClassIsKnown() throws {
        let known = Set(VocabularyClasses.all.map(\.name))
        let orphans = try bundledWordClasses().subtracting(known).sorted()
        #expect(orphans.isEmpty, "bundled tiles carry unknown wordClass(es): \(orphans)")
    }

    @Test func collapsedFoodSubclassesAreGone() throws {
        for dead in ["meals", "fruit", "veggie", "snacks"] {
            #expect(VocabularyClasses.known(dead) == nil, "\(dead) should have collapsed into food")
        }
        let bundled = try bundledWordClasses()
        #expect(bundled.contains("food"))
        #expect(bundled.isDisjoint(with: ["meals", "fruit", "veggie", "snacks"]))
    }

    @Test func plantIsAFirstClassCaregiverClass() throws {
        let plant = try #require(VocabularyClasses.known("plant"), "plant class should exist")
        #expect(plant.isCaregiverSelectable)
        #expect(try bundledWordClasses().contains("plant"), "seaweed/hay should tag as plant")
    }

    @Test func objectGuidanceFramesItAsLastResort() {
        // The centralized guidance must keep steering the AI away from the
        // object dumping-ground that mis-tagged whole animal/plant packs.
        let g = VocabularyClasses.classSelectionGuidance.lowercased()
        #expect(g.contains("last resort"))
        #expect(g.contains("animal") && g.contains("plant"))
    }
}
