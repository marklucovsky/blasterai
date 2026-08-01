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

    private let model = "gpt-4o-mini"
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
                profile: SceneNavigation.Profile = .full) async throws -> GeneratedScene {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let system = buildSystemPrompt(currentTopical: currentTopical)
        let user = buildUserPrompt(instruction: instruction, vocabBlock: buildVocabBlock(allTiles: allTiles))

        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
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
                                        extraNewWords: carryOver, profile: profile)
    }

    // MARK: - Prompt builders

    private func buildSystemPrompt(currentTopical: [GeneratedTile]) -> String {
        let listing = currentTopical
            .map { tile in
                let name = tile.displayName ?? tile.key.replacingOccurrences(of: "_", with: " ")
                return "\(tile.key) — \(name)"
            }
            .joined(separator: "\n")
        return """
        You are an expert AAC specialist refining the ACTIVITY VOCABULARY of an existing scene for a \
        non-verbal child. The app supplies the child's familiar core board automatically (pronouns, \
        family, needs, feelings, food/drinks/people/body&health) — you ONLY manage the TOPICAL tiles \
        for the activity. The therapist will give an instruction; apply ONLY that change.

        Here are the CURRENT topical tiles (key — what it shows):
        \(listing)

        Rules:
        - Return the COMPLETE updated topical tile list: keep every current topical tile unless the \
          instruction removes it, and add the new ones.
        - When the instruction introduces concrete things, INFER the obvious related items too (a fish \
          pond implies fish, frog, lily pad, water; a creek implies bridge, rock, stream). Pull the \
          full relevant set.
        - Stay topical: do NOT add pronouns, family, feelings, generic foods/drinks, needs, or social \
          words — those are on the core board already.
        - Prefer existing vocabulary keys. Declare any genuinely new concrete word ONCE in the \
          top-level "newWords" array with "displayName" and "wordClass" (one of: \
          \(VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "))); reference it \
          by the same key. Concrete nouns only.
        - \(VocabularyClasses.classSelectionGuidance)
        - Put every topical tile on a SINGLE page; no navigation tiles.

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose. Each tile MUST be \
        an object, never a bare string:
        {
          "name": "string",
          "description": "string",
          "homePageKey": "string",
          "newWords": [ { "key": "frog", "displayName": "frog", "wordClass": "animal" } ],
          "pages": [ { "key": "string", "tiles": [ { "key": "fish", "isAudible": true, "link": "" } ] } ]
        }
        """
    }

    private func buildUserPrompt(instruction: String, vocabBlock: String) -> String {
        """
        Instruction: \(instruction)

        Available vocabulary by category:
        \(vocabBlock)
        """
    }

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            guard tile.wordClass != "navigation", tile.wordClass != PageLink.wordClass else { continue }
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}
