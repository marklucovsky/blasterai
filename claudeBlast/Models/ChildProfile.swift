// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfile.swift
//  claudeBlast
//

import SwiftData
import Foundation
import AVFoundation

/// Brown's Stages of syntactic development — the axis this app tunes itself to.
///
/// ## Why this and not age
///
/// The sentence prompt used to say the child had "the grammar and vocabulary of
/// a {grade} student", where grade was derived from a stored date of birth. That
/// assumes age predicts expressive language level, which is false by definition
/// for an AAC user — a ten-year-old may be at Stage I and a four-year-old at
/// Stage IV. It also overshot in practice. Brown's Stages are age-independent,
/// clinically standard, and a far more precise instruction to a model: each one
/// names a mean utterance length and a morpheme inventory.
///
/// Removing the age derivation is what let `ChildProfile.birthday` be deleted
/// outright rather than merely ignored — see the type's own documentation.
///
/// ## One control, not three
///
/// This is deliberately the *single* stored axis for how a child communicates.
/// It replaced three separate caregiver knobs that were really one:
/// `interactionModeRaw` (sentence vs. single-word), the tile-count stepper, and
/// the birthday-derived grade. Stage I *is* single-word mode; Stage II-III *is*
/// a four-tile cap; Stage IV+ is where you already are once a caregiver widens
/// past four. None of the three meant anything to a speech-language pathologist.
/// One stage does.
enum BrownsStage: String, CaseIterable, Identifiable {
    /// MLU ~1.0-2.0. Single words, no grammatical morphemes. Classic AAC:
    /// each tile speaks its own word. **No AI call is made at this stage.**
    case one = "I"
    /// MLU ~2.0-3.0. Two- and three-word combinations; the first grammatical
    /// morphemes appear (present progressive -ing, in/on, regular plural -s).
    case twoThree = "II-III"
    /// MLU 3.0+. Longer sentences with embedding and coordination; irregular
    /// past, possessives, articles, contractible copula.
    case fourPlus = "IV+"

    var id: String { rawValue }

    var label: String { "Stage \(rawValue)" }

    /// Plain-language description for a caregiver who has never heard of Roger
    /// Brown. Deliberately describes the *child*, not the app's behavior — the
    /// caregiver is picking where their child is, not picking a feature.
    var detail: String {
        switch self {
        case .one:
            return "Uses one word at a time. Each tile speaks its own word."
        case .twoThree:
            return "Putting two and three words together. Up to 4 tiles per sentence."
        case .fourPlus:
            return "Building longer sentences. You choose how many tiles."
        }
    }

    /// What the *app* does at this stage.
    ///
    /// Kept separate from `detail` on purpose. `detail` describes the child, so
    /// a caregiver picking a stage is answering a question about their child
    /// rather than choosing a feature — but having answered it, they deserve to
    /// know what they just turned on. Two sentences, two jobs.
    var appBehavior: String {
        switch self {
        case .one:
            return "Classic AAC: each tap speaks its own word. No AI, and no key needed."
        case .twoThree:
            return "AI turns up to 4 tiles into a spoken sentence. Needs an OpenAI key."
        case .fourPlus:
            return "AI builds longer sentences from the tiles you allow. Needs an OpenAI key."
        }
    }

    /// Whether this stage's sentence-building depends on an OpenAI key.
    ///
    /// Without one the app falls back to a mock provider, which answers with
    /// placeholder text rather than failing — usable for a demo, useless for a
    /// child. Worth saying out loud before someone picks a stage they cannot
    /// yet run.
    var requiresAPIKey: Bool { self != .one }

    /// How tile taps turn into communication at this stage. Stage I is single
    /// words by definition; every later stage is building sentences.
    var interactionMode: InteractionMode {
        self == .one ? .singleWord : .sentence
    }

    /// Tile counts this stage permits. Fixed for I and II-III, because the
    /// count *is* part of what the stage means. Only IV+ is a real choice,
    /// which is why it is the only stage that shows the caregiver a stepper.
    var tileCapRange: ClosedRange<Int> {
        switch self {
        case .one:      return 1...1
        case .twoThree: return 4...4
        case .fourPlus: return 5...8
        }
    }

