// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneGeneratorService.swift
//  claudeBlast
//
//  Generates a complete multi-page AAC scene from a therapist's free-form
//  session description.
//

import Foundation

struct SceneGeneratorService {
    let apiKey: String

    // MARK: - Prompt configuration
    // These constants are intentionally separate so prompt engineering is easy.

    /// Sampling settings. The model is `ModelID.sceneAuthoring`; `ChatRequest`
    /// drops the temperature for a model that rejects it.
    private let temperature = 0.5
    /// Rich world-inference scenes run 40–50 tiles across several pages; 2000
    /// truncated the JSON.
    private let maxTokens = 3000

    // MARK: - Public API

    func generate(description: String, allTiles: [TileModel]) async throws -> GeneratedScene {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let body = requestBody(description: description, allTiles: allTiles)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: .sceneGenerate, endpoint: OpenAIEndpoint.chatCompletions)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(statusCode: http.statusCode, body: body)
        }

        var scene = try parseScene(data: data, allTiles: allTiles)
        scene.tokenUsage = Self.totalTokens(from: data)
        return scene
    }

    /// The exact chat-completions body `generate` sends. Pure, so the prompt
    /// fixtures (`PromptFixtureTests`) can pin it without a network call.
    func requestBody(description: String, allTiles: [TileModel]) -> [String: Any] {
        let vocabBlock = Self.vocabBlock(allTiles: allTiles)
        let system = buildSystemPrompt(tileCount: allTiles.count)
        let user = buildUserPrompt(description: description, vocabBlock: vocabBlock)
        return ChatRequest.body(model: ModelID.sceneAuthoring,
                                messages: [["role": "system", "content": system],
                                           ["role": "user", "content": user]],
                                temperature: temperature, maxTokens: maxTokens)
    }

    /// Pull `usage.total_tokens` from a chat-completions response, if present.
    private static func totalTokens(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any],
              let total = usage["total_tokens"] as? Int else { return nil }
        return total
    }

    // MARK: - Prompt builders
    // Each builder is a separate function so individual prompt sections are easy to tune.

    private func buildSystemPrompt(tileCount: Int) -> String {
        PromptTemplate.render("scene_generate_system", [
            "class_guidance": VocabularyClasses.classSelectionGuidance,
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
        ])
    }

    private func buildUserPrompt(description: String, vocabBlock: String) -> String {
        PromptTemplate.render("scene_generate_user", ["description": description, "vocab_block": vocabBlock])
    }

    // MARK: - Vocab formatting

    /// `wordClass: key, key, …` per class. Shared with `TopicWordsService`.
    static func vocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            // Hide structural navigation + page_link tiles (next_page, page_home,
            // page_farm, …) so the model can't repurpose them as ad-hoc words or
            // page switchers; scene navigation is generated deterministically
            // (see SceneNavigation).
            guard !tile.isStructuralChrome else { continue }
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    // MARK: - Response parsing

    private func parseScene(data: Data, allTiles: [TileModel]) throws -> GeneratedScene {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }
        // Sanitize + scaffold is shared with SceneRefinerService.
        return try GeneratedScene.parse(content: content, allTiles: allTiles)
    }
}
