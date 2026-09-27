// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LinkColorResolver.swift
//  claudeBlast
//
//  What color a folder should be, worked out from what is behind it.
//

import Foundation

/// Picks a `TileColorSlot` for a page link by looking at the page it opens.
///
/// ## Why the destination and not the word on the tile
///
/// The obvious rule — color the folder by the part of speech of its own word —
/// does not work, and the board says so. Of our twelve top-level folders,
/// `people`, `places`, `social`, `time`, `actions`, `groups` and `keyboard` are
/// all nouns, so seven of twelve would be orange: less information than the one
/// blue they replaced. Worse, it is actively misleading where it matters most —
/// `actions` is a noun that opens a page of verbs, and `describe` is a verb that
/// opens a page of adjectives.
///
/// The destination tells the truth: a folder of doing words should look like
/// doing words, because that is the convention an SLP already reads.
///
/// ## Why raw counts do not work either, and what replaces them
///
/// Nouns are 36% of the vocabulary and will dominate any page by sheer count —
/// fringe vocabulary is numerous, which is most of what makes it fringe. On the
/// `people` page a plain count gives noun 14, pronoun 9, so the folder comes out
/// orange when every published board colors it for pronouns.
///
/// So each part of speech's share of the page is divided by its share of the
/// whole vocabulary, and the largest ratio wins. Pronouns are 37.5% of that page
/// against 3.2% of the vocabulary — a lift of 11.7 — while nouns are 58% against
/// 36%, a lift of 1.6. Pronouns win by a wide margin rather than a whisker.
///
/// This was reached from Mark's suggestion of weighting nouns down. It is that
/// idea with the constant removed: the background distribution *is* the weight,
/// it calibrates itself from the data, and it keeps working as the vocabulary
/// grows — which it will, with packs planned.
///
/// ## The two guards, and what each one caught
///
/// **A share floor.** Undiluted lift is wildly unstable at small counts: a
/// single `when` on the Time page, against question words being 1.3% of the
/// vocabulary, out-lifted fourteen adjectives and painted Time purple. Anything
/// under `minimumShare` of the page is not what the page is about.
///
/// **A minimum sample.** The `keyboard` page holds one placeholder tile, and one
/// noun is not evidence of anything. Under `minimumWords`, the answer is
/// wayfinding.
///
/// ## Folders of folders
///
/// A page that is mostly links has no part of speech at all, so `groups` and
/// `keyboard` resolve to `.wayfinding`. That is not a special case bolted on: it
/// is the original argument for the blue — *"wayfinding rather than
/// vocabulary"* — turning out to be right for a narrow class of page rather than
/// for all of them.
///
/// ## Two implementations, and why that is safe
///
/// `tools/resolve_link_colors.py` runs this same algorithm offline, because the
/// bundled board's colors are resolved once and committed rather than computed
/// on device. Two implementations of one rule is a drift risk, so neither is
/// trusted on its own: the tool's `--check` mode fails when the committed JSON
/// disagrees with what Python computes, and `LinkColorResolverTests` fails when
/// it disagrees with what Swift computes. Both are pinned to the same committed
/// artifact, so a divergence cannot pass quietly.
enum LinkColorResolver {

    /// A part of speech below this share of the destination page is noise.
    ///
    /// 0.15 rather than a majority: `people` is legitimately 37.5% pronouns and
    /// nothing there holds 50%, so requiring a majority would fall back to
    /// wayfinding on exactly the pages this is meant to color.
    static let minimumShare = 0.15

    /// Fewer real words than this and the page is not evidence of anything.
    static let minimumWords = 4

    /// Resolve one link.
    ///
    /// - Parameters:
    ///   - destination: the tiles on the page the link opens.
    ///   - partOfSpeech: a word key's part of speech, or nil when unknown.
    ///     Unknown words are excluded rather than bucketed, since "we could not
    ///     identify it" is not a category a color should stand for.
    ///   - background: how often each part of speech occurs across the whole
    ///     vocabulary — the denominator that turns a count into a lift.
    static func slot(forDestination destination: [TileEntry],
                     partOfSpeech: (String) -> PartOfSpeech?,
                     background: [PartOfSpeech: Int]) -> TileColorSlot {

        // Spacers are holes, not tiles, and must not dilute the page.
        let real = destination.filter { !$0.isSpacer }
        let links = real.filter { !$0.link.isEmpty }
        let words = real.filter { $0.link.isEmpty }

        // A page of folders is wayfinding, whatever the few words on it say.
        guard links.count <= words.count else { return .wayfinding }

        var counts: [PartOfSpeech: Int] = [:]
        for word in words {
            guard let part = partOfSpeech(word.key) else { continue }
            counts[part, default: 0] += 1
        }

        let total = counts.values.reduce(0, +)
        guard total >= minimumWords else { return .wayfinding }

        let backgroundTotal = background.values.reduce(0, +)
        guard backgroundTotal > 0 else { return .wayfinding }

        // Written out rather than chained: the fluent version of this was a
        // filter/map/sorted over tuples, which the type checker took an
        // unreasonable time over.
        var ranked: [(part: PartOfSpeech, lift: Double)] = []
        for (part, count) in counts {
            let onPage = Double(count) / Double(total)
            guard onPage >= minimumShare else { continue }
            // A part of speech absent from the vocabulary cannot be the
            // denominator; treat it as one occurrence rather than divide by
            // zero. It cannot arise from bundled data and must not crash.
            let occurrences = max(background[part] ?? 1, 1)
            let overall = Double(occurrences) / Double(backgroundTotal)
            ranked.append((part, onPage / overall))
        }

        // Sort by lift, then by raw name, so a tie resolves the same way on
        // every run and in both implementations. Dictionary iteration order is
        // not stable and a committed color must not depend on it.
        ranked.sort { left, right in
            left.lift == right.lift
                ? left.part.rawValue < right.part.rawValue
                : left.lift > right.lift
        }

        guard let winner = ranked.first else { return .wayfinding }
        return .partOfSpeech(winner.part)
    }

    /// Background distribution over a vocabulary listing.
    static func background(for keys: [String],
                           partOfSpeech: (String) -> PartOfSpeech?) -> [PartOfSpeech: Int] {
        var counts: [PartOfSpeech: Int] = [:]
        for key in keys {
            guard let part = partOfSpeech(key) else { continue }
            counts[part, default: 0] += 1
        }
        return counts
    }
}
