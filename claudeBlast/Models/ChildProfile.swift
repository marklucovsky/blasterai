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
/// Whether the message box shows a chip's picture. A profile setting
/// (`ChildProfile.trayPictures`), so it follows whoever is talking.
enum TrayPictures: String, CaseIterable, Identifiable {
    /// The child's stage decides: pictures through Stage II-III, words at IV+.
    case auto
    case pictures
    /// Words only.
    case words

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Follow Stage"
        case .pictures: "Pictures and Words"
        case .words: "Words Only"
        }
    }

    /// The device-wide value earlier builds stored, read once as the
    /// starting point for a profile that has never chosen.
    static func legacyDeviceValue(_ defaults: UserDefaults = .standard) -> TrayPictures {
        defaults.string(forKey: AppSettingsKey.trayPictures).flatMap(TrayPictures.init(rawValue:)) ?? .auto
    }
}

/// What a profile does with AI on the board. The device's AI switch
/// (`AIConsent`) is the master gate; this is the profile's own choice under it.
///
/// One string-backed field rather than two Bools: the schema is promoted, so a
/// field is permanent from the day it ships, and an enum can grow a state a
/// Bool never could. Same rule as `brownsStageRaw`.
enum ProfileAIMode: String, CaseIterable, Identifiable {
    /// No AI for this profile, whatever the device allows.
    case off
    /// AI allowed, the message box speaks each word as it is tapped.
    case on
    /// AI allowed, and the words in the message box become a sentence.
    case sentences

