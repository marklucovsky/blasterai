// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoverageReport.swift
//  claudeBlast
//
//  How much of a scene a child actually reaches, by part of speech.
//

import Foundation

/// Coverage of one scene: what is on it, what got used, what never did.
///
/// ## The unit is a SCENE, not a page
///
/// A scene's whole vocabulary, across every page in it. Not a page, because a
/// page is a shelf rather than a vocabulary — the same word sits on several,
/// and a child who reaches a word from Home has reached it. `Board` is
/// deliberately absent from this file: in OBF and CoughDrop a board IS one
/// page, so using it for a scene reintroduces exactly the ambiguity that
/// naming settled.
///
/// ## Scoped to one scene, never summed across them
///
/// A figure across every scene a child has would climb whenever a caregiver
/// adds a good one — a coverage number that gets worse the more vocabulary you
/// provide is measuring the wrong thing. Topic scenes are reported beside the
/// everyday one, not added to it: a Farm Visit scene at 9-of-24 means the outing
/// happened once, not that the child is stuck.
///
/// ## Part of speech, not `wordClass`
///
/// `wordClass` answers the sentence generator's question — is `snack_bar` a
/// place or a food — and is injected into the prompt to settle exactly that.
/// This asks something else entirely, for a different reader: does this scene
/// carry question words, and has she ever pressed one. The two axes do not
/// derive from each other (see `PartOfSpeech`).
struct CoverageReport {

    /// One part of speech in this scene.
    struct CategoryCoverage: Identifiable, Equatable {
        let partOfSpeech: PartOfSpeech
        /// Distinct words of this kind the child used.
        let used: Int
        /// Distinct words of this kind the scene carries.
        let available: Int
        /// The words themselves, sorted, and which of them were reached.
        ///
        /// Carried so a row can be opened rather than only counted. A percentage
        /// says a kind is underused; the words say WHICH, and that is the part a
        /// therapist can act on.
        var keys: [String] = []
        var usedKeys: Set<String> = []

        var id: String { partOfSpeech.rawValue }
        var label: String { partOfSpeech.label }
        var neverUsed: Int { available - used }

        /// Share used, 0–1. Zero available reads as zero rather than dividing.
        var usedFraction: Double {
            available > 0 ? Double(used) / Double(available) : 0
        }

        /// Share never used, 0–1.
        ///
        /// Kept alongside `usedFraction` because the two answer different
        /// questions and the screen shows the positive one. Ranking on a SHARE
        /// rather than a count is the part that matters either way: a raw tally
        /// puts the largest category first every time, which is a fact about the
        /// scene rather than about the child. Seven question words untouched out
        /// of seven is the finding; a hundred unused adjectives out of six
        /// hundred is arithmetic.
        var neverUsedFraction: Double {
            available > 0 ? Double(neverUsed) / Double(available) : 0
        }
    }

    /// One page in the scene.
    ///
    /// ## Where the numbers come from
    ///
    /// `LoggedUtterance.pageKeys` records the page each tile was pressed on, at
    /// the press — the referrer. So a page's `used` is genuinely "words pressed
    /// while on this page", not an inference.
    ///
    /// Rows written before that existed carry no pages, and those presses are
    /// counted in `unattributedPresses` rather than guessed at. The tempting
    /// guess — credit every page a used word appears on — is worse than useless
    /// here: a buried page stocked with core words that also sit on Home would
    /// score as well-used, because those words were pressed on Home. An SLP
    /// tuning that page would be reading an artefact, which is the one job this
    /// section has.
    ///
    /// A separate shape from `CategoryCoverage`, because these rows do not
    /// partition the scene the way part-of-speech rows nearly do: a word on
    /// three pages is available on all three, so `available` totals more than
    /// the scene. One shared type would invite someone to sum a mixed list.
    struct PageCoverage: Identifiable, Equatable {
        let pageKey: String
        /// Words on this page that were pressed while on this page.
        let used: Int
        /// Vocabulary words the page carries.
        let available: Int
        /// The page's words **in page order**, and which were reached.
        ///
        /// Order matters here in a way it does not for a part of speech: laid
        /// out as the child sees them, an untouched bottom row or right-hand
        /// column reads as a reaching problem rather than a vocabulary one.
        var keys: [String] = []
        var usedKeys: Set<String> = []

        var id: String { pageKey }
        var neverUsed: Int { available - used }
        var usedFraction: Double {
            available > 0 ? Double(used) / Double(available) : 0
        }
        var neverUsedFraction: Double {
            available > 0 ? Double(neverUsed) / Double(available) : 0
        }
    }

