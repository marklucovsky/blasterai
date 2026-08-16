// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ImageSetCatalogTests.swift
//  claudeBlastTests
//
//  2B: image set identity, after ImageSetID stopped being a closed enum.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ImageSetCatalogTests {

    // MARK: - Identity is persisted data

    /// `TileArtVariant.imageSetRaw` is a SYNCED CloudKit field and the `imageSet`
    /// UserDefault is on every install. Both hold these exact strings, so a slug
    /// is not a rename away from orphaning a caregiver's generated art.
    @Test func builtInSlugsAreFrozen() {
        #expect(ImageSetID.classic.rawValue == "classic")
        #expect(ImageSetID.playful3D.rawValue == "playful_3d")
        #expect(ImageSetID.highContrast.rawValue == "high_contrast")
        #expect(ImageSetID.classicMedium.rawValue == "classic_medium")
        #expect(ImageSetID.classicMediumDark.rawValue == "classic_medium_dark")
    }

    /// An unknown id must stay itself. The old enum answered an unrecognised raw
    /// with `?? .playful3D`, which silently rendered a different set's art — the
    /// exact failure that made installable sets impossible to add safely.
    @Test func unknownIDIsPreservedNotSubstituted() {
        let unknown = ImageSetID("some_installed_set")
        #expect(unknown.rawValue == "some_installed_set")
        #expect(ImageSetCatalog.descriptor(for: unknown) == nil)
        // Prefix falls back to the slug, so it looks for its own art and finds
        // nothing — rather than quietly resolving to another set's files.
        #expect(ImageSetCatalog.bundlePrefix(for: unknown) == "some_installed_set")
        #expect(unknown.displayName == "some_installed_set")
    }

    // MARK: - Resolution ladder (mirrors scenes)

    @Test func resolvesBySlugQualifiedIDAndDisplayName() {
        #expect(ImageSetCatalog.descriptor(forSlug: "classic")?.id == .classic)
        #expect(ImageSetCatalog.descriptor(
            for: ImageSetID("imagesets.blasterai.app/classic"))?.id == .classic)
        #expect(ImageSetCatalog.descriptor(for: ImageSetID("Classic"))?.id == .classic)
    }

    @Test func systemSetsCarryFirstPartyProvenance() {
        for set in ImageSetCatalog.system {
            #expect(set.setID.hasPrefix(ImageSetCatalog.firstPartyAuthority + "/"))
            #expect(set.isSystemOwned, "system sets must be immutable")
            #expect(!set.systemSetKey.isEmpty)
        }
    }

    /// Mutability is gated on `systemSetKey`, exactly as `BlasterScene` gates on
    /// `systemSceneKey` — never on "is it first-party", because a bundled set a
    /// caregiver may edit is still theirs to edit.
    @Test func installedSetIsNotSystemOwned() {
        let installed = ImageSetDescriptor(
            id: ImageSetID("khmer_core"), setID: "author-123/khmer_core",
            displayName: "Khmer Core", shortName: "Khmer", summary: "",
            bundlePrefix: "khmer", version: "1.0.0",
            systemSetKey: "",                    // <- the whole test
            isShippable: true, isGenerationTarget: true,
            stylePromptKey: "classic", toneExemplarKey: "")
        #expect(!installed.isSystemOwned)
        #expect(installed.acceptsNewWords)
    }

    // MARK: - Bundle wiring

    /// Every shippable set must actually have art in the bundle under its own
    /// prefix. A descriptor pointing at a prefix nobody synced renders a whole
    /// set of placeholders while looking perfectly configured.
    @Test func everyShippableSetHasBundledArt() {
        for set in ImageSetCatalog.all where set.isShippable {
            let name = "\(set.bundlePrefix)_eat"
            let found = ["heic", "png"].contains {
                Bundle.main.url(forResource: name, withExtension: $0) != nil
            }
            #expect(found, "no bundled art for \(set.displayName) (\(name))")
        }
    }

    @Test func bundlePrefixesAreUnique() {
        let prefixes = ImageSetCatalog.all.map(\.bundlePrefix)
        #expect(Set(prefixes).count == prefixes.count,
                "two sets sharing a prefix would resolve each other's art")
    }

    @Test func setIDsAreUnique() {
        let ids = ImageSetCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Tone variants

    /// The tone sets are Classic with skin recoloured and nothing else, so they
    /// must generate new words in Classic's style. Keying the style on the set id
    /// instead would miss `image_styles.json` (which has no `classic_medium`
    /// entry) and silently drop every tone-set word-add to the generic fallback.
    @Test func toneVariantsShareClassicStyle() {
        for id in [ImageSetID.classicMedium, .classicMediumDark] {
            let d = ImageSetCatalog.descriptor(for: id)
            #expect(d?.stylePromptKey == "classic")
            #expect(d?.acceptsNewWords == true)
        }
    }

    /// A tone set without an exemplar cannot tone-match a new word, so a
    /// caregiver's added word would arrive as the only light-skinned figure in
    /// their set — the exact absence these sets exist to remove.
    @Test func toneVariantsDeclareAnExemplar() {
        #expect(!ImageSetID.classicMedium.toneExemplarKey.isEmpty)
        #expect(!ImageSetID.classicMediumDark.toneExemplarKey.isEmpty)
        // Base Classic is the light end of the scale; it has no tone to match.
        #expect(ImageSetID.classic.toneExemplarKey.isEmpty)
    }

    @Test func exemplarTilesExistInTheirOwnSet() {
        for set in ImageSetCatalog.all where !set.toneExemplarKey.isEmpty {
            let name = "\(set.bundlePrefix)_\(set.toneExemplarKey)"
            let found = ["heic", "png"].contains {
                Bundle.main.url(forResource: name, withExtension: $0) != nil
            }
            #expect(found, "\(set.displayName) names exemplar \(name), which isn't bundled")
        }
    }

    // MARK: - Defaults

    @Test func defaultAndBackfillAreClassic() {
        #expect(ImageSetID.defaultSet == .classic)
        #expect(ImageSetID.universalBackfill == .classic)
        // The backfill covers gaps in every other set, so it must be complete.
        #expect(ImageSetCatalog.descriptor(for: .universalBackfill)?.isShippable == true)
    }

    @Test func generationTargetsPutThePreferredSetFirst() {
        let ordered = ImageSetCatalog.generationTargets(preferring: .classicMediumDark)
        #expect(ordered.first == .classicMediumDark)
        #expect(Set(ordered) == Set(ImageSetCatalog.generationTargets))
        // High Contrast isn't a generation target — nothing generates into it.
        #expect(!ImageSetCatalog.generationTargets.contains(.highContrast))
    }

    @Test func everySelectableSetIsShippableInRelease() {
        #if !DEBUG
        #expect(ImageSetCatalog.selectable.allSatisfy(\.isShippable))
        #endif
        #expect(!ImageSetCatalog.selectable.isEmpty)
    }
}
}
