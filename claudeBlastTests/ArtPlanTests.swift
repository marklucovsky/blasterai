// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ArtPlanTests.swift
//  claudeBlastTests
//
//  What calls a new word's art costs, and when. The variability here — how many
//  styles, how far down a tone scale, whether a transform runs at all — is what
//  made this worth extracting into a pure function: every case below is a
//  question that was previously only answerable by adding a word and looking.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ArtPlanTests {

    /// Calls the plan implies, as the assertion the call-count questions reduce
    /// to: one generation per style, one transform per variant below the base,
    /// and one vision check per style that has any transform to protect.
    private func calls(_ plan: [PlannedStyle]) -> (generations: Int, transforms: Int, checks: Int) {
        (plan.count,
         plan.reduce(0) { $0 + $1.transforms.count },
         plan.filter(\.needsSkinCheck).count)
    }

    // MARK: - Just my own style (the default)

    /// The default caregiver on Classic — Light: one image, and nothing else at
    /// all. No transform to run, so no vision check to pay for either.
    @Test func lightWithTheToggleOffIsOneImageAndNoOtherCalls() {
        let plan = ArtPlan.plan(activeSet: .classic, allStyles: false)
        #expect(plan.map(\.setIDs) == [[.classic]])
        #expect(calls(plan) == (generations: 1, transforms: 0, checks: 0))
    }

    /// Medium stops at Medium: the base it derives from, itself, and no Dark —
    /// a call she never asked for.
    @Test func mediumStopsAtMedium() {
        let plan = ArtPlan.plan(activeSet: .classicMedium, allStyles: false)
        #expect(plan.map(\.setIDs) == [[.classic, .classicMedium]])
        #expect(calls(plan) == (generations: 1, transforms: 1, checks: 1))
    }

    /// Dark needs the whole chain, because each variant is transformed from the
    /// one above it — there is no way to reach Dark without Medium.
    @Test func darkWalksTheWholeChain() {
        let plan = ArtPlan.plan(activeSet: .classicMediumDark, allStyles: false)
        #expect(plan.map(\.setIDs) == [[.classic, .classicMedium, .classicMediumDark]])
        #expect(calls(plan) == (generations: 1, transforms: 2, checks: 1))
    }

    /// A single-variant style has no transform to protect, so it must not pay for
    /// a vision check. Adding a word on High Contrast is one call, full stop.
    @Test func singleVariantStylesNeverPayForASkinCheck() {
        for set in [ImageSetID.highContrast, .playful3D] {
            let plan = ArtPlan.plan(activeSet: set, allStyles: false)
            #expect(plan.map(\.setIDs) == [[set]])
            #expect(calls(plan) == (generations: 1, transforms: 0, checks: 0))
        }
    }

    // MARK: - Generate all styles

    /// "In all styles, make sure all variants exist" — so every style completes,
    /// including the one the caregiver is on.
    ///
    /// This is the bug the extraction exists to prevent: three call sites each
    /// computed their own depth, and the shipped version applied the active-set
    /// limit here too. Playful 3D and High Contrast filled completely while
    /// Classic sat half-populated at whichever tone was active. Asserting on
    /// `activeSet: .classic` specifically, since Light is where it looked most
    /// correct and was most wrong.
    @Test func allStylesCompletesEveryStyleIncludingTheActiveOne() {
        for active in [ImageSetID.classic, .classicMedium, .classicMediumDark] {
            let plan = ArtPlan.plan(activeSet: active, allStyles: true)
            let sets = Set(ArtPlan.expectedSets(plan))
            #expect(sets == Set(ImageSetCatalog.generationTargets.flatMap(\.setIDs)),
                    "all-styles from \(active.rawValue) left a style incomplete")
            #expect(calls(plan) == (generations: 3, transforms: 2, checks: 1))
        }
    }

    /// The caregiver's own style comes first so their board fills in before the
    /// styles they aren't looking at.
    @Test func theActiveStyleIsPlannedFirst() {
        let plan = ArtPlan.plan(activeSet: .highContrast, allStyles: true)
        #expect(plan.first?.style.id == "high_contrast_v2")
        // And its base is still its own base, not the active set as such.
        #expect(plan.first?.base.id == .highContrast)
    }

    // MARK: - Invariants

    /// Every plan starts at a base. A plan whose first entry were a mid-scale
    /// variant would transform from art that was never drawn.
    @Test func everyPlannedStyleStartsAtItsBase() {
        for allStyles in [true, false] {
            for set in ImageSetCatalog.all.map(\.id) {
                for planned in ArtPlan.plan(activeSet: set, allStyles: allStyles) {
                    #expect(planned.base.isStyleBase)
                    #expect(planned.base.id == planned.style.base.id)
                    #expect(planned.variants.map(\.variantIndex)
                            == Array(0..<planned.variants.count))
                }
            }
        }
    }

    /// A set this build cannot resolve must not silently plan another set's art.
    @Test func anUnknownActiveSetPlansNothing() {
        #expect(ArtPlan.plan(activeSet: ImageSetID("khmer_core"), allStyles: false).isEmpty)
        // With all styles on, the unknown set simply doesn't reorder anything.
        let plan = ArtPlan.plan(activeSet: ImageSetID("khmer_core"), allStyles: true)
        #expect(Set(ArtPlan.expectedSets(plan))
                == Set(ImageSetCatalog.generationTargets.flatMap(\.setIDs)))
    }

    /// Turning the setting on never costs less than leaving it off — the cheapest
    /// possible statement of "on means more coverage, not different coverage".
    @Test func allStylesIsAlwaysASupersetOfTheDefault() {
        for set in ImageSetCatalog.generationTargets.flatMap(\.setIDs) {
            let off = Set(ArtPlan.expectedSets(ArtPlan.plan(activeSet: set, allStyles: false)))
            let on = Set(ArtPlan.expectedSets(ArtPlan.plan(activeSet: set, allStyles: true)))
            #expect(off.isSubset(of: on), "\(set.rawValue): turning the setting on lost coverage")
            #expect(on.contains(set), "\(set.rawValue): all-styles skipped the caregiver's own set")
        }
    }
}
}