    /// True when the caregiver has a number to pick. See `tileCapRange`.
    var allowsTileCapChoice: Bool { self == .fourPlus }

    /// The stage that a given tile cap implies. This is the "caregiver strays"
    /// rule: widening past four tiles *is* moving to Stage IV+, so the setting
    /// can never end up describing something the child isn't doing.
    static func implied(byTileCap cap: Int) -> BrownsStage {
        switch cap {
        case ...1:  return .one
        case 2...4: return .twoThree
        default:    return .fourPlus
        }
    }

    /// The developmental target handed to the sentence prompt in place of the
    /// old "{grade} student" phrasing. Names an MLU and a morpheme inventory,
    /// which is a far more actionable instruction than a school grade.
    ///
    /// `escalating` drops the **length** ceiling while keeping the vocabulary
    /// and grammar level. See the discussion on
    /// `SentencePromptBuilder.escalationPrompt`: a repeat tap means the child
    /// means it *more*, and the only way a text-to-speech device conveys that
    /// audibly today is with more insistent words. Live eval ladders showed the
    /// brevity clause winning at deep rungs — "I NEED TO GO HOME NOW!!!"
    /// collapsing back to "I want to GO HOME!" — because a rule stated
    /// absolutely in the system prompt outranks an exemption mentioned later.
    /// So the exemption is applied here, where the rule itself is written.
    func promptDescriptor(escalating: Bool = false) -> String {
        switch self {
        case .one:
            // Stage I never reaches the model — single-word mode makes no API
            // call — but the descriptor exists so the value is total.
            return "at Brown's Stage I: single words, mean utterance length 1.0-2.0, " +
                   "no grammatical morphemes"
        case .twoThree:
            let base = "at Brown's Stage II-III: mean utterance length 2.0-3.0, two- and " +
                       "three-word combinations, early grammatical morphemes only (present " +
                       "progressive -ing, the prepositions in and on, regular plural -s)"
            return escalating
                ? base + ". They are insisting right now, so this sentence may be longer " +
                         "and more forceful than their usual level — keep the words simple, " +
                         "but do not shorten it back down"
                : base + ". Keep sentences short and concrete; do not use complex clauses"
        case .fourPlus:
            return "at Brown's Stage IV or later: mean utterance length above 3.0, " +
                   "full simple sentences with embedding and coordination, including " +
                   "irregular past tense, possessives, articles and contractible copula"
        }
    }
}

/// How the child's tile taps turn into communication.
///
/// **Derived, never stored.** This is a projection of `BrownsStage` (Stage I is
/// single words; every later stage builds sentences), optionally overridden for
/// the current device — see `DeviceProfile.singleWordOverride`. It was a stored
/// field on `ChildProfile` until 2026-08-24, which meant a caregiver flipping
/// modes for one afternoon's session silently rewrote the child's profile on
/// every synced device.
enum InteractionMode: String, CaseIterable, Identifiable {
    /// Tiles accumulate into a group; AI builds a sentence (the default).
    case sentence
    /// Classic AAC: each tile speaks its own word on tap and appends to a
    /// running FIFO strip. No AI, no sentence — good for ABC/123/new-word
    /// boards and for demoing AI vs. classic side by side on one device.
    case singleWord

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sentence:   return "AI Sentences"
        case .singleWord: return "Single Words"
        }
    }

    var detail: String {
        switch self {
        case .sentence:   return "Tiles combine into an AI-generated sentence."
        case .singleWord: return "Each tile speaks its word; words build a strip. No AI."
        }
    }
}

