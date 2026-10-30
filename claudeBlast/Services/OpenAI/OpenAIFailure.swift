// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIFailure.swift
//  claudeBlast
//
//  What a refusal from OpenAI actually means.
//

import Foundation

/// Why a request was refused, and therefore what the device should do about it.
///
/// Four conditions arrive over two status codes, and the status alone does not
/// separate them. All four were measured against a live scoped, capped project
/// on 2026-09-16 rather than read off documentation — the bodies below are
/// verbatim.
///
/// | Status | `type` / `code`                                  | Case          |
/// |--------|--------------------------------------------------|---------------|
/// | 401/403| `invalid_api_key` and friends                    | `.rejected`   |
/// | 403    | `invalid_request_error` / `model_not_found`      | `.capability` |
/// | 429    | `insufficient_quota` / `project_spend_limit_…`   | `.exhausted`  |
/// | 429    | `rate_limit_exceeded`                            | `.transient`  |
///
/// The two defaults are deliberately asymmetric, and both preserve the
/// behaviour that existed before this type:
///
/// - An **unrecognised 403 is `.rejected`**. A refusal to authenticate is the
///   overwhelmingly likely reading, and a device that wrongly falls back still
///   speaks every word the child taps.
/// - An **unrecognised 429 is `.transient`**. Ordinary rate limiting is far more
///   common than quota exhaustion, and condemning a working key over a burst is
///   exactly the failure `SentenceEngine.isKeyRejection` was written to avoid.
enum OpenAIFailure: Equatable {
    /// The key is finished — revoked, deleted, malformed. A new key is the only fix.
    case rejected

    /// The money ran out: a project spend limit, or an account with no credit
    /// left. The key itself is valid and starts working again when it is topped
    /// up or the limit is raised, which is why it is not `.rejected`.
    case exhausted

    /// The key is fine; one model is not available to it. Carries the model name
    /// when OpenAI names it, because "which model" is the entire diagnostic.
    ///
    /// **Never latches anywhere.** Allowlist changes propagate with a lag —
    /// observed 2026-09-16 as a model working, then intermittently failing,
    /// shortly after being enabled — so a remembered "this key can't do images"
    /// would keep a newly-granted key broken until the app was relaunched.
    case capability(model: String?)

    /// The request itself was refused on its merits — content policy, an invalid
    /// parameter, a prompt the safety system rejected. The key and the balance
    /// are both fine; *this* request is not going to work however many times it
    /// is retried.
    ///
    /// Carries OpenAI's own message, and this is the one place it is shown
    /// verbatim. Elsewhere their copy is written for the account owner and is
    /// wrong for a caregiver, but a content-policy refusal is specific to what
    /// was just asked for and no paraphrase of ours would be more useful.
    case requestRefused(message: String)

    /// Retry later: a network blip, a 500, a rate limit. Changes no state.
    case transient
}

extension OpenAIFailure {
    /// Classify a thrown error.
    ///
    /// Static and pure so it can be tested without an engine, a network or a
    /// clock — the generation path that consumes it is private, and a test
    /// reaching into that would compile to nothing and silently pass (see the
    /// note in CLAUDE.md).
    static func classify(_ error: Error) -> OpenAIFailure {
        guard case OpenAIError.httpError(let status, let body) = error else {
            return .transient
        }
        let detail = ErrorBody(body)

        switch status {
        case 401:
            return .rejected

        case 403:
            // Matched on `code` rather than `type`, because
            // `invalid_request_error` is a broad family and only this member of
            // it means "the key is healthy, the model is not".
            if detail.code == "model_not_found" {
                return .capability(model: detail.modelName)
            }
            return .rejected

        case 429:
            // Matched on `type`, not `code`, and the generality is the point.
            // `insufficient_quota` is equally what OpenAI returns when an
            // ordinary BYOK account exhausts its own credit, so one case covers
            // a gifted project hitting its cap and a family's $5 running out.
            // The narrower `project_spend_limit_exceeded` would have handled
            // only the first.
            if detail.type == "insufficient_quota" {
                return .exhausted
            }
            return .transient

        case 400, 422:
            // A refusal about the request, not the credential. Reached mainly
            // from image generation, where the safety system declines a prompt —
            // and where the message names what it objected to, which nothing on
            // our side can reconstruct.
            if let message = detail.message, !message.isEmpty {
                return .requestRefused(message: message)
            }
            return .transient

        default:
            return .transient
        }
    }

    /// One sentence a caregiver can act on, for any surface that asks the API
    /// for something and can fail.
    ///
    /// Written here rather than at each call site because there are seven AI
    /// surfaces and they were each saying something different, or — worse —
    /// nothing. "Created art for 0 of 2 words" is true and useless; the reason
    /// was sitting in the error and got dropped.
    ///
    /// **Never OpenAI's own message.** The quota one names the project and links
    /// to a settings page only the account owner can open, which is confusing to
    /// a parent and unusable to an evaluator holding a key someone gave them.
    var caregiverMessage: String {
        switch self {
        case .exhausted:
            return "This key is out of credit. The key itself is fine — it works again "
                 + "once more credit is added or the spending limit resets."
        case .rejected:
            return "OpenAI refused this key. It may have been revoked or deleted. "
                 + "Add a different key from Settings → Device."
        case .capability(let model):
            let what = model.map { "the \($0) model" } ?? "a model it needs"
            return "This key cannot use \(what). Everything that doesn't need it still works."
        case .requestRefused(let message):
            return message
        case .transient:
            return "Couldn't reach OpenAI just now. Check the connection and try again."
        }
    }

    /// Convenience for the common `catch { message = … }` shape.
    static func caregiverMessage(for error: Error) -> String {
        classify(error).caregiverMessage
    }

    /// The fields of OpenAI's error envelope that decide the classification.
    ///
    /// Tolerant by construction: a body that is not JSON, or is JSON of some
    /// other shape, yields empty fields and falls through to the per-status
    /// default rather than throwing. A refusal we cannot parse is still a
    /// refusal, and the defaults above are safe.
    private struct ErrorBody {
        let type: String?
        let code: String?
        let message: String?

        init(_ body: String) {
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let error = json["error"] as? [String: Any] else {
                type = nil; code = nil; message = nil
                return
            }
            type = error["type"] as? String
            code = error["code"] as? String
            message = error["message"] as? String
        }

        /// The model named in a `model_not_found` message.
        ///
        /// OpenAI puts it in prose rather than a field:
        /// "Project `proj_…` does not have access to model `gpt-image-1`".
        /// The last backticked token is the model; if the wording changes we get
        /// `nil` and the caller says "a model" instead of naming one, which is
        /// a degraded message rather than a wrong one.
        var modelName: String? {
            guard let message else { return nil }
            let quoted = message.split(separator: "`").enumerated()
                .filter { $0.offset % 2 == 1 }
                .map { String($0.element) }
            return quoted.last { $0.contains("-") && !$0.hasPrefix("proj_") }
        }
    }
}
