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
        let vocabBlock = buildVocabBlock(allTiles: allTiles)

        let systemMessage = """
        You are an expert AAC (Augmentative and Alternative Communication) specialist choosing the \
        tiles for one topical page on a non-verbal child's communication board.

        1. WORLD INFERENCE — From the goal, brainstorm the common, concrete things a child would \
        actually SEE or DO for it: objects, animals, foods, places, people-roles, plus the core \
        action or describing words at the heart of it. Include the obvious items even if the goal \
        did not name them (e.g. potty training implies toilet, potty, pee, poop, wipe, flush, wash, \
        dry, underwear). Pull the FULL relevant set, not just a couple.

        2. PREFER EXISTING — Before proposing a NEW word, search the vocabulary below for an existing \
        word with the same or a near-identical meaning and use that key instead. Only introduce a new \
        word when nothing existing fits.

        3. NEW WORDS — A NEW word must be a COMMON, CONCRETE thing with a single clear visual (an \
        animal, object, food, place, or person). NEVER make abstract concepts, feelings, or actions \
        into new words — those must come from existing vocabulary. \(VocabularyClasses.classSelectionGuidance) \
        Declare each new word ONCE in "newWords" with its "displayName" and "wordClass" (one of: \
        \(VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "))).

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose:
        {
          "keys": ["toilet", "potty", "pee"],
          "newWords": [ { "key": "potty", "displayName": "potty", "wordClass": "body" } ]
        }
        Every entry in "keys" MUST be either an existing vocabulary key or a key declared in \
        "newWords". Aim for 8–20 tiles total.
        """

        let userMessage = """
        Goal: \(goal)

        Existing vocabulary by category:
        \(vocabBlock)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.4,
            "max_tokens": 700,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user",   "content": userMessage]
            ]
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(statusCode: http.statusCode, body: body)
        }

        return try parseResult(data: data, validKeys: validKeys)
    }

    // MARK: - Helpers

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
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
