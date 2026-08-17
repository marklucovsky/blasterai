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
            stylePromptKey: "classic", styleName: "Classic",
            toneTarget: nil, variantIndex: 0)
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

    /// A set on the tone scale without a target cannot recolour a new word, so a
    /// caregiver's added word would arrive as the only light-skinned figure in
    /// their set — the exact absence these sets exist to remove.
    ///
    /// The **base** carries one too: a step names where it is coming from as well
    /// as where it is going, and without the origin the model has no idea the
    /// tones form an ordered scale.
    @Test func everySetOnTheToneScaleDeclaresATarget() {
        for id in [ImageSetID.classic, .classicMedium, .classicMediumDark] {
            #expect(id.toneTarget != nil, "\(id.displayName) has no tone target")
        }
        // Skin tone is not a property of white-on-black silhouettes.
        #expect(ImageSetID.highContrast.toneTarget == nil)
    }

    /// The scale must actually descend. A target that is lighter than the step
    /// above it is how the offline build first failed — dark came back sometimes
    /// *lighter* than medium-dark — and it is invisible without this check.
    @Test func toneTargetsDarkenMonotonically() {
        for style in ImageSetCatalog.styles {
            for (previous, variant) in zip(style.variants, style.variants.dropFirst()) {
                guard let target = variant.toneTarget,
                      let origin = previous.toneTarget else { continue }
                #expect(target.red < origin.red && target.green < origin.green
                        && target.blue < origin.blue,
                        "\(variant.displayName) is not darker than \(previous.displayName)")
            }
        }
    }

    /// Blue as a fraction of red is what separates a brown that reads as skin
    /// from one that reads as rust — the model crushed blue to less than half its
    /// target on the first offline pilot and produced terracotta. The prompt pins
    /// the ratio, so the values themselves have to be in a plausible band.
    @Test func toneTargetsAreSkinNotTerracotta() {
        for set in ImageSetCatalog.all {
            guard let t = set.toneTarget else { continue }
            #expect((35...75).contains(t.bluePercent),
                    "\(set.displayName) blue is \(t.bluePercent)% of red — not a skin tone")
            #expect((60...90).contains(t.greenPercent),
                    "\(set.displayName) green is \(t.greenPercent)% of red")
        }
    }

    // MARK: - Styles

    /// A style is the unit art is generated in, so every set must belong to
    /// exactly one. A set left out of the grouping can never receive a new word:
    /// nothing would ever name it as a generation target.
    @Test func stylesCoverEverySet() {
        let grouped = ImageSetCatalog.styles.flatMap(\.setIDs)
        #expect(Set(grouped) == Set(ImageSetCatalog.all.map(\.id)))
        #expect(grouped.count == ImageSetCatalog.all.count, "a set appears in two styles")
    }

    /// Classic is one style with three variants, in scale order. This is the
    /// whole point of the model: Light, Medium and Dark are not three sets that
    /// resemble each other, they are one picture and two transforms of it.
    @Test func classicIsOneStyleWithThreeVariants() {
        let classic = ImageSetCatalog.style(for: .classic)
        #expect(classic?.id == "classic")
        #expect(classic?.setIDs == [.classic, .classicMedium, .classicMediumDark])
        #expect(classic?.base.id == .classic)
        // Every variant resolves to the same style, whichever one you ask from.
        #expect(ImageSetCatalog.style(for: .classicMediumDark) == classic)
    }

    /// A style with one variant is not a special case — it is the same loop with
    /// zero transforms. If Playful 3D ever gains tones it slots in unchanged.
    @Test func singleVariantStylesAreOrdinary() {
        for id in [ImageSetID.playful3D, .highContrast] {
            let style = ImageSetCatalog.style(for: id)
            #expect(style?.variants.count == 1)
            #expect(style?.base.id == id)
        }
    }

    /// `TileStyle.base` subscripts `variants[0]`, so the first variant must be
    /// the base. A style whose sets all claimed index 1 would otherwise transform
    /// from art that was never generated.
    @Test func everyStyleStartsAtItsBase() {
        for style in ImageSetCatalog.styles {
            #expect(style.base.isStyleBase, "\(style.id) has no base variant")
            #expect(style.variants.map(\.variantIndex) == Array(0..<style.variants.count),
                    "\(style.id) has a gap or duplicate in its variant order")
        }
    }

    /// A style's variants must agree on the family's name, since `styleName` is
    /// copied per set rather than derived.
    @Test func styleNamesAgreeWithinAStyle() {
        for style in ImageSetCatalog.styles {
            let names = Set(style.variants.map(\.styleName))
            #expect(names.count == 1, "\(style.id) variants disagree on styleName: \(names)")
            #expect(style.displayName == style.base.styleName)
        }
        #expect(ImageSetCatalog.style(for: .classicMediumDark)?.displayName == "Classic")
    }

    // MARK: - Generation depth

    /// Stopping at the active variant is a **prefix**, never a subset: each
    /// variant is transformed from the one above it, so Dark cannot exist without
    /// Medium. A caregiver on Medium pays for Light and Medium and nothing else.
    @Test func variantsStopAtTheActiveOne() {
        let classic = ImageSetCatalog.style(for: .classic)!
        #expect(classic.variants(upTo: .classic).map(\.id) == [.classic])
        #expect(classic.variants(upTo: .classicMedium).map(\.id) == [.classic, .classicMedium])
        #expect(classic.variants(upTo: .classicMediumDark).map(\.id)
                == [.classic, .classicMedium, .classicMediumDark])
    }

    /// A stop that isn't in this style means the caregiver is looking at some
    /// other style, so there is no variant of theirs to stop at — complete it.
    /// This is what "Generate all styles" relies on for the styles you're not on.
    @Test func aStopFromAnotherStyleCompletesThisOne() {
        let classic = ImageSetCatalog.style(for: .classic)!
        #expect(classic.variants(upTo: .playful3D).map(\.id) == classic.setIDs)
        #expect(classic.variants(upTo: nil).map(\.id) == classic.setIDs)
        // Single-variant styles are unaffected either way.
        let p3d = ImageSetCatalog.style(for: .playful3D)!
        #expect(p3d.variants(upTo: .classicMedium).map(\.id) == [.playful3D])
    }

    /// High Contrast ships and has a style prompt, so "Generate all styles" must
    /// include it. It was excluded while the set was incomplete, and leaving that
    /// stale meant the toggle silently skipped it — the Contrast slot just stayed
    /// empty with no error.
    @Test func everyShippableStyleIsAGenerationTarget() {
        let targets = Set(ImageSetCatalog.generationTargets.flatMap(\.setIDs))
        for set in ImageSetCatalog.all where set.isShippable {
            #expect(targets.contains(set.id),
                    "\(set.displayName) ships but 'generate all styles' skips it")
        }
    }


    // MARK: - Defaults

    @Test func defaultAndBackfillAreClassic() {
        #expect(ImageSetID.defaultSet == .classic)
        #expect(ImageSetID.universalBackfill == .classic)
        // The backfill covers gaps in every other set, so it must be complete.
        #expect(ImageSetCatalog.descriptor(for: .universalBackfill)?.isShippable == true)
    }

    /// Preferring a *variant* must put its whole style first, not the variant —
    /// a caregiver on Dark should see their own board fill in first, and their
    /// board's art cannot be generated without the two variants above it.
    @Test func generationTargetsPutThePreferredStyleFirst() {
        let ordered = ImageSetCatalog.generationTargets(preferring: .classicMediumDark)
        #expect(ordered.first?.id == "classic")
        #expect(Set(ordered) == Set(ImageSetCatalog.generationTargets))
        // High Contrast IS a generation target now. This assertion previously
        // said the opposite, encoding the state from when the set was incomplete
        // and unshippable — which is exactly why "Generate all styles" left the
        // Contrast slot empty with no error. It ships and has a style prompt, so
        // it generates; `everyShippableStyleIsAGenerationTarget` guards the rule.
        #expect(ImageSetCatalog.generationTargets.flatMap(\.setIDs).contains(.highContrast))
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
