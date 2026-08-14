// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAISentenceProvider.swift
//  claudeBlast
//

import Foundation

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        case .decodingError(let detail):
            return "Failed to decode response: \(detail)"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        }
    }
}

struct OpenAISentenceProvider: SentenceProvider {
    let displayName = "OpenAI"
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        conversationContext: [String]
    ) async throws -> SentenceResult {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: buildRequestBody(
            systemPrompt: systemPrompt,
            conversationContext: conversationContext
        ))

        // `.sentenceGenerate` is the fallback only. Escalations and caregiver
        // refines reach this same line, and `SentenceEngine` distinguishes them
        // via the `UsageContext` task-local.
        let (data, response) = try await OpenAIClient.send(
            request, cause: .sentenceGenerate, endpoint: OpenAIEndpoint.chatCompletions)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Request building

    private func buildRequestBody(
        systemPrompt: [PromptMessage],
        conversationContext: [String]
    ) -> [String: Any] {
        var messages: [[String: Any]] = systemPrompt.map {
            ["role": $0.role, "content": $0.content]
        }

        // Add conversation context as prior assistant turns
        for sentence in conversationContext {
            messages.append(["role": "assistant", "content": sentence])
        }

        // The last context entry is the user prompt (tile descriptions)
        if let userPrompt = conversationContext.last {
            messages[messages.count - 1] = ["role": "user", "content": userPrompt]
        }

        return [
            // Single source of truth: the same constant seeds the cache version
            // token, so the request model and cache identity can't diverge.
            "model": CacheKeyPolicy.modelID,
            "messages": messages,
            "max_tokens": 500,
            // Lower temperature so the model is more obedient to the word-class
            // annotation rule rather than drifting to a word's common meaning.
            "temperature": 0.3,
        ]
    }

    private func parseResponse(data: Data) throws -> SentenceResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw OpenAIError.decodingError("Could not parse choices from response")
        }

        if let error = json["error"] as? [String: Any],
           let errorMessage = error["message"] as? String {
            throw OpenAIError.apiError(errorMessage)
        }

        guard let text = message["content"] as? String, !text.isEmpty else {
            throw OpenAIError.decodingError("No text content in response")
        }

        return SentenceResult(text: text, usage: parseUsage(json: json))
    }

    private func parseUsage(json: [String: Any]) -> TokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let model = json["model"] as? String ?? "unknown"
        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        return TokenUsage(
            model: model,
            promptTokens: usage["prompt_tokens"] as? Int ?? 0,
            completionTokens: usage["completion_tokens"] as? Int ?? 0,
            totalTokens: usage["total_tokens"] as? Int ?? 0,
            promptCachedTokens: promptDetails?["cached_tokens"] as? Int ?? 0
        )
    }
}
