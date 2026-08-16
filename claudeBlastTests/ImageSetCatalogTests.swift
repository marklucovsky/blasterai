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
        // Case-insensitive on every rung: a hand-written script saying "Classic"
        // must find the set whose slug is `classic`. This used to pass only by
        // accident, matching the displayName back when it was literally
        // "Classic" — and broke when the label became "Classic — Light".
        #expect(ImageSetCatalog.descriptor(for: ImageSetID("Classic"))?.id == .classic)
        #expect(ImageSetCatalog.descriptor(for: ImageSetID("CLASSIC_MEDIUM"))?.id == .classicMedium)
        // Display names still resolve, including the renamed ones.
        #expect(ImageSetCatalog.descriptor(for: ImageSetID("Classic — Dark"))?.id == .classicMediumDark)
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
            stylePromptKey: "classic", toneExemplarKey: "", toneBase: nil)
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

    // MARK: - Tone families

    /// Every tone variant must name a base that exists and is itself a base.
    /// Without the link, a runtime word-add generates each set independently and
    /// the family stops being one figure: adding "swimmer" produced three
    /// different swimmers, in different swimsuits, one wearing a cap.
    @Test func toneVariantsPointAtARealBase() {
        let variants = ImageSetCatalog.all.filter(\.isToneVariant)
        #expect(!variants.isEmpty)
        for v in variants {
            let base = ImageSetCatalog.descriptor(for: v.toneBase!)
            #expect(base != nil, "\(v.displayName) names a base that does not exist")
            #expect(base?.isToneVariant == false, "tone bases must not themselves be variants")
            // A variant is a recolour, so it has to be drawn the same way.
            #expect(base?.stylePromptKey == v.stylePromptKey,
                    "\(v.displayName) and its base are drawn in different styles")
            // And it needs an exemplar, or there is nothing to recolour toward.
            #expect(!v.toneExemplarKey.isEmpty)
        }
    }

    @Test func classicToneFamilyIsComplete() {
        let family = ImageSetCatalog.all.filter { $0.toneBase == .classic }.map(\.id)
        #expect(Set(family) == [.classicMedium, .classicMediumDark])
        #expect(ImageSetCatalog.descriptor(for: .classic)?.toneBase == nil)
    }

    /// Distinct styles must NOT be tone variants — recolouring Classic would not
    /// produce Playful 3D or High Contrast art, it would produce Classic art in
    /// the wrong set.
    @Test func distinctStylesAreNotToneVariants() {
        #expect(ImageSetCatalog.descriptor(for: .playful3D)?.isToneVariant == false)
        #expect(ImageSetCatalog.descriptor(for: .highContrast)?.isToneVariant == false)
    }

    /// High Contrast ships and has a style prompt, so "Generate all styles" must
    /// include it. It was excluded while the set was incomplete, and leaving that
    /// stale meant the toggle silently skipped it — the Contrast slot just stayed
    /// empty with no error.
    @Test func everyShippableStyleIsAGenerationTarget() {
        let targets = Set(ImageSetCatalog.generationTargets)
        for set in ImageSetCatalog.all where set.isShippable {
            #expect(targets.contains(set.id),
                    "\(set.displayName) ships but 'generate all styles' skips it")
        }
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
        // High Contrast IS a generation target now. This assertion previously
        // said the opposite, encoding the state from when the set was incomplete
        // and unshippable — which is exactly why "Generate all styles" left the
        // Contrast slot empty with no error. It ships and has a style prompt, so
        // it generates; `everyShippableStyleIsAGenerationTarget` guards the rule.
        #expect(ImageSetCatalog.generationTargets.contains(.highContrast))
    }

    // MARK: - Reading persisted ids

    /// The bug this suite exists to prevent recurring.
    ///
    /// `init(rawValue:)` is non-failable by design — an installed set's id must be
    /// storable by a build that has never heard of it. That makes
    /// `ImageSetID(rawValue: stored) ?? .defaultSet` dead code, and it shipped:
    /// with no stored preference it yielded `ImageSetID("")`, which matched no
    /// card in onboarding, was persisted as an empty string, and left the
    /// resolver on Classic while the UI implied Medium-Dark — so a word added on
    /// Medium-Dark was generated in Classic.
    @Test func unresolvableStoredIDsFallBackToTheDefault() {
        #expect(ImageSetID.resolved(nil) == .defaultSet)
        #expect(ImageSetID.resolved("") == .defaultSet)
        #expect(ImageSetID.resolved("a_set_this_build_removed") == .defaultSet)
        // A resolvable id is passed through untouched.
        #expect(ImageSetID.resolved("classic_medium_dark") == .classicMediumDark)
        #expect(ImageSetID.resolved("playful_3d") == .playful3D)
    }

    /// `resolved` must never be used for stored ART, only for the active-set
    /// preference: a variant generated for an installed set has to keep pointing
    /// at that set, or reinstalling the set would not bring the art back.
    @Test func variantKeepsItsOwnSetIDEvenWhenUnknown() {
        let v = TileArtVariant(tileKey: "eat",
                               imageSet: ImageSetID("khmer_core"),
                               imageData: Data())
        #expect(v.imageSet.rawValue == "khmer_core")
        #expect(v.imageSet != .defaultSet)
    }

    @Test func tileScriptResolvesToneSetsAndAliases() {
        #expect(TileScriptParser.parseImageSet("classic_medium") == .classicMedium)
        // Display name (em-dash and all) and the frozen slug both resolve — they
        // deliberately differ, since the labels are relative to this palette
        // while the slugs record the Fitzpatrick steps the sets were built from.
        #expect(TileScriptParser.parseImageSet("Classic — Dark") == .classicMediumDark)
        #expect(TileScriptParser.parseImageSet("classic_medium_dark") == .classicMediumDark)
        #expect(TileScriptParser.parseImageSet("clsmd") == .classicMediumDark)
        #expect(TileScriptParser.parseImageSet("p3d") == .playful3D)
        #expect(TileScriptParser.parseImageSet("hc") == .highContrast)
        // An unknown set is nil, not a silent substitution.
        #expect(TileScriptParser.parseImageSet("no_such_set") == nil)
    }

    @Test func everySelectableSetIsShippableInRelease() {
        #if !DEBUG
        #expect(ImageSetCatalog.selectable.allSatisfy(\.isShippable))
        #endif
        #expect(!ImageSetCatalog.selectable.isEmpty)
    }
}
}
