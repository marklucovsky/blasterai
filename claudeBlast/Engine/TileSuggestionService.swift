// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileSuggestionService.swift
//  claudeBlast
//

import Foundation
import SwiftData

/// The result of an AI tile suggestion: existing vocabulary keys to select, PLUS
/// proposed NEW words (declared `displayName` + `wordClass`) to materialize.
/// Mirrors scene/page generation so "Suggest tiles for potty training" can
/// introduce potty/pee/poop, not just the existing "toilet".
struct TileSuggestionResult {
    var existingKeys: Set<String>
    var newWords: [GeneratedNewWord]
}

struct TileSuggestionService {
    let apiKey: String

    /// Ask gpt-4o-mini for the tiles that fit `goal` — existing keys from
    /// `allTiles` and any COMMON, CONCRETE new words worth adding.
    func suggest(goal: String, allTiles: [TileModel]) async throws -> TileSuggestionResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let validKeys = Set(allTiles.map(\.key))
        let body = requestBody(goal: goal, allTiles: allTiles)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: .tileSuggest, endpoint: OpenAIEndpoint.chatCompletions)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(statusCode: http.statusCode, body: body)
        }

        return try parseResult(data: data, validKeys: validKeys)
    }

    /// The exact chat-completions body `suggest` sends. Pure, so the prompt
    /// fixtures (`PromptFixtureTests`) can pin it without a network call.
    func requestBody(goal: String, allTiles: [TileModel]) -> [String: Any] {
        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let systemMessage = PromptTemplate.render("tile_suggest_system", [
            "class_guidance": VocabularyClasses.classSelectionGuidance,
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
        ])
        let userMessage = PromptTemplate.render("tile_suggest_user", ["goal": goal, "vocab_block": vocabBlock])

        return ChatRequest.body(model: ModelID.tileSuggest,
                                messages: [["role": "system", "content": systemMessage],
                                           ["role": "user", "content": userMessage]],
                                temperature: 0.4, maxTokens: 700)
    }

    // MARK: - Helpers

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            // Navigation and page-link tiles are not words to suggest — the
            // folder tiles (`folder_moving`…) would otherwise read as vocabulary.
            // Same rule as `SceneGeneratorService.vocabBlock`.
            guard !tile.isStructuralChrome else { continue }
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    /// Lenient new-word shape — a single malformed element must not sink the
    /// whole response (we just drop it).
    private struct LenientNewWord: Codable {
        var key: String?
        var displayName: String?
        var wordClass: String?
    }
    private struct SuggestionResponse: Codable {
        var keys: [String]?
        var newWords: [LenientNewWord]?
    }

    private func messageContent(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse response")
        }
        return content
    }

    private func parseResult(data: Data, validKeys: Set<String>) throws -> TileSuggestionResult {
        let content = try messageContent(data: data)

        // Preferred shape: an object { keys, newWords }.
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
           let objData = String(content[start...end]).data(using: .utf8),
           let resp = try? JSONDecoder().decode(SuggestionResponse.self, from: objData) {
            let declared = (resp.newWords ?? []).compactMap { l -> GeneratedNewWord? in
                guard let k = l.key, let d = l.displayName, let w = l.wordClass else { return nil }
                return GeneratedNewWord(key: k, displayName: d, wordClass: w)
            }
            let newWords = Array(GeneratedNewWord.lookup(from: declared).values)
            let existing = Set((resp.keys ?? []).map { TileModel.normalizeKey($0) })
                .intersection(validKeys)
            return TileSuggestionResult(existingKeys: existing, newWords: newWords)
        }

        // Fallback: a bare array of keys (older prompt shape) — existing only.
        if let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"),
           let arrData = String(content[start...end]).data(using: .utf8),
           let keys = try? JSONDecoder().decode([String].self, from: arrData) {
            let existing = Set(keys.map { TileModel.normalizeKey($0) }).intersection(validKeys)
            return TileSuggestionResult(existingKeys: existing, newWords: [])
        }

        throw OpenAIError.decodingError("Response was not valid suggestion JSON")
    }
}