    var id: String { rawValue }
}

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

    /// Whether a tray chip carries its picture, or just the word.
    ///
    /// **Brandi, reviewing the board:** in the more advanced mode the tray
    /// should show the display name without the tile image.
    ///
    /// The reasoning is developmental rather than cosmetic. At Stages I-III the
    /// tray is the child's own feedback loop — *these are the ones I pressed* —
    /// and it has to be readable by someone who is not yet reading, so it echoes
    /// the pictures back. A Stage IV+ child is building sentences with
    /// embedding and coordination, and for them the tray is a sentence under
    /// construction: the words matter, and a row of pictures is a slower way to
    /// read the same thing. The picture has already done its job on the board.
    ///
    /// It also buys room. The same chip without its picture fits far more of a
    /// long word, and Stage IV+ is exactly where the caregiver chooses how many
    /// tiles a sentence may hold.
    ///
    /// **Derived, never stored** — the rule this whole axis exists to enforce.
    /// Three separate knobs were removed to get here; a fourth would be a
    /// setting that can disagree with the stage it was supposed to follow.
    var showsPicturesInTray: Bool {
        switch self {
        case .one, .twoThree: return true
        case .fourPlus: return false
        }
    }

    /// Plain-language description for a caregiver who has never heard of Roger
    /// Brown. Deliberately describes the *child*, not the app's behavior — the
    /// caregiver is picking where their child is, not picking a feature.
    var detail: String {
        switch self {
        case .one:
            return "Uses one word at a time. Each tile speaks its own word."
        case .twoThree:
            return "Putting two and three words together."
        case .fourPlus:
            return "Building longer sentences."
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
            return "Starts with each tap speaking its own word, pictures in the message box."
        case .twoThree:
            return "Starts with pictures in the message box and 4 words per message if you turn on AI sentences."
        case .fourPlus:
            return "Starts with words only in the message box and 5 words per message if you turn on AI sentences."
        }
    }

    /// Whether this stage's sentence-building depends on an OpenAI key.
    ///
    /// Without one the app falls back to a mock provider, which answers with
    /// placeholder text rather than failing — usable for a demo, useless for a
    /// child. Worth saying out loud before someone picks a stage they cannot
    /// yet run.
    ///
    /// No stage turns AI sentences on by itself any more (Mark 2026-11-15), so
    /// no stage needs a key to be picked.
    var requiresAPIKey: Bool { false }

    /// How tile taps turn into communication at this stage. Stage I is single
    /// words by definition; every later stage is building sentences.
    var interactionMode: InteractionMode {
        self == .one ? .singleWord : .sentence
    }

    /// The words per message a profile starts with at this stage. A starting
    /// point, not a rule (Mark 2026-11-15): every stage can choose anything in
    /// `ChildProfile.wordsPerMessageRange`, and Reset to Stage Defaults puts
    /// this back.
    var defaultWordsPerMessage: Int {
        self == .fourPlus ? 5 : 4
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
    ///
    /// The text lives in `Resources/Prompts/prompt_stages.json`, keyed by raw
    /// value with "/escalating" for the insisting variant. Stage I never
    /// reaches the model — single-word mode makes no API call — but has an
    /// entry so the value is total.
    func promptDescriptor(escalating: Bool = false) -> String {
        PromptTemplate.stages[rawValue + (escalating ? "/escalating" : "")] ?? ""
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
    /// This child's part-of-speech → color overrides, as JSON.
    /// **Empty means the Fitzgerald default**, which is where every profile
    /// starts.
    ///
    /// ## Why the child and not the device
    ///
    /// There is a precedent pulling the other way: the **image set is a device
    /// setting**. A child can run Classic Light while her therapist's iPad runs
    /// Classic Dark, and nobody set that per child — the choice is static and the
    /// control is five rows, so a device-level setting somebody sets once was the
    /// better trade.
    ///
    /// A color map breaks both halves of that argument. It is eleven mappings
    /// rather than a pick from five, and it is a fact about **how this child
    /// sees** rather than a rendering preference. A child with cortical visual
    /// impairment often has one reliably-perceived color and reduced
    /// discrimination generally, so several of the eight Fitzgerald hues collapse
    /// into each other for them — and a board whose color system the child
    /// cannot see teaches nothing while looking like it does. That has to be true
    /// on every device the child touches.
    ///
    /// ## Sparse, and a map rather than eleven fields
    ///
    /// Only what the therapist changed is stored, so the default palette stays in
    /// code and can be improved later without rewriting anyone's data. One String
    /// rather than eleven color fields because the palette is an *artifact* a
    /// therapist builds, names and sends to a family — the same move scenes and
    /// vocabulary packs already made — and because eleven synced fields could
    /// never be reshaped after promotion, where a JSON blob can.
    ///
    /// Taken as schema insurance on the now-proven precedent: a synced property
    /// can be added before CloudKit promotion and never after.
    /// `CD_partOfSpeechRaw` was confirmed present in the Development schema on
    /// 2026-09-05 having never been written a non-empty value, which is the
    /// defaulted-property rule working exactly as `SchemaVersions` claims.
    var colorMapData: String = ""

    /// The caregiver's saved color palettes, as a JSON array of `TileColorMap`.
    ///
    /// **Lives on the system profile**, which is the caregiver's own record —
    /// the one auto-seeded on every device with a stable shared id, currently
    /// called Sandbox. A library belongs to the person building palettes, not to
    /// any one child: the whole point is reuse across children, and the person
    /// who can build a good CVI palette is rarely the person holding the device
    /// it needs to be on.
    ///
    /// Synced, deliberately. A therapist's scenes, palettes and packs should
    /// travel wherever their iCloud does — Mark, 2026-09-07 — so the iPad they
    /// configure on and the iPhone they carry show the same library.
    ///
    /// Empty means no saved palettes. Same schema-insurance reasoning as
    /// `colorMapData`: a synced property can be added before promotion and never
    /// after, and where the library ultimately *lives* can still change, since
    /// the system profile survives the rename to Caregiver unmoved.
    var colorMapLibrary: String = ""

    /// How page links take their color: `LinkColorMode.rawValue`.
    ///
    /// **Defaults to `alwaysWayfinding` — one blue for every folder.**
    ///
    /// Not because it is better. Destination colouring is the more informative
    /// default on screen, and the reason it is not the default is that the
    /// person who has to teach with it preferred the blue. Brandi, reviewing
    /// the board: *"I like the blue links and I think that could work well for
    /// a light-tech flip book option later down the road."* A colour key is
    /// worth exactly what the clinician using it thinks it is worth, and this
    /// is the first release any clinician has seen.
    ///
    /// Both are one tap apart, and the per-child setting is the whole point:
    /// whichever way this lands for one child, the other is still there. Revisit
    /// once there is feedback from more than one SLP — her stated reason was a
    /// printed flip book, which may mean the answer differs between paper and
    /// screen rather than being one answer at all.
    /// The other two are blunt instruments on purpose — `alwaysWayfinding` for
    /// a caregiver who needs every folder to shout, `alwaysAuto` for one who has
    /// been handed a shared scene whose hand-picked colors they do not want.
    ///
    /// **A string-backed enum rather than a Bool, and that is not style.** This
    /// lands after CloudKit promotion, so the property is permanent from the day
    /// it ships and a Bool that later wanted a third state could never grow one.
    /// Same rule as `brownsStageRaw` and `roleRaw`.
    ///
    /// Render-time only. It changes which color is looked up and never what a
    /// link stores, so switching it back restores exactly the board that was
    /// there before — see `TileEntry.linkColor` for why a stored color must not
    /// move on its own.
    var linkColorModeRaw: String = LinkColorMode.standard.rawValue

    var linkColorMode: LinkColorMode {
        get { LinkColorMode(rawValue: linkColorModeRaw) ?? .standard }
        set { linkColorModeRaw = newValue.rawValue }
    }

    /// `ProfileAIMode` raw value. Empty on a profile written before build 11,
    /// which keeps doing what its stage did then: sentences from Stage II-III
    /// up, single words at Stage I. Read `aiMode`.
    var aiModeRaw: String = ""

    /// `TrayPictures` raw value; empty means `.auto`, the stage's answer.
    /// Read `trayPictures`.
    var trayPicturesRaw: String = ""

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
        self.maxSelectedTiles = Self.clampWords(maxSelectedTiles ?? brownsStage.defaultWordsPerMessage)
        // A new profile starts with AI allowed and sentences off, at every
        // stage (Mark 2026-11-15). Turning sentences on is a deliberate step.
        self.aiModeRaw = ProfileAIMode.on.rawValue
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
    /// Writing it changes nothing else: the stage is an input to the
    /// defaults (`applyStageDefaults`), not a rule over the other settings.
    var brownsStage: BrownsStage {
        get { BrownsStage(rawValue: brownsStageRaw) ?? .one }
        set {
            brownsStageRaw = newValue.rawValue
            modifiedAt = .now
        }
    }

    // MARK: - AI and the message box

    /// What this profile does with AI. See `aiModeRaw` for the empty case.
    var aiMode: ProfileAIMode {
        get {
            ProfileAIMode(rawValue: aiModeRaw)
                ?? (brownsStage.interactionMode == .sentence ? .sentences : .on)
        }
        set {
            aiModeRaw = newValue.rawValue
            modifiedAt = .now
        }
    }

    /// How this profile's taps become a message: a sentence when it has AI
    /// sentences on, otherwise each word on its own. Whether the device can
    /// make sentences at all is the engine's question, not this one.
    var interactionMode: InteractionMode { aiMode == .sentences ? .sentence : .singleWord }

    /// How many words a sentence is built from, when sentences are on.
    static let wordsPerMessageRange = 4...8

    static func clampWords(_ n: Int) -> Int {
        min(wordsPerMessageRange.upperBound, max(wordsPerMessageRange.lowerBound, n))
    }

    /// Words per message in force. Read this rather than `maxSelectedTiles`,
    /// which may hold a count an earlier build allowed (Stage I stored 1).
    var wordsPerMessage: Int {
        get { Self.clampWords(maxSelectedTiles) }
        set {
            maxSelectedTiles = Self.clampWords(newValue)
            modifiedAt = .now
        }
    }

    /// Pictures in the message box. Empty `trayPicturesRaw` is `.auto`.
    var trayPictures: TrayPictures {
        get { TrayPictures(rawValue: trayPicturesRaw) ?? .auto }
        set {
            trayPicturesRaw = newValue == .auto ? "" : newValue.rawValue
            modifiedAt = .now
        }
    }

    /// Whether the settings the stage starts are what this profile has.
    var matchesStageDefaults: Bool {
        aiMode == .on && wordsPerMessage == brownsStage.defaultWordsPerMessage
            && trayPictures == .auto
    }

    /// The stage's starting point for the settings the stage decides: words
    /// per message and pictures. AI is left alone.
    func applyStageDefaults() {
        maxSelectedTiles = brownsStage.defaultWordsPerMessage
        trayPicturesRaw = ""
        modifiedAt = .now
    }

    /// Everything back to how a new profile at this stage starts: AI on,
    /// sentences off, and the stage's words and pictures.
    func resetToStageDefaults() {
        aiModeRaw = ProfileAIMode.on.rawValue
        applyStageDefaults()
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
