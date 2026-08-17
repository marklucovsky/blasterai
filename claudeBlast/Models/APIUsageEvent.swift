// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  APIUsageEvent.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// What caused an OpenAI call — the dimension the reporting is actually built on.
///
/// The *endpoint* can't answer "what did scene generation cost me": five of our
/// features share `/v1/chat/completions`. Nor can the *service*: a plain
/// sentence, an escalated re-generation, and a caregiver refine all run through
/// `OpenAISentenceProvider` and mean entirely different things to a caregiver
/// reading the report.
///
/// Stored as a String raw value, matching `MetricEvent.eventTypeRaw` /
/// `ChildProfile.interactionModeRaw`. Unknown values decode to `.unknown` so a
/// row written by a newer build degrades instead of failing.
enum UsageCause: String, Codable, CaseIterable {
    // Child-facing — the hot path.
    case sentenceGenerate
    /// The child repeated a combination to insist harder. Broken out because
    /// escalation deliberately bypasses the cache, so it is pure API spend.
    case sentenceEscalate
    /// Caregiver-initiated re-generation with an instruction.
    case sentenceRefine

    // Authoring — caregiver-triggered, large prompts.
    case sceneGenerate
    case sceneRefine
    case pageGenerate
    case pageRefine
    case tileSuggest

    // Art — expected to dominate total spend.
    case tileImageGenerate
    /// Iterative art refinement. Hits `/v1/images/edits` (image-to-image, so the
    /// result builds on the previous image) — named for what the caregiver did,
    /// not the endpoint, matching `sceneRefine` / `pageRefine` / `sentenceRefine`.
    case tileImageRefine
    /// The vision check that decides whether a new picture even *has* skin to
    /// recolour. Pennies against the art it gates, but recorded so a run's call
    /// count adds up: one of these precedes every multi-variant style.
    case tileArtClassify

    // MARK: Word audit — the "add a word" safety path
    //
    // Adding a word (say "shotgun") runs `WordModerationService.audit`, which
    // makes TWO API calls per batch and therefore writes two rows. Tier 1 (the
    // offline blocklist) costs nothing and makes no call, so it never appears
    // here. `detail` carries how many words the batch covered — `audit` takes an
    // array, so one add-word action of six words is still one row of each.

    /// Tier 3 — the gpt-4o-mini age-appropriateness rubric. **The primary gate**,
    /// and the only part of the word audit that costs money.
    case wordAuditRubric
    /// Tier 2 — `/v1/moderations` policy screen. Free, but recorded so the call
    /// volume behind an add-word is visible rather than invisible.
    case wordAuditScreen

    /// `/v1/models` key check — free.
    case keyValidation

    case unknown

    /// Caregiver-facing label for the Activity report.
    var label: String {
        switch self {
        case .sentenceGenerate:  return "Sentences"
        case .sentenceEscalate:  return "Escalations"
        case .sentenceRefine:    return "Sentence refines"
        case .sceneGenerate:     return "Scene generation"
        case .sceneRefine:       return "Scene refines"
        case .pageGenerate:      return "Page generation"
        case .pageRefine:        return "Page refines"
        case .tileSuggest:       return "Word suggestions"
        case .tileImageGenerate: return "Tile art"
        case .tileImageRefine:   return "Art refines"
        case .tileArtClassify:   return "Art checks"
        case .wordAuditRubric:   return "Word review"
        case .wordAuditScreen:   return "Word safety screen"
        case .keyValidation:     return "Key checks"
        case .unknown:           return "Other"
        }
    }

    /// Endpoints OpenAI does not bill for, known by construction rather than
    /// inferred from the price table.
    ///
    /// Declaring it here also covers `keyValidation`, whose `/v1/models` response
    /// names no model at all — so a price lookup can say nothing useful about it
    /// and it would otherwise fall through to a "$0.00" that was accidental
    /// rather than informed.
    var isFreeEndpoint: Bool {
        switch self {
        case .wordAuditScreen, .keyValidation: return true
        default: return false
        }
    }

    /// Whether this cause is part of the child *talking*, as opposed to a
    /// caregiver authoring the board. The distinction the GTM claim turns on:
    /// talking is fractions of a cent; authoring is where the money goes.
    var isChildSpeech: Bool {
        switch self {
        case .sentenceGenerate, .sentenceEscalate, .sentenceRefine: return true
        default: return false
        }
    }
}

