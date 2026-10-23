// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ModelPricing.swift
//  claudeBlast
//
//  The one place model ids and their prices are written down.
//

import Foundation
import os

/// The model each job calls — one entry per job, and the only place a service
/// finds its model. Declared here so the price table and the request bodies can
/// never name different models — the failure mode that makes a cost report
/// quietly wrong rather than obviously broken.
///
/// **One entry per job, not per kind of work.** There used to be a single
/// `authoring` covering scene writing, tile suggestions, the word audit and the
/// skin check, and five services named "gpt-4o-mini" themselves besides. GPT-6
/// splits those jobs across models (eval, 2026-10-21: Sol writes scene pages,
/// Luna writes sentences), so one shared setting would have moved the word
/// audit to Sol along with the scenes. Switching a job is now one line here;
/// `ChatRequest` adapts the body to whatever model the line names.
///
/// **Build 9 (2026-10-23) moved every chat job off gpt-4o-mini**, which retires
/// 2027-01-14. Per-job numbers are in `docs/eval/gpt6-switch.md`.
enum ModelID {
    /// Sentence generation and escalation. `CacheKeyPolicy.modelID` reads this,
    /// so the cache key and the request model stay coupled — the switch retires
    /// gpt-4o-mini's cached sentences rather than serving them. Luna, not Sol:
    /// Sol's sentences were better but ~1.5 s at p50, and this is the child's
    /// real-time path.
    nonisolated static let sentence = "gpt-6-luna"
    /// Scene and page generation and refinement. Sol: far better pages, at
    /// ~16 s for a whole scene (gpt-4o-mini ~6 s).
    nonisolated static let sceneAuthoring = "gpt-6.1-sol"
    /// Tile suggestions for a goal. Sol: 6 of 24 outputs weak against Luna's 17,
    /// at ~5 s; it is authoring, not the child's path.
    nonisolated static let tileSuggest = "gpt-6.1-sol"
    /// The word audit's age-appropriateness rubric (`WordModerationService`
    /// tier 3) — the primary gate on a new word. Luna is more lenient than
    /// gpt-4o-mini: report-harm words (fight, blood, hate) and mild insults are
    /// flagged for the caregiver rather than blocked, as decided 2026-10-19.
    nonisolated static let wordAudit = "gpt-6-luna"
    /// "Does this tile show skin?" before a tone transform — an image input, so
    /// the model must accept images. Luna matches the recorded Classic answers
    /// (`tools/eval/probe_skin_check.py`) once its token limit fits the answer.
    nonisolated static let skinCheck = "gpt-6-luna"
    /// `/v1/moderations` policy screen — free.
    nonisolated static let moderation = "omni-moderation-latest"
    /// Tile art generation and refinement. gpt-image-1 shuts down 2026-10-23;
    /// gpt-image-2 is OpenAI's documented replacement.
    nonisolated static let image = "gpt-image-2"
}

/// Per-million-token rates for one model, in US dollars.
///
/// Roles rather than endpoints: a chat model prices `textInput` / `cachedInput` /
/// `output`, an image model prices `textInput` / `imageInput` / `output` (where
/// output is the generated image). A model simply leaves unused roles at zero.
///
/// `cacheWritePerM` is GPT-6's: a prompt it has not seen is billed as a **cache
/// write** at 1.25× input, not as plain input — on the 2026-10-21 bill, Luna's
/// day was 1.84M cache-write tokens against 11,625 plain input tokens. Left at
/// zero, a GPT-6 call would price its whole first-seen prompt at the input rate.
struct ModelRates: Sendable {
    let textInputPerM: Double
    let cachedInputPerM: Double
    let imageInputPerM: Double
    let outputPerM: Double
    var cacheWritePerM: Double = 0

    static let free = ModelRates(textInputPerM: 0, cachedInputPerM: 0,
                                 imageInputPerM: 0, outputPerM: 0)
}