/// Per-child identity. Syncs via CloudKit when iCloud is enabled, so a
/// therapist's roster appears across their own devices.
///
/// ## No date of birth, deliberately
///
/// This model stored a `birthday` until 2026-08-24. It existed for exactly one
/// reason — to derive a US grade level for the sentence prompt — and
/// `BrownsStage` replaced that derivation with a better one. A child's date of
/// birth is the most sensitive field this app could hold: with a name attached
/// it is a large fraction of an identity kit, and it is the first thing a
/// school district or clinic asks about. Keeping one to power a feature we had
/// just removed would have been indefensible, so it went.
///
/// The removal had a deadline. A promoted CloudKit schema is additive-only
/// forever, so a field can only be deleted *before* promotion. Ours had not
/// promoted (session 1 deferred it), which made this free — and impossible a
/// session later. See `docs/final-countdown-plan.md` gate 9.
///
/// What remains is still not anonymous: `displayName` is a child's name and
/// `notes` is caregiver free text. Onboarding says a nickname is fine.
@Model
final class ChildProfile {
    /// String, not UUID — matches the project convention (TileModel, BlasterScene)
    /// and keeps SwiftData+CloudKit happy without `@Attribute(.unique)`.
    var id: String = UUID().uuidString
    var displayName: String = ""
    /// AVSpeechSynthesisVoice identifier. Empty = system default.
    var voiceIdentifier: String = ""
    /// How many tiles may be selected at once. **Constrained by `brownsStage`**
    /// — read `effectiveTileCap` rather than this, which is the raw stored
    /// number and is only meaningful at Stage IV+. Stages I and II-III pin the
    /// count (1 and 4), because the count is part of what those stages mean.
    ///
    /// Writing a value above 4 promotes the stage to IV+ via `setTileCap(_:)`,
    /// so the stage can never disagree with the number the caregiver picked.
    var maxSelectedTiles: Int = 4
    /// AVSpeechUtterance rate. 0.5 ≈ AVSpeechUtteranceDefaultSpeechRate on iOS.
    var ttsRate: Float = 0.5
    /// AVSpeechUtterance volume. 0.0–1.0.
    var ttsVolume: Float = 1.0
    /// BCP-47 language tag for this child's board and generated sentences.
    /// Empty ⇒ unspecified ⇒ English.
    ///
    /// **Inert on arrival — nothing reads this yet.** It exists now because the
    /// synced schema becomes additive-only the moment it is promoted to
    /// Production CloudKit, and a defaulted `String` costs two lines today
    /// versus a new field plus a backfill of build-1 testers' records later.
    /// See `docs/localization-impact.md` §7.2 and `docs/final-countdown-plan.md`
    /// gate 8.
    ///
    /// Note that scene-level language needs no field at all: `BlasterScene`
    /// stores its pages as inline JSON, so per-page and per-tile language
    /// tagging can be added at any time at zero promotion cost.
    var languageRaw: String = ""
    /// Brown's Stage of syntactic development for this child. Raw values
    /// `"I"`, `"II-III"`, `"IV+"`; the typed accessor and its enum arrive in 3E.
    ///
    /// **Inert on arrival**, for the same reason as `languageRaw`. It becomes
    /// load-bearing in 3E, where it replaces the age→grade derivation that
    /// currently drives the sentence prompt — Brown's Stages are age-independent
    /// and clinically standard, which matters because age does not predict
    /// expressive language level for an AAC user.
    ///
    /// Defaults to a **real** stage rather than an empty "unset" sentinel.
    /// There is no pre-existing data to distinguish from a deliberate choice:
    /// all devices are wiped before first use (decided 2026-08-24), so every
    /// profile that will ever exist is created after the stage selector does.
    /// Stage I is the right floor — it is where an AAC user starts.
    ///
    /// Once 3E lands this is the **single source of truth** for how the child
    /// communicates, and `interactionMode` becomes a projection of it: Stage I
    /// *is* single-word mode, Stage II-III and IV+ *are* sentence mode.
    var brownsStageRaw: String = "I"
    /// BlasterScene.name to land on at app launch / session-revert.
    /// Empty = honor the device's currently-active scene.
    var defaultSceneKey: String = ""
    /// Therapist-only notes. Never fed to the prompt.
    var notes: String = ""
    /// Hint only — `ChildProfileResolver` resolves the true active profile
    /// using a deterministic tiebreaker (most-recently-modified wins) to
    /// survive CloudKit races where two devices both set isActive.
    var isActive: Bool = false
    /// True for the per-device Sandbox profile — the always-present
    /// fallback the resolver returns when no real child is active. Created
    /// by `ProfileMigration.ensureProfilesAfterBootstrap` and visible (but
    /// undeletable) in the Admin Profiles list.
    var isSystem: Bool = false
    var createdAt: Date = Date.now
    /// Bumped on every mutation. Drives the resolver's tiebreaker.
    var modifiedAt: Date = Date.now