/// One OpenAI API call: what it was for, what it consumed, what it cost.
///
/// **Device-local** — lives in the `DeviceLocal` ModelConfiguration
/// (`cloudKitDatabase: .none`), never CloudKit. Spend is incurred by *this*
/// device against *this* device's API key, which is also the more correct
/// meaning, and it matches the reasoning already applied to `MetricEvent`.
/// Because it never enters the CloudKit schema, this model is free to evolve
/// without the additive-only constraints that bind the synced models.
///
/// ## Cost is computed at write time, and never recomputed
///
/// `costMicros` is calculated from `ModelPricing` at the moment of the call and
/// stored. Prices change; a historical row must keep the dollars it actually
/// incurred, so the price table never needs to carry history and reports never
/// re-price the past. `priceTableAsOf` records which snapshot of the table
/// produced the figure, so a stale-table period stays identifiable after the fact.
///
/// ## Token fields across the two billing shapes
///
/// Chat and image endpoints both report `usage`, but price different parts of
/// it at different rates. The fields are named for the *role* the tokens play,
/// and `ModelPricing` decides the rate from `model`:
///
/// - **Chat** (`gpt-4o-mini`): `promptTokens` at the input rate, of which
///   `cachedPromptTokens` gets the cached discount; `completionTokens` at the
///   output rate. `imageInputTokens` is 0.
/// - **Images** (`gpt-image-1`): `promptTokens` is total input, of which
///   `imageInputTokens` is the image portion (billed higher than text — the
///   remainder is text input); `completionTokens` is the generated-image output,
///   which is by far the most expensive rate we pay. `cachedPromptTokens` is 0.
@Model
final class APIUsageEvent {
    var id: String = UUID().uuidString
    var timestamp: Date = Date.now

    /// `UsageCause.rawValue`. See `cause` for the typed accessor.
    var causeRaw: String = UsageCause.unknown.rawValue

    /// Free-text qualifier for the parameter that distinguishes otherwise
    /// identical causes — most importantly the **image set** for art generation,
    /// which is how "art for the active set" vs "art for a set we don't ship"
    /// gets answered without a combinatorial enum. Empty when not applicable.
    var detail: String = ""

    /// The model id as reported by the API response, not as requested — so a
    /// silent server-side model substitution shows up in the ledger rather than
    /// being priced as something it wasn't.
    var model: String = ""

    /// API path the call went to — `/v1/chat/completions`, `/v1/images/generations`,
    /// `/v1/images/edits`, `/v1/moderations`, `/v1/models`. Redundant with `cause`
    /// today, and deliberately so: it's the axis **OpenAI's own usage dashboard
    /// breaks down by**, so having it recorded is what makes our totals
    /// reconcilable against theirs line-for-line rather than only in aggregate.
    /// Also future-proofs the ledger against a cause being served by a different
    /// endpoint later. Surfaced in the line-item detail view only.
    var endpoint: String = ""

    // MARK: - Consumption

    var promptTokens: Int = 0
    /// Portion of `promptTokens` served from OpenAI's prompt cache at a discount.
    /// Chat only; 0 for images.
    var cachedPromptTokens: Int = 0
    /// Portion of `promptTokens` that is image input (a higher rate than text).
    /// Images only; 0 for chat.
    var imageInputTokens: Int = 0
    var completionTokens: Int = 0
    /// Images returned. 0 for text calls. Kept alongside tokens because "3 new
    /// images" is the unit a caregiver actually understands.
    var imageCount: Int = 0

    // MARK: - Cost

    /// Integer micro-dollars (1_000_000 = $1). Integer so summing a month of
    /// rows can't accumulate `Double` drift; a single sentence is ~120 micros,
    /// so there is ample resolution.
    var costMicros: Int = 0

    /// **A date, not a cost** — the publication date of the `ModelPricing` table
    /// that produced `costMicros`. Renamed from `pricedAsOf`, which read
    /// ambiguously as though it might hold a price.
    ///
    /// The price table carries no history (see the class doc), so this is what
    /// makes a stale table detectable after the fact: if our reported total
    /// disagrees with OpenAI's dashboard, this says which snapshot was in force
    /// when each row was written.
    var priceTableAsOf: Date = Date.distantPast

    // MARK: - Attribution

    /// `ChildProfile.id` active when the call was made, so the report can answer
    /// "what did this child cost this month". Empty when no child context
    /// applies (key validation, most authoring).
    var childID: String = ""

