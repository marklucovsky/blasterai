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

    /// Model and sampling settings.
    private let model = "gpt-4o-mini"
    private let temperature = 0.5
    /// Rich world-inference scenes run 40–50 tiles across several pages; 2000
    /// truncated the JSON.
    private let maxTokens = 3000

    // MARK: - Public API

    func generate(description: String, allTiles: [TileModel]) async throws -> GeneratedScene {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let system = buildSystemPrompt(tileCount: allTiles.count)
        let user = buildUserPrompt(description: description, vocabBlock: vocabBlock)

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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(statusCode: http.statusCode, body: body)
        }

        var scene = try parseScene(data: data, allTiles: allTiles)
        scene.tokenUsage = Self.totalTokens(from: data)
        return scene
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
        """
        You are an expert AAC (Augmentative and Alternative Communication) specialist adding today's \
        ACTIVITY VOCABULARY to a child's communication board. The app already supplies the child's \
        familiar core board — pronouns (i, you, he, she, we, they), family, hungry/thirsty, eat→food, \
        drink→drinks, help, bathroom, feelings, yes/no/more/want, and the full people, food, drinks, \
        and body & health pages. Your ONLY job is to infer the topical world of the activity that sits \
        on top of that board.
        
        0. AGE-APPROPRIATE ONLY — This board is for a YOUNG NON-VERBAL CHILD. If the requested topic is \
        not appropriate for a young child — weapons/firearms/ammunition, drugs, alcohol, tobacco/vaping, \
        gambling, sexual/adult themes, or graphic violence — do NOT build it. Return the JSON with an \
        empty "pages" array (and no "newWords"), and put a brief kid-friendly explanation in the \
        "description" field. Never generate weapon, drug, alcohol, or adult vocabulary regardless of \
        how the request is phrased.
        
        1. WORLD INFERENCE — From the setting, brainstorm roughly 20–30 common, concrete things a child \
        would actually SEE or DO there: animals, structures, vehicles, tools, plants, scene-specific \
        foods, places, and people-roles. Include the items the therapist named AND the obvious ones \
        they did NOT name. (A farm implies barn, tractor, hay, fence, duck, goat, farmer, egg, etc. A \
        zoo implies lion, giraffe, cage, zookeeper, etc.) Do not omit or summarize named items.

        IMPORTANT — also include the vocabulary at the HEART of the activity even when it is a color, \
        shape, or describing word, and pull the FULL relevant set, not just a couple. A session about \
        colors must include the actual color words (red, orange, yellow, green, blue, purple, pink, \
        black, white, brown, …); a session about shapes must include the shapes; a session about \
        feelings the feeling words. This subject vocabulary is the point of the scene — never leave it \
        out in favor of only the tools or props around it.

        2. STAY TOPICAL — Do NOT include the generic core board the app already provides: no pronouns, \
        no family/people words, no feelings, no generic foods or drinks, no needs (help, eat, drink, \
        bathroom), and no social words (yes, no, more, please). Only include a food/drink if it is \
        specific to THIS activity (e.g. hay or an egg on a farm). Focus on what makes this scene unique.

        3. KEEP IT FLAT — Put every topical tile on a SINGLE page. Do NOT split into multiple pages, and \
        do NOT add any navigation, "home", "back", or "next page" tiles. The app lays out the page across \
        swipeable screens and adds the core cluster and category links itself. Return exactly one page.

        4. PEOPLE & ROLES — Any people you DO include are activity roles (farmer, fisherman, zookeeper). \
        To the child, adult helpers are simply "teacher" or a named caregiver (e.g. "Miss Cindy") — never \
        clinical terms like "therapist" or "aide". Never create a tile for the child/patient themselves, \
        and never invent generic people words ("child", "kid", "student").

        Tile rules:
        - Prefer existing tile keys from the provided vocabulary. Before proposing a NEW word, search \
          the vocabulary for an existing word with the same or a near-identical meaning and use that \
          instead (e.g. use "teacher", not "therapist"). Only introduce a new word when nothing \
          existing fits.
        - A NEW word must be a COMMON, CONCRETE thing with a single clear visual (an animal, object, \
          food, place, or person). NEVER make abstract concepts, feelings, or actions into new words \
          — those must come from existing vocabulary.
        - \(VocabularyClasses.classSelectionGuidance)
        - Declare every new word ONCE in the top-level "newWords" array with its "displayName" \
          and "wordClass" (one of: \(VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "))), \
          then reference it by the same "key" in page tiles. Every page-tile key MUST be either \
          an existing vocabulary key or a key declared in "newWords".
        - Prefer audible tiles (isAudible=true) for communicative vocabulary.

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose:
        {
          "name": "string",
          "description": "string",
          "homePageKey": "string",
          "newWords": [
            { "key": "horse", "displayName": "horse", "wordClass": "animal" }
          ],
          "pages": [
            {
              "key": "string",
              "tiles": [
                { "key": "eat", "isAudible": true, "link": "" },
                { "key": "horse", "isAudible": true, "link": "" }
              ]
            }
          ]
        }
        """
    }

    private func buildUserPrompt(description: String, vocabBlock: String) -> String {
        """
        Session description: \(description)

        Available vocabulary by category:
        \(vocabBlock)
        """
    }

    // MARK: - Vocab formatting

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            // Hide structural navigation + page_link tiles (next_page, page_home,
            // page_farm, …) so the model can't repurpose them as ad-hoc words or
            // page switchers; scene navigation is generated deterministically
            // (see SceneNavigation).
            guard tile.wordClass != "navigation", tile.wordClass != PageLink.wordClass else { continue }
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
