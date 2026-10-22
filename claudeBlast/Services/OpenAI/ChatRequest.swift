// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChatRequest.swift
//  claudeBlast
//
//  The one place a chat-completions body is assembled, so it always fits the
//  model it names.
//

import Foundation

/// What one chat model accepts.
///
/// The models do not take the same parameters, and the wrong one is a 400, not
/// a warning (probed 2026-10-19):
/// - every GPT-6 model rejects any `temperature` but the default, and every
///   service here sends one;
/// - GPT-6 takes `reasoning_effort` (Luna's lowest is `none`, Sol's is `low`)
///   and `max_completion_tokens`, whose budget includes reasoning tokens;
/// - gpt-4o-mini takes neither of those, and `max_tokens`.
///
/// Mirrors `tools/eval/models.py`, which adapts the same requests for the eval —
/// keep the two in step, or the eval measures a request the app never sends.
struct ModelCapabilities: Sendable, Equatable {
    let acceptsTemperature: Bool
    /// `reasoning_effort` to send; nil for a model that takes none.
    let reasoningEffort: String?

    nonisolated static let classic = ModelCapabilities(acceptsTemperature: true, reasoningEffort: nil)

    /// Every chat model a `ModelID` job may name. `ModelCapabilitiesTests`
    /// fails if a job names one missing from here.
    nonisolated static let table: [String: ModelCapabilities] = [
        "gpt-4o-mini": .classic,
        // 0 reasoning tokens on our prompts at none; sentences ~1.0 s p50.
        "gpt-6-luna": ModelCapabilities(acceptsTemperature: false, reasoningEffort: "none"),
        // Sol has no `none`. Scene pages ~10 s at low.
        "gpt-6.1-sol": ModelCapabilities(acceptsTemperature: false, reasoningEffort: "low"),
    ]

    /// Capabilities for `model`, tolerating a dated snapshot id the same way
    /// `ModelPricing.resolveRates` does (longest matching key wins).
    nonisolated static func of(_ model: String) -> ModelCapabilities {
        if let exact = table[model] { return exact }
        return table.filter { model.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?.value ?? .classic
    }
}

/// A chat-completions body for whatever model the caller's `ModelID` job names.
///
/// Services state what they want in gpt-4o-mini's terms — a temperature, a
/// visible-text token limit — and this translates for the model: drops the
/// temperature GPT-6 rejects, adds its reasoning effort, and moves the limit to
/// `max_completion_tokens`, ×4 above effort `none` because reasoning tokens
/// count against it (the eval's `adapt` does the same).
///
/// For gpt-4o-mini the result is exactly the body the services built by hand
/// before this existed; the prompt fixtures pin that byte for byte.
enum ChatRequest {
    nonisolated static func body(model: String,
                                 messages: [[String: Any]],
                                 temperature: Double,
                                 maxTokens: Int? = nil) -> [String: Any] {
        let caps = ModelCapabilities.of(model)
        var body: [String: Any] = ["model": model, "messages": messages]
        if caps.acceptsTemperature {
            body["temperature"] = temperature
        }
        if let effort = caps.reasoningEffort {
            body["reasoning_effort"] = effort
            if let maxTokens {
                body["max_completion_tokens"] = effort == "none" ? maxTokens : maxTokens * 4
            }
        } else if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        return body
    }
}
