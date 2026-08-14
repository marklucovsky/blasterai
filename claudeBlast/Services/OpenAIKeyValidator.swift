// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeyValidator.swift
//  claudeBlast
//
//  Lightweight "is this key usable?" check. Hits the cheapest authenticated
//  OpenAI endpoint (GET /v1/models) and maps the status code to a friendly
//  outcome. Only the key (as a bearer token) leaves the device — no user
//  content — so it's safe to run during onboarding before any real generation.

import Foundation

enum OpenAIKeyValidator {
    enum Outcome: Equatable {
        case valid
        case invalidKey            // 401 — rejected
        case rateLimited           // 429
        case networkError(String)  // unreachable / timed out
        case unexpected(Int)       // any other status

        /// A short, non-technical sentence for the entry UI.
        var friendlyMessage: String {
            switch self {
            case .valid:            return "Key verified."
            case .invalidKey:       return "That key was rejected — check you copied the whole key (it starts with \u{201C}sk-\u{201D})."
            case .rateLimited:      return "OpenAI is rate-limiting right now — try again in a moment."
            case .networkError:     return "Couldn't reach OpenAI — check your internet connection."
            case .unexpected(let code): return "Unexpected response from OpenAI (\(code))."
            }
        }
    }

    private static let modelsURL = URL(string: "https://api.openai.com/v1/models")!

    /// Verify `key` against OpenAI. Returns `.invalidKey` for empty input
    /// without a network round-trip.
    static func validate(
        _ key: String,
        session: URLSession = .shared
    ) async -> Outcome {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await OpenAIClient.send(
                request, cause: .keyValidation, endpoint: OpenAIEndpoint.models,
                session: session)
            guard let http = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }
            switch http.statusCode {
            case 200:        return .valid
            case 401, 403:   return .invalidKey
            case 429:        return .rateLimited
            default:         return .unexpected(http.statusCode)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}