    struct WordCount: Identifiable, Equatable {
        let key: String
        let count: Int
        var id: String { key }
    }

    let sceneName: String
    /// Vocabulary words in the scene — page links excluded.
    let sceneWordCount: Int
    /// Distinct scene words used in the window.
    let usedCount: Int

    /// Coverage per part of speech, in `PartOfSpeech.display` order, omitting
    /// kinds the scene does not carry at all. A row reading "0 of 0" is noise;
    /// the absence of a kind is a scene-authoring question, not a usage one.
    let coverage: [CategoryCoverage]

    /// Scene words the part-of-speech index cannot classify — words a therapist
    /// added, which the static table does not know.
    ///
    /// Surfaced rather than dropped. Silently excluding them would make the
    /// coverage rows fail to add up to the scene, and on a heavily customised
    /// scene they could be most of it.
    let unclassifiedCount: Int

    let mostUsed: [WordCount]

    /// Used before this window and not in it.
    ///
    /// The short, actionable half of "not used": a word that was working and
    /// stopped is a different finding from one never taken up, and it is the one
    /// a therapist does something about.
    let wentQuiet: [String]

    /// Utilisation by kind, most-used first.
    ///
    /// Stated as "how much of this kind gets used" rather than "how much never
    /// does". Same numbers, and the positive form is the one that reads: a full
    /// ring means good, and `Questions — 0% used` lands as a finding where
    /// `Questions — 100% never pressed` takes a beat to parse.
    ///
    /// Fully-used kinds are kept, unlike before. Once the column reads as
    /// utilisation, a kind at 100% is a result rather than an empty row.
    let usageByKind: [CategoryCoverage]

    /// Utilisation by page, most-used first.
    ///
    /// The layout question rather than the language one. A page at 12% usually
    /// means it is buried behind a link nobody presses, not that its words are
    /// wrong — and a page at 0% is the sharpest row on the screen.
    let usageByPage: [PageCoverage]

    /// Presses in the record that predate page attribution.
    ///
    /// While this is large the page rows understate use, and they say so. It
    /// falls to zero as new history accumulates, which is the honest shape: the
    /// answer improves rather than being fabricated in the meantime.
    let unattributedPresses: Int

    /// Distinct words said in the window that are not in this scene.
    ///
    /// Reported so the numbers reconcile. Without it a caregiver comparing this
    /// screen to the utterance count finds a gap and no explanation for it.
    let offSceneWordCount: Int

    var neverUsedCount: Int { sceneWordCount - allTimeUsedCount }

    /// Share of the scene ever pressed, 0–1 — the headline figure.
    var usedFraction: Double {
        sceneWordCount > 0 ? Double(allTimeUsedCount) / Double(sceneWordCount) : 0
    }
    /// Distinct scene words used at any time — the denominator "never used"
    /// subtracts from, which is all-time rather than windowed on purpose: a word
    /// used last month has been used.
    let allTimeUsedCount: Int

    var neverUsedFraction: Double {
        sceneWordCount > 0 ? Double(neverUsedCount) / Double(sceneWordCount) : 0
    }
}

extension CoverageReport {

