// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ArtPlan.swift
//  claudeBlast
//
//  What art to make for one new word, decided in exactly one place.
//

import Foundation

/// One style's share of the work: the picture to draw, then the variants to
/// transform it into, in the order the transforms must run.
struct PlannedStyle: Equatable, Sendable {
    let style: TileStyle
    /// Base first, then each variant to produce from the one before it.
    let variants: [ImageSetDescriptor]

    var base: ImageSetDescriptor { variants[0] }
    var transforms: [ImageSetDescriptor] { Array(variants.dropFirst()) }
    var setIDs: [ImageSetID] { variants.map(\.id) }

    /// Whether this style needs the "is there a person in this?" vision check.
    ///
    /// Only when there is something to transform. A single-variant style, or a
    /// style stopped at its own base, has no transform to protect and must not
    /// pay for a check — adding a word on High Contrast, or on Classic — Light,
    /// makes one image and no other calls at all.
    var needsSkinCheck: Bool { !transforms.isEmpty }
}

/// How many styles, and how deep into each, a new word's art covers.
///
/// ## Why this is a type and not three lines at the call site
///
/// It *was* three lines at the call site, in three call sites, and the
/// duplication broke immediately: each one computed its own
/// `allStyles ? nil : activeSet`, and the version that shipped passed the active
/// set unconditionally. "Generate all styles" then filled Playful 3D and High
/// Contrast completely while stopping Classic at whichever tone the caregiver
/// happened to be on — every style complete except the one they were looking at.
///
/// The decision has real variability in it (how many styles, how far down a tone
/// scale, whether a transform runs at all), which is exactly why it should be one
/// pure function that can be asserted against rather than a conditional repeated
/// wherever art gets made.
enum ArtPlan {
    /// The work for one word.
    ///
    /// - `activeSet`: the set the caregiver is actually looking at.
    /// - `allStyles`: the "Generate all styles" setting.
    ///
    /// **Off** covers the active set's style, stopping at the active variant:
    /// someone on Medium needs Medium and the base it derives from, and Dark is a
    /// call they never asked for. **On** covers every generatable style,
    /// completely — "in all styles, make sure all variants exist" — so it must
    /// *not* also stop at the active variant.
    static func plan(activeSet: ImageSetID, allStyles: Bool) -> [PlannedStyle] {
        let styles = allStyles
            ? ImageSetCatalog.generationTargets(preferring: activeSet)
            : [ImageSetCatalog.style(for: activeSet)].compactMap { $0 }
        // Depth is the caregiver's own variant only when this is their own style
        // and only when they didn't ask for everything.
        let stop: ImageSetID? = allStyles ? nil : activeSet
        return styles.compactMap { style in
            let variants = style.variants(upTo: stop)
            guard !variants.isEmpty else { return nil }
            return PlannedStyle(style: style, variants: variants)
        }
    }

    /// Every set the plan should end up filling — what a caller compares results
    /// against to name what is missing.
    static func expectedSets(_ plan: [PlannedStyle]) -> [ImageSetID] {
        plan.flatMap(\.setIDs)
    }
}