    init(displayName: String, brownsStage: BrownsStage = .one,
         voiceIdentifier: String = "", maxSelectedTiles: Int? = nil,
         defaultSceneKey: String = "", notes: String = "",
         isActive: Bool = false, isSystem: Bool = false) {
        self.displayName = displayName
        self.brownsStageRaw = brownsStage.rawValue
        self.voiceIdentifier = voiceIdentifier
        // Default the cap from the stage rather than hardcoding 4, so a
        // caller that names only a stage gets a coherent pair. An explicit
        // value is clamped into the stage's range.
        self.maxSelectedTiles = min(brownsStage.tileCapRange.upperBound,
                                    max(brownsStage.tileCapRange.lowerBound,
                                        maxSelectedTiles ?? brownsStage.tileCapRange.lowerBound))
        self.defaultSceneKey = defaultSceneKey
        self.notes = notes
        self.isActive = isActive
        self.isSystem = isSystem
    }

    // MARK: - Derived getters

    /// Typed accessor over `brownsStageRaw`. Unknown raw values fall back to
    /// Stage I — the floor, and the safe direction to fail: a child shown one
    /// word at a time is under-served, whereas one handed Stage IV+ sentences
    /// they cannot parse is being spoken *for* rather than *with*.
    ///
    /// Writing also reconciles `maxSelectedTiles`, so the stored count can
    /// never contradict the stage.
    var brownsStage: BrownsStage {
        get { BrownsStage(rawValue: brownsStageRaw) ?? .one }
        set {
            brownsStageRaw = newValue.rawValue
            maxSelectedTiles = clampTileCap(maxSelectedTiles, to: newValue)
            modifiedAt = .now
        }
    }

    /// How this child's taps become communication. Derived from the stage —
    /// there is no stored interaction mode. A *device* may temporarily override
    /// this to single words (`DeviceProfile.singleWordOverride`); that override
    /// is applied by `ChildProfileResolver`, not here, because it is a fact
    /// about the device rather than about the child.
    var interactionMode: InteractionMode { brownsStage.interactionMode }

    /// The tile cap actually in force: the stage's fixed count at Stage I and
    /// II-III, and the caregiver's stored choice (clamped) at Stage IV+.
    /// Read this rather than `maxSelectedTiles`.
    var effectiveTileCap: Int {
        clampTileCap(maxSelectedTiles, to: brownsStage)
    }

    // MARK: - Stage / tile-cap reconciliation

    /// Set the tile cap, promoting the stage when the caregiver widens past
    /// what the current stage allows.
    ///
    /// This is the "let the caregiver stray" rule. Someone who moves a Stage
    /// II-III child to six tiles is telling us something clinical — that the
    /// child is combining more than three words — so the stage follows the
    /// number rather than fighting it. The reverse holds too: narrowing to one
    /// tile is Stage I.
    func setTileCap(_ cap: Int) {
        let implied = BrownsStage.implied(byTileCap: cap)
        if implied != brownsStage {
            brownsStageRaw = implied.rawValue
        }
        maxSelectedTiles = clampTileCap(cap, to: implied)
        modifiedAt = .now
    }

    private func clampTileCap(_ cap: Int, to stage: BrownsStage) -> Int {
        min(stage.tileCapRange.upperBound, max(stage.tileCapRange.lowerBound, cap))
    }

    // MARK: - Active resolution

    /// Pure function used by `ChildProfileResolver` (commit 3) and tests.
    /// Picks the canonical active profile from a candidate list, surviving
    /// CloudKit races where two devices both set `isActive = true`.
    ///
    /// Resolution:
    /// 1. If exactly one is active, return it.
    /// 2. If multiple are active, prefer the most-recently-modified;
    ///    deterministic tiebreaker by lowest `id` lexicographically.
    /// 3. If none are active, return nil.
    static func resolveActive(from candidates: [ChildProfile]) -> ChildProfile? {
        let active = candidates.filter { $0.isActive }
        guard !active.isEmpty else { return nil }
        if active.count == 1 { return active[0] }
        return active.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.id < rhs.id
        }.first
    }
}