    /// A scene's vocabulary: every tile key across its pages, page links removed.
    ///
    /// Links are chrome, not words. A `body_health` tile is a door to a page;
    /// counting it as vocabulary inflates the scene and puts a word the child
    /// cannot say into "never used". Order is page order, deduplicated — a word
    /// on three pages is one word.
    static func vocabularyKeys(of pages: [PageSpec]) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for page in pages {
            for tile in page.tiles where tile.link.isEmpty {
                if seen.insert(tile.key).inserted { keys.append(tile.key) }
            }
        }
        return keys
    }

    /// Build the report.
    ///
    /// - Parameters:
    ///   - inWindow: utterances inside the window being reported.
    ///   - allTime: every utterance, for the two questions that are not about
    ///     the window — what was never used, and what went quiet.
    static func make(sceneName: String,
                     pages: [PageSpec],
                     inWindow: [LoggedUtterance],
                     allTime: [LoggedUtterance],
                     mostUsedLimit: Int = 5,
                     wentQuietLimit: Int = 12) -> CoverageReport {

        let scene = Set(vocabularyKeys(of: pages))

        var windowCounts: [String: Int] = [:]
        for entry in inWindow {
            for key in Set(entry.tileKeys) { windowCounts[key, default: 0] += 1 }
        }
        let usedInWindow = Set(windowCounts.keys).intersection(scene)
        let usedEverKeys = Set(allTime.flatMap(\.tileKeys)).intersection(scene)

        // Coverage counts DISTINCT words, not presses. "24 of 108" is how much of
        // the scene she reaches; how often she reaches for each is `mostUsed`.
        var coverage: [CategoryCoverage] = []
        for pos in PartOfSpeech.display {
            let available = scene.filter { PartOfSpeechIndex.partOfSpeech(for: $0) == pos }
            guard !available.isEmpty else { continue }
            let reached = available.filter { usedInWindow.contains($0) }
            coverage.append(CategoryCoverage(
                partOfSpeech: pos,
                used: reached.count,
                available: available.count,
                keys: available.sorted(),
                usedKeys: Set(reached)
            ))
        }

        let classified = scene.filter { PartOfSpeechIndex.partOfSpeech(for: $0) != nil }

        // Never-used is measured all-time, so its rows use a different `used`
        // than the windowed coverage above. Same shape, different question.
        let usageByKind = coverage.map { row in
            let available = scene.filter {
                PartOfSpeechIndex.partOfSpeech(for: $0) == row.partOfSpeech
            }
            let reached = available.filter { usedEverKeys.contains($0) }
            return CategoryCoverage(
                partOfSpeech: row.partOfSpeech,
                used: reached.count,
                available: available.count,
                keys: available.sorted(),
                usedKeys: Set(reached)
            )
        }
        // Most-used first, and fully-used kinds are KEPT. Filtering them out was
        // right while the column meant "never used" — a zero row there said
        // nothing — but read as utilisation a 100% row is a result, and dropping
        // it would make the list silently incomplete.
        //
        // Descending reads as a ranking, which is what a percentage column
        // invites: strongest at the top, and the 0% rows collect together at the
        // bottom where "nothing here is being used" is one glance rather than a
        // scan down the list.
        .sorted {
            if $0.usedFraction != $1.usedFraction {
                return $0.usedFraction > $1.usedFraction
            }
            return $0.available > $1.available
        }

        let mostUsed = windowCounts
            .filter { scene.contains($0.key) }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(mostUsedLimit)
            .map { WordCount(key: $0.key, count: $0.value) }

        let wentQuiet = usedEverKeys
            .subtracting(usedInWindow)
            .sorted()
            .prefix(wentQuietLimit)
            .map { $0 }

        // Presses credited to the page they were made on. Only utterances that
        // recorded one contribute; the rest are counted, not guessed.
        var pressedOnPage: [String: Set<String>] = [:]
        var unattributed = 0
        for entry in allTime {
            for (index, key) in entry.tileKeys.enumerated() {
                let page = index < entry.pageKeys.count ? entry.pageKeys[index] : ""
                if page.isEmpty {
                    unattributed += 1
                } else {
                    pressedOnPage[page, default: []].insert(key)
                }
            }
        }

        // A page with no vocabulary contributes nothing rather than a 0-of-0
        // row: it is navigation, and has nothing to reach.
        let usageByPage = pages.compactMap { page -> PageCoverage? in
            // Page order, deduplicated — the order the child sees.
            var seen = Set<String>()
            let ordered = page.tiles
                .filter { $0.link.isEmpty }
                .map(\.key)
                .filter { seen.insert($0).inserted }
            guard !ordered.isEmpty else { return nil }
            let reached = Set(ordered).intersection(pressedOnPage[page.key] ?? [])
            return PageCoverage(
                pageKey: page.key,
                used: reached.count,
                available: ordered.count,
                keys: ordered,
                usedKeys: reached
            )
        }
        .sorted {
            if $0.usedFraction != $1.usedFraction {
                return $0.usedFraction > $1.usedFraction
            }
            return $0.available > $1.available
        }

        return CoverageReport(
            sceneName: sceneName,
            sceneWordCount: scene.count,
            usedCount: usedInWindow.count,
            coverage: coverage,
            unclassifiedCount: scene.count - classified.count,
            mostUsed: Array(mostUsed),
            wentQuiet: Array(wentQuiet),
            usageByKind: usageByKind,
            usageByPage: usageByPage,
            unattributedPresses: unattributed,
            offSceneWordCount: Set(windowCounts.keys).subtracting(scene).count,
            allTimeUsedCount: usedEverKeys.count
        )
    }
}