/// Snapshot of OpenAI's published prices.
///
/// ## This table carries no history, on purpose
///
/// `APIUsageEvent.costMicros` is computed at write time and stored, so a
/// historical row already holds the dollars it actually incurred. This table is
/// therefore only ever consulted for the call happening *right now*, and exactly
/// one current price set is needed. Updating prices means editing `rates` and
/// bumping `asOf` — rows written earlier keep their original cost, which is the
/// correct answer rather than a limitation.
///
/// ## There is no pricing API — this table is transcribed by hand
///
/// OpenAI publishes **no endpoint that returns per-model prices**. `/v1/models`
/// lists models but carries no rates. The numbers below were read off the public
/// pricing page (https://developers.openai.com/api/docs/pricing) on `asOf` and
/// typed in. Nothing detects a change automatically, and the app deliberately
/// does not fetch prices at runtime: that would add a network dependency on a
/// human-readable page that is not an API, introduce a parse-failure mode on the
/// hot path, and undercut the offline story for no real gain.
///
/// **What does exist is better for checking our work:** the Admin
/// `/v1/organization/costs` endpoint returns *actually billed dollars* and
/// reconciles to the OpenAI invoice. It requires an **Admin API key** created by
/// an org Owner — org-wide and far more privileged than the project key a
/// caregiver supplies — so it must never be requested from a user or wired into
/// the app. It is a **development-time verification tool** run against our own
/// org (see `tools/`), which turns "eyeball the dashboard" into a real check.
///
/// ## When to update this table
///
/// A stale table only mis-prices calls made between OpenAI's change and our
/// update; rows already written keep their original cost. So the exposure is a
/// window, not a corruption. Re-verify:
///
/// 1. **Whenever a model id in `ModelID` changes** — the highest-risk moment by
///    far, since a new model almost certainly has different rates, and the
///    change will otherwise look like it worked.
/// 2. **At each release** — cheap, and bounds the staleness window to a cycle.
/// 3. **Whenever reconciliation disagrees** with the Costs API or the dashboard.
///
/// `daysSinceVerified` backs a "prices last verified N days ago" line in the
/// Activity detail view, so the staleness is visible to us rather than assumed
/// away. **Treat this table as a convenience, never as an authority.**
enum ModelPricing {
    private static let logger = Logger(subsystem: "app.blasterai", category: "pricing")

    /// Publication date of the prices below. Bump whenever `rates` changes.
    /// Source: https://developers.openai.com/api/docs/pricing
    static let asOf: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 21
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    /// US dollars per 1M tokens, verified against the pricing page on `asOf`;
    /// the GPT-6 rates also against the 2026-10-21 billing export, which the
    /// eval harness's own accounting matched to the cent.
    ///
    /// **Keyed by model name, never by `ModelID` job.** Keyed by job, moving
    /// `ModelID.sentence` to another model would have taken gpt-4o-mini's entry
    /// with it while other jobs still called gpt-4o-mini — every one of their
    /// rows unpriced.
    static let rates: [String: ModelRates] = [
        "gpt-4o-mini": ModelRates(textInputPerM: 0.15, cachedInputPerM: 0.075,
                                  imageInputPerM: 0, outputPerM: 0.60),
        "gpt-6-luna": ModelRates(textInputPerM: 0.10, cachedInputPerM: 0.01,
                                 imageInputPerM: 0, outputPerM: 0.50, cacheWritePerM: 0.125),
        "gpt-6.1-sol": ModelRates(textInputPerM: 2.00, cachedInputPerM: 0.10,
                                  imageInputPerM: 0, outputPerM: 10.00, cacheWritePerM: 2.50),
        "gpt-image-2": ModelRates(textInputPerM: 5.00, cachedInputPerM: 0,
                                  imageInputPerM: 8.00, outputPerM: 30.00),
        "omni-moderation-latest": .free,
    ]

