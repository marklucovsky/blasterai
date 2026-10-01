// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIClient.swift
//  claudeBlast
//
//  The single seam every OpenAI call passes through, so usage is recorded once
//  rather than nine times.
//

import Foundation
import SwiftData
import os

/// Caller-supplied context for the call about to be made.
///
/// ## Why a task-local rather than a parameter
///
/// The *cause* of a call is known at the caller, not at the call site. A
/// sentence, an escalation, and a caregiver refine all reach the identical line
/// in `OpenAISentenceProvider`; only `SentenceEngine` knows which one is
/// happening. Threading that down would mean changing `SentenceProvider` — a
/// protocol with three implementations, two of which make no network call at all.
///
/// A task-local lets a caller annotate the work it is about to do without any
/// signature churn:
///
/// ```swift
/// await UsageContext.$current.withValue(.init(cause: .sentenceEscalate, childID: id)) {
///     try await provider.generate(...)
/// }
/// ```
///
/// The value propagates through `async` calls automatically and is read by
/// `OpenAIClient.send` at record time.
struct UsageContext: Sendable {
    var cause: UsageCause
    var detail: String
    var childID: String

    init(cause: UsageCause, detail: String = "", childID: String = "") {
        self.cause = cause
        self.detail = detail
        self.childID = childID
    }

    @TaskLocal static var current: UsageContext?
}

/// Records one API call's consumption. Isolated to the main actor because
/// `ModelContext` is not `Sendable`; `OpenAIClient` awaits it off whatever
/// context the call was made from.
@MainActor
final class UsageRecorder {
    static let shared = UsageRecorder()
    private static let logger = Logger(subsystem: "app.blasterai", category: "usage")

    /// Set once at launch. Nil in tests and previews, where recording is a no-op
    /// rather than a crash — an unconfigured ledger must never break a feature
    /// that would otherwise work.
    private var context: ModelContext?

    func configure(context: ModelContext) {
        self.context = context
        repairPhantomImageCounts(in: context)
    }

    /// Zero the image counts that never were.
    ///
    /// `/v1/models` answers a key check with `{"object":"list","data":[…every
    /// model…]}`, and the usage parser counted any `data` array as pictures — so
    /// each key check logged ~132 images. Ten of them put 1,320 imaginary images
    /// in the AI Usage summary beside the 20 real ones, which is exactly the kind
    /// of number this ledger exists to be trusted about.
    ///
    /// The parser is fixed, but rows already written keep the bad count for the
    /// rest of the month they landed in. They are provably wrong — a non-image
    /// endpoint cannot return an image — so they are repaired rather than
    /// explained. Costs are untouched: `imageCount` never fed the price, which is
    /// why the money was right all along while the count was not.
    ///
    /// Idempotent and cheap: after the first pass the predicate matches nothing.
    /// `APIUsageEvent` is device-local, so this rewrites nothing anyone else has.
    private func repairPhantomImageCounts(in context: ModelContext) {
        let generations = OpenAIEndpoint.imagesGenerations
        let edits = OpenAIEndpoint.imagesEdits
        let descriptor = FetchDescriptor<APIUsageEvent>(
            predicate: #Predicate { event in
                event.imageCount > 0 && event.endpoint != generations && event.endpoint != edits
            })
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for event in stale { event.imageCount = 0 }
        try? context.save()
        Self.logger.info("Cleared phantom image counts on \(stale.count, privacy: .public) usage rows")
    }

    func record(_ event: APIUsageEvent) {
        guard let context else {
            Self.logger.debug("Usage recorder unconfigured; dropping \(event.causeRaw, privacy: .public)")
            return
        }
        context.insert(event)
        // Deliberately not saving here: SwiftData autosaves, and forcing a save
        // on the hot sentence path would put disk I/O in front of speech.
    }
}

/// Transport + accounting for every OpenAI request in the app.
///
/// Each of the nine call sites replaces its `URLSession.shared.data(for:)` with
/// `OpenAIClient.send(request, cause:endpoint:)`. Services keep their existing
/// shape — stateless structs holding an `apiKey` — and gain accounting for free.
enum OpenAIClient {
    private static let logger = Logger(subsystem: "app.blasterai", category: "openai")

    /// Perform `request`, record what it consumed, and return the response
    /// untouched.
    ///
    /// `cause` is the fallback attribution; a `UsageContext` task-local set by
    /// the caller takes precedence, so a site that serves several causes (the
    /// sentence path) is annotated by its caller while single-purpose sites just
    /// pass their cause here.
    ///
    /// **Accounting never fails a request.** A missing `usage` object, an
    /// unpriced model, or a malformed body all degrade to a zero-cost row. The
    /// response is returned to the caller exactly as received either way.
    /// `session` is injectable so `OpenAIKeyValidator`'s existing test seam keeps
    /// working; every other caller takes the default.
    static func send(_ request: URLRequest,
                     cause: UsageCause,
                     endpoint: String,
                     session: URLSession = .shared,
                     consentGranted: Bool = AIConsent.isGranted()) async throws -> (Data, URLResponse) {
        // Nothing reaches OpenAI without permission. Checked here because every
        // request in the app passes through this line; see `AIConsent`.
        guard consentGranted else { throw AIConsentError.notGranted }
        let (data, response) = try await session.data(for: request)
        recordUsage(from: data, response: response, fallbackCause: cause, endpoint: endpoint)
        return (data, response)
    }

