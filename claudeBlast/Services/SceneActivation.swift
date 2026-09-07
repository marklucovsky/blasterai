// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneActivation.swift
//  claudeBlast
//
//  What a scene must be before it is allowed to become the child's board.
//

import Foundation
import SwiftData

/// Checks a scene before it goes live, and says what it did.
///
/// ## Why this exists
///
/// Two lockouts inside an hour on an iPad mini (`docs/s4-cleanup.md` §9): a
/// hand-built scene whose `homePageKey` named no page, and an imported one whose
/// pages had been emptied by an export bug. Both drew no board — and Admin is
/// reached by long-pressing Home, which lives *on* the board, so there was no way
/// back in short of deleting the app.
///
/// Those are patched: the empty state now carries **Open Admin**, the `pages`
/// setter and `activate` hold the home-page invariant, and an empty page still
/// draws its Home cell. **That is containment, not a fix** — nothing stopped a
/// scene in a known-bad state going live, and nothing told the caregiver why
/// their board looked wrong.
///
/// ## The rule
///
/// **Repair what is unambiguous, refuse what is not, and never silently do
/// either.** The last clause is the one that was missing: `activate` already
/// repaired a dangling home page, quietly, and every call site says `try?`, so
/// even a thrown error went nowhere.
///
/// Refusal is deliberately narrow. Now that an empty board is survivable, the
/// only genuinely unusable state is a scene with **no pages at all** — there is
/// nothing to adopt as home and nothing to draw. Everything else is a warning
/// the caregiver can act on, because a half-built scene is a normal thing to
/// have mid-edit and refusing it would strand them.
enum SceneActivation {

    /// A change made to the scene so it could be activated.
    enum Repair: Equatable {
        /// `homePageKey` named no page; the first page adopted it.
        case adoptedHomePage(String)

        var message: String {
            switch self {
            case .adoptedHomePage(let key):
                return "This scene had no home page, so “\(key)” is now the page it opens on."
            }
        }
    }

    /// Something true of the scene that the caregiver should know, but which
    /// does not stop it being used.
    enum Warning: Equatable {
        /// No page holds a word the child can press.
        case noReachableWords
        /// Pages naming words this device does not have. The signature of the
        /// export bug in §9 — populated in the editor, empty on the board.
        case missingWords([String])

        var message: String {
            switch self {
            case .noReachableWords:
                return "No page in this scene has a word the child can press. "
                     + "The board will be empty until you add some."
            case .missingWords(let keys):
                let sample = keys.prefix(3).joined(separator: ", ")
                let extra = keys.count > 3 ? " and \(keys.count - 3) more" : ""
                return "\(keys.count) word\(keys.count == 1 ? "" : "s") on this board "
                     + "(\(sample)\(extra)) are not on this device, so those tiles will be blank."
            }
        }
    }

    /// Why a scene cannot be activated at all.
    enum Refusal: LocalizedError, Equatable {
        case noPages

        var errorDescription: String? {
            switch self {
            case .noPages:
                return "This scene has no pages yet, so there is nothing to show. "
                     + "Add a page before making it active."
            }
        }
    }

    /// What activation did. Carried back to the caller so it can be shown —
    /// a repair nobody is told about is the thing §9 set out to stop.
    struct Outcome: Equatable {
        var repairs: [Repair] = []
        var warnings: [Warning] = []

        var isClean: Bool { repairs.isEmpty && warnings.isEmpty }

        /// One caregiver-facing paragraph, or nil when there is nothing to say.
        var message: String? {
            let lines = repairs.map(\.message) + warnings.map(\.message)
            return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
        }
    }

    /// Inspect a scene. Throws only when it genuinely cannot be shown.
    ///
    /// `vocabulary` is the set of keys this device actually has. Passing an
    /// empty set skips the word checks rather than reporting every word missing,
    /// which is what a caller with no context should get.
    static func check(_ scene: BlasterScene, vocabulary: Set<String>) throws -> Outcome {
        let pages = scene.pages
        guard !pages.isEmpty else { throw Refusal.noPages }

        var outcome = Outcome()

        // Unambiguous repair: pages exist, so one of them can be home.
        if !pages.contains(where: { $0.key == scene.homePageKey }), let first = pages.first {
            outcome.repairs.append(.adoptedHomePage(first.key))
        }

        // Spacers are not words and never count toward vocabulary — a page of
        // gaps is as empty as a page of nothing.
        let placements = pages.flatMap(\.tiles).filter { !$0.isSpacer && $0.link.isEmpty }

        if !vocabulary.isEmpty {
            let missing = placements.map(\.key).filter { !vocabulary.contains($0) }
            if !missing.isEmpty {
                var seen = Set<String>()
                outcome.warnings.append(.missingWords(missing.filter { seen.insert($0).inserted }))
            }
        }

        // Reachable means: a word, present on this device, not concealed here.
        let reachable = placements.contains { entry in
            !entry.isConcealed && (vocabulary.isEmpty || vocabulary.contains(entry.key))
        }
        if !reachable { outcome.warnings.append(.noReachableWords) }

        return outcome
    }
}