    // MARK: - Compaction (mirrors MetricEvent)
    //
    // ## What folds, and how
    //
    // **Yes — every field in Consumption and Cost is SUMMED**, never averaged.
    // A folded row is "here is everything this cause consumed and cost over this
    // period", which is the only reading under which a month's total stays
    // correct after old rows compact.
    //
    // - **Summed:** `count`, `promptTokens`, `cachedPromptTokens`,
    //   `imageInputTokens`, `completionTokens`, `imageCount`, `costMicros`.
    // - **Fold key** (rows may only fold when ALL of these are equal, since a
    //   sum across differing values would be meaningless):
    //   `causeRaw`, `model`, `endpoint`, `detail`, `childID`, `priceTableAsOf`.
    //   Including `priceTableAsOf` keeps a period spanning a price change from
    //   collapsing rows priced under different tables.
    // - **Range:** `timestamp` becomes the EARLIEST event in the fold and
    //   `periodEnd` the LATEST. A live row leaves `periodEnd` nil.
    //
    // The trap this documents: `promptTokens` on an aggregate row is not "what
    // one call used", so nothing may derive a per-call figure without dividing
    // by `count`. Averages are the reader's job, not the row's.

    /// How many occurrences this row represents. Always 1 for a live event; a
    /// compaction pass can fold a range of same-cause events into one row with
    /// `count > 1`. **Every reader must sum `count`, never count rows** — and
    /// token/cost fields on a folded row are the SUM over the period, not a
    /// per-call average.
    var count: Int = 1

    /// End of the range this row covers when it represents compacted history.
    /// Nil for a live single event (`timestamp` is the moment it happened).
    var periodEnd: Date?

    var isAggregate: Bool { count > 1 || periodEnd != nil }

    /// Typed accessor over `causeRaw`. Computed, so it cannot be used inside a
    /// `#Predicate` — filter on `causeRaw` there.
    var cause: UsageCause {
        get { UsageCause(rawValue: causeRaw) ?? .unknown }
        set { causeRaw = newValue.rawValue }
    }

    /// Cost in dollars, for display only. Never sum these — sum `costMicros`.
    var costUSD: Double { Double(costMicros) / 1_000_000 }

    /// This call was never billable — a free endpoint, or a model priced at zero.
    ///
    /// Displayed as **"free"**, not "$0.00". A dollar figure asserts that a cost
    /// was computed and came to nothing; for `/v1/moderations` the truth is that
    /// the endpoint doesn't bill at all. Different statements, and the report is
    /// worth more when it only says things it actually knows.
    var isFreeCall: Bool { cause.isFreeEndpoint || ModelPricing.isFree(model) }

    /// True when this row consumed billable tokens but carries no cost — i.e. we
    /// could not price it, as opposed to it having genuinely been free.
    ///
    /// Happens when the model was absent from `ModelPricing` at write time. The
    /// row keeps zero cost permanently, because history is never re-priced — so
    /// the display must say "unpriced" rather than "$0.00", which would assert
    /// something untrue about a call that really did cost money.
    ///
    /// This is how the first real device run surfaced: OpenAI returns dated
    /// snapshot ids (`gpt-4o-mini-2024-07-18`), the table only had the alias, and
    /// every chat row landed here.
    var isUnpriced: Bool {
        costMicros == 0 && totalTokens > 0 && !isFreeCall
    }

    /// Total tokens across every billed role.
    var totalTokens: Int { promptTokens + completionTokens }

    init(cause: UsageCause,
         model: String,
         endpoint: String = "",
         detail: String = "",
         promptTokens: Int = 0,
         cachedPromptTokens: Int = 0,
         imageInputTokens: Int = 0,
         completionTokens: Int = 0,
         imageCount: Int = 0,
         costMicros: Int = 0,
         priceTableAsOf: Date = .distantPast,
         childID: String = "",
         timestamp: Date = .now,
         count: Int = 1,
         periodEnd: Date? = nil) {
        self.causeRaw = cause.rawValue
        self.model = model
        self.endpoint = endpoint
        self.detail = detail
        self.promptTokens = promptTokens
        self.cachedPromptTokens = cachedPromptTokens
        self.imageInputTokens = imageInputTokens
        self.completionTokens = completionTokens
        self.imageCount = imageCount
        self.costMicros = costMicros
        self.priceTableAsOf = priceTableAsOf
        self.childID = childID
        self.timestamp = timestamp
        self.count = count
        self.periodEnd = periodEnd
    }
}
