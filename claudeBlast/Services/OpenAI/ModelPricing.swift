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

/// Every OpenAI model this app calls. Declared here so the price table and the
/// request bodies can never name different models — the failure mode that makes
/// a cost report quietly wrong rather than obviously broken.
enum ModelID {
    /// Sentence generation. `CacheKeyPolicy.modelID` reads this, so the cache
    /// key and the request model stay coupled.
    static let sentence = "gpt-4o-mini"
    /// Scene/page/tile authoring and the word-audit rubric.
    static let authoring = "gpt-4o-mini"
    /// `/v1/moderations` policy screen — free.
    static let moderation = "omni-moderation-latest"
    /// Tile art generation and refinement.
    static let image = "gpt-image-1"
}

/// Per-million-token rates for one model, in US dollars.
///
/// Roles rather than endpoints: a chat model prices `textInput` / `cachedInput` /
/// `output`, an image model prices `textInput` / `imageInput` / `output` (where
/// output is the generated image). A model simply leaves unused roles at zero.
struct ModelRates: Sendable {
    let textInputPerM: Double
    let cachedInputPerM: Double
    let imageInputPerM: Double
    let outputPerM: Double

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
        c.year = 2026; c.month = 8; c.day = 13
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    /// US dollars per 1M tokens, verified against the pricing page on `asOf`.
    static let rates: [String: ModelRates] = [
        ModelID.sentence: ModelRates(textInputPerM: 0.15, cachedInputPerM: 0.075,
                                     imageInputPerM: 0, outputPerM: 0.60),
        ModelID.image: ModelRates(textInputPerM: 5.00, cachedInputPerM: 0,
                                  imageInputPerM: 10.00, outputPerM: 40.00),
        ModelID.moderation: .free,
    ]

    /// Cost in integer micro-dollars (1_000_000 = $1).
    ///
    /// The arithmetic collapses neatly: a rate quoted per 1M tokens, applied to
    /// N tokens, expressed in micro-dollars, is just `N × rate`.
    ///   700 prompt tokens × $0.15/M = 105 micros = $0.000105
    ///   1056 image-output tokens × $40/M = 42,240 micros = $0.042
    ///
    /// Returns `nil` for a model absent from the table. Callers record the row
    /// with **zero cost** rather than guessing: a visible under-report shows up
    /// as an anomaly against OpenAI's dashboard, whereas an invented number
    /// silently corrupts the very claim this system exists to verify.
    static func costMicros(model: String,
                           promptTokens: Int,
                           cachedPromptTokens: Int = 0,
                           imageInputTokens: Int = 0,
                           completionTokens: Int) -> Int? {
        guard let r = resolveRates(for: model) else {
            logger.warning("No price entry for model \(model, privacy: .public) — recording usage at zero cost")
            return nil
        }
        // Prompt tokens partition into three differently-priced buckets; plain
        // text input is whatever the cached and image portions don't claim.
        let plainTextTokens = max(0, promptTokens - cachedPromptTokens - imageInputTokens)
        let dollarsPerMillion =
            Double(plainTextTokens) * r.textInputPerM
            + Double(cachedPromptTokens) * r.cachedInputPerM
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
        return r.textInputPerM == 0 && r.cachedInputPerM == 0
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