    // MARK: - Recording

    private static func recordUsage(from data: Data,
                                    response: URLResponse,
                                    fallbackCause: UsageCause,
                                    endpoint: String) {
        // Only successful calls consumed billable tokens. A 4xx/5xx carries no
        // usage object and costs nothing.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

        let ctx = UsageContext.current
        let cause = ctx?.cause ?? fallbackCause
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        let parsed = parseUsage(json: json, endpoint: endpoint)
        let model = parsed.model.isEmpty ? defaultModel(for: cause) : parsed.model

        let cost = ModelPricing.costMicros(
            model: model,
            promptTokens: parsed.promptTokens,
            cachedPromptTokens: parsed.cachedPromptTokens,
            imageInputTokens: parsed.imageInputTokens,
            completionTokens: parsed.completionTokens
        )

        let event = APIUsageEvent(
            cause: cause,
            model: model,
            endpoint: endpoint,
            detail: ctx?.detail ?? "",
            promptTokens: parsed.promptTokens,
            cachedPromptTokens: parsed.cachedPromptTokens,
            imageInputTokens: parsed.imageInputTokens,
            completionTokens: parsed.completionTokens,
            imageCount: parsed.imageCount,
            costMicros: cost ?? 0,
            priceTableAsOf: ModelPricing.asOf,
            childID: ctx?.childID ?? ""
        )

        Task { @MainActor in UsageRecorder.shared.record(event) }
    }

    private struct ParsedUsage {
        var model = ""
        var promptTokens = 0
        var cachedPromptTokens = 0
        var imageInputTokens = 0
        var completionTokens = 0
        var imageCount = 0
    }

    /// Reads the `usage` object common to chat and image responses.
    ///
    /// The two shapes differ in field names — chat reports
    /// `prompt_tokens`/`completion_tokens`, images report
    /// `input_tokens`/`output_tokens` — so both spellings are accepted. Image
    /// responses further split their input via `input_tokens_details.image_tokens`,
    /// which matters because image input is billed at twice the text rate.
    private static func parseUsage(json: [String: Any]?, endpoint: String) -> ParsedUsage {
        var out = ParsedUsage()
        guard let json else { return out }

        out.model = json["model"] as? String ?? ""
        // `data` is an array on more than one endpoint and means something
        // different on each: generated pictures on the image endpoints, and the
        // **model catalogue** on `/v1/models`. Counting it unconditionally made
        // every key check report ~132 images — ten of them put 1,320 imaginary
        // images in the usage summary, next to the 20 real ones. So the endpoint
        // decides, not the shape of the JSON.
        if OpenAIEndpoint.producesImages(endpoint),
           let items = json["data"] as? [[String: Any]] {
            out.imageCount = items.count
        }

        guard let usage = json["usage"] as? [String: Any] else { return out }

        out.promptTokens = usage["prompt_tokens"] as? Int ?? usage["input_tokens"] as? Int ?? 0
        out.completionTokens = usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int ?? 0

        if let details = usage["prompt_tokens_details"] as? [String: Any] {
            out.cachedPromptTokens = details["cached_tokens"] as? Int ?? 0
        }
        if let details = usage["input_tokens_details"] as? [String: Any] {
            out.imageInputTokens = details["image_tokens"] as? Int ?? 0
            // Some responses report cached tokens here too.
            out.cachedPromptTokens = details["cached_tokens"] as? Int ?? out.cachedPromptTokens
        }
        return out
    }

    /// Model to attribute when the response omitted one — the moderations and
    /// models endpoints don't echo it back. Never a guess for a *billable* call:
    /// chat and image responses always name their model.
    private static func defaultModel(for cause: UsageCause) -> String {
        switch cause {
        case .wordAuditScreen: return ModelID.moderation
        case .keyValidation:   return ""
        case .tileImageGenerate, .tileImageRefine: return ModelID.image
        default: return ModelID.authoring
        }
    }
}

// MARK: - Endpoint paths

/// The API paths this app calls, recorded on each ledger row because it's the
/// axis OpenAI's own usage dashboard breaks down by.
enum OpenAIEndpoint {
    static let chatCompletions = "/v1/chat/completions"
    static let imagesGenerations = "/v1/images/generations"
    static let imagesEdits = "/v1/images/edits"
    static let moderations = "/v1/moderations"
    static let models = "/v1/models"

    /// Whether a response from this endpoint's `data` array is pictures.
    static func producesImages(_ endpoint: String) -> Bool {
        endpoint == imagesGenerations || endpoint == imagesEdits
    }
}
