// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneRefinerService.swift
//  claudeBlast
//
//  Iteratively refines an existing scene from a therapist's natural-language
//  instruction ("add a fish pond and a creek"). Refinement operates on the
//  scene's TOPICAL layer only — the activity vocabulary the model originally
//  inferred — and the familiar core board is rebuilt around it by
//  SceneNavigation.scaffold (via GeneratedScene.parse). This keeps refinement
//  consistent with generation and never disturbs the core board.
//

import Foundation

struct SceneRefinerService {
    let apiKey: String

    /// The model is `ModelID.sceneAuthoring`.
    private let temperature = 0.5
    private let maxTokens = 3000

    /// Apply `instruction` to a scene whose current topical tiles are
    /// `currentTopical`, returning a freshly scaffolded scene. `allTiles` is the
    /// live vocabulary. Topical tiles carrying new-word metadata (proposed words
    /// on an un-accepted preview) are carried forward so they survive the round
    /// trip even if the model references them by key without re-declaring.
    func refine(instruction: String,
                currentTopical: [GeneratedTile],
                allTiles: [TileModel],
                chrome: SceneNavigation.ChromeBundle = .none) async throws -> GeneratedScene {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let body = requestBody(instruction: instruction, currentTopical: currentTopical, allTiles: allTiles)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: .sceneRefine, endpoint: OpenAIEndpoint.chatCompletions)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }

        // Carry forward proposed words from the current topical layer that aren't
        // yet in base vocabulary, so an un-accepted preview's new words survive.
        let carryOver: [GeneratedNewWord] = currentTopical.compactMap { tile in
            guard tile.isProposedNew, let displayName = tile.displayName, let wordClass = tile.wordClass
            else { return nil }
            return GeneratedNewWord(key: tile.key, displayName: displayName, wordClass: wordClass)
        }
        return try GeneratedScene.parse(content: content, allTiles: allTiles,
                                        extraNewWords: carryOver, chrome: chrome)
    }

    /// The exact chat-completions body `refine` sends. Pure, so the prompt
    /// fixtures (`PromptFixtureTests`) can pin it without a network call.
    func requestBody(instruction: String, currentTopical: [GeneratedTile],
                     allTiles: [TileModel]) -> [String: Any] {
        let system = buildSystemPrompt(currentTopical: currentTopical)
        let user = buildUserPrompt(instruction: instruction, vocabBlock: buildVocabBlock(allTiles: allTiles))
        return ChatRequest.body(model: ModelID.sceneAuthoring,
                                messages: [["role": "system", "content": system],
                                           ["role": "user", "content": user]],
                                temperature: temperature, maxTokens: maxTokens)
    }

    // MARK: - Prompt builders

    private func buildSystemPrompt(currentTopical: [GeneratedTile]) -> String {
        let listing = currentTopical
            .map { tile in
                let name = tile.displayName ?? tile.key.replacingOccurrences(of: "_", with: " ")
                return "\(tile.key) — \(name)"
            }
            .joined(separator: "\n")
        return PromptTemplate.render("scene_refine_system", [
            "current_tiles": listing,
            "class_guidance": VocabularyClasses.classSelectionGuidance,
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
        ])
    }

    private func buildUserPrompt(instruction: String, vocabBlock: String) -> String {
        PromptTemplate.render("scene_refine_user", ["instruction": instruction, "vocab_block": vocabBlock])
    }

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            guard !tile.isStructuralChrome else { continue }
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}