    /// Cost in integer micro-dollars (1_000_000 = $1).
    ///
    /// The arithmetic collapses neatly: a rate quoted per 1M tokens, applied to
    /// N tokens, expressed in micro-dollars, is just `N × rate`.
    ///   700 prompt tokens × $0.15/M = 105 micros = $0.000105
    ///   1756 image-output tokens × $30/M = 52,680 micros = $0.053
    ///
    /// Returns `nil` for a model absent from the table. Callers record the row
    /// with **zero cost** rather than guessing: a visible under-report shows up
    /// as an anomaly against OpenAI's dashboard, whereas an invented number
    /// silently corrupts the very claim this system exists to verify.
    static func costMicros(model: String,
                           promptTokens: Int,
                           cachedPromptTokens: Int = 0,
                           cacheWriteTokens: Int = 0,
                           imageInputTokens: Int = 0,
                           completionTokens: Int) -> Int? {
        guard let r = resolveRates(for: model) else {
            logger.warning("No price entry for model \(model, privacy: .public) — recording usage at zero cost")
            return nil
        }
        // Prompt tokens partition into four differently-priced buckets; plain
        // text input is whatever the cached, cache-written and image portions
        // don't claim.
        let plainTextTokens = max(0, promptTokens - cachedPromptTokens - cacheWriteTokens - imageInputTokens)
        let dollarsPerMillion =
            Double(plainTextTokens) * r.textInputPerM
            + Double(cachedPromptTokens) * r.cachedInputPerM
            + Double(cacheWriteTokens) * r.cacheWritePerM
            + Double(imageInputTokens) * r.imageInputPerM
            + Double(completionTokens) * r.outputPerM
        return Int((dollarsPerMillion).rounded())
    }

    /// Find rates for a model id, tolerating **dated snapshot ids**.
    ///
    /// OpenAI's responses echo the resolved snapshot, not the alias you asked
    /// for: a request for `gpt-4o-mini` comes back as `gpt-4o-mini-2024-07-18`.
    /// Since we deliberately record the model the API *reported* (so a
    /// server-side substitution is visible), an exact-match lookup misses every
    /// chat call and silently prices it at zero. That is precisely what happened
    /// on the first real run — every sentence showed $0.00 while the images,
    /// whose `gpt-image-1` id carries no date, priced correctly.
    ///
    /// Resolution: exact match first, then the **longest** table key the reported
    /// id is prefixed by. Longest wins so that adding `gpt-4o` alongside
    /// `gpt-4o-mini` can never let the pricier model's rates capture a mini
    /// snapshot — the failure this would otherwise invite.
    static func resolveRates(for model: String) -> ModelRates? {
        if let exact = rates[model] { return exact }
        return rates
            .filter { model.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// True when we have a price for this model, including dated snapshot ids.
    static func isPriced(_ model: String) -> Bool { resolveRates(for: model) != nil }

    /// True when this model is genuinely **free**, not merely unpriced.
    ///
    /// The distinction matters in the report: `/v1/moderations` costs nothing, so
    /// `$0.00` is the truth. A chat call that consumed 3,200 tokens and shows
    /// `$0.00` is something else entirely — a row we couldn't price, displaying a
    /// number that claims it was free. Conflating those two is exactly the
    /// confusion this accounting exists to prevent, so the UI distinguishes them.
    static func isFree(_ model: String) -> Bool {
        guard let r = resolveRates(for: model) else { return false }
        return r.textInputPerM == 0 && r.cachedInputPerM == 0 && r.cacheWritePerM == 0
            && r.imageInputPerM == 0 && r.outputPerM == 0
    }

    /// How long since the prices above were verified against OpenAI's pricing
    /// page. Surfaced in the Activity detail view so a stale table is visible
    /// rather than silently assumed current — there being no API to check it for
    /// us (see the type doc).
    static func daysSinceVerified(asOf now: Date = .now) -> Int {
        Calendar.current.dateComponents([.day], from: asOf, to: now).day ?? 0
    }
}
