// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageGeneratorService.swift
//  claudeBlast
//
//  Generates a page (with optional sub-pages) from a therapist's goal description.
//

import Foundation

struct PageGeneratorService {
    let apiKey: String

    // MARK: - Prompt configuration

    private let model = "gpt-4o-mini"
    private let temperature = 0.4
    private let maxTokens = 800

    // MARK: - Public API

    func generate(pageGoal: String, pageName: String, allTiles: [TileModel],
                  scenePages: [PageSpec] = [], homePageKey: String = "") async throws -> GeneratedPageResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let sceneBlock = buildSceneBlock(scenePages: scenePages, homePageKey: homePageKey, allTiles: allTiles)
        let system = buildSystemPrompt()
        let user = buildUserPrompt(pageGoal: pageGoal, pageName: pageName, vocabBlock: vocabBlock, sceneBlock: sceneBlock)

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

        return try parsePage(data: data, pageName: pageName, validKeys: Set(allTiles.map(\.key)))
    }

    /// Apply `instruction` to the current page (`currentTiles`), returning a
    /// refined page. Mirrors SceneRefinerService: keep current tiles unless the
    /// instruction removes them; proposed-new words carry forward so an
    /// un-accepted preview's new words survive the round trip.
    func refine(instruction: String, pageName: String,
                currentTiles: [GeneratedTile], allTiles: [TileModel],
                scenePages: [PageSpec] = [], homePageKey: String = "") async throws -> GeneratedPageResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let sceneBlock = buildSceneBlock(scenePages: scenePages, homePageKey: homePageKey, allTiles: allTiles)
        let system = buildRefineSystemPrompt(currentTiles: currentTiles)
        let user = buildUserPrompt(pageGoal: instruction, pageName: pageName, vocabBlock: vocabBlock, sceneBlock: sceneBlock)

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

        let carryOver: [GeneratedNewWord] = currentTiles.compactMap { tile in
            guard tile.isProposedNew, let displayName = tile.displayName, let wordClass = tile.wordClass
            else { return nil }
            return GeneratedNewWord(key: tile.key, displayName: displayName, wordClass: wordClass)
        }
        return try parsePage(data: data, pageName: pageName,
                             validKeys: Set(allTiles.map(\.key)), extraNewWords: carryOver)
    }

    // MARK: - Prompt builders

    private func buildRefineSystemPrompt(currentTiles: [GeneratedTile]) -> String {
        let listing = currentTiles.map { tile in
            let name = tile.displayName ?? tile.key.replacingOccurrences(of: "_", with: " ")
            return "\(tile.key) — \(name)"
        }.joined(separator: "\n")
        return """
        You are a specialist in AAC (Augmentative and Alternative Communication) for non-verbal children, \
        REFINING an existing single page. The caregiver will give an instruction; apply ONLY that change.

        Here are the page's CURRENT tiles (key — what it shows):
        \(listing)

        Rules:
        - Return the COMPLETE updated tile list: keep every current tile unless the instruction removes \
          it, and add the new ones.
        - When the instruction names concrete things, include EVERY one — reuse an existing vocabulary \
          key if present, otherwise declare it new.
        - A NEW word must be a COMMON, CONCRETE thing with a single clear visual (an animal, object, \
          food, place, or person). Declare each new word ONCE in "newWords" with "displayName" and \
          "wordClass" (one of: \(VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "))), \
          then reference it by the same "key". Choose wordClass by what the thing IS: "places" is ONLY a \
          location you go to — for a physical object, tool, or vehicle use "object".
        - Put every tile on the SINGLE page (isAudible=true, empty link); no navigation tiles.
        - Aim for 8–24 tiles.

        Return ONLY valid JSON — no markdown, no prose:
        {
          "key": "string",
          "newWords": [ { "key": "horse", "displayName": "horse", "wordClass": "animal" } ],
          "tiles": [ { "key": "horse", "isAudible": true, "link": "" } ],
          "newPages": []
        }
        """
    }

    private func buildSystemPrompt() -> String {
        """
        You are a specialist in AAC (Augmentative and Alternative Communication) for non-verbal children. \
        Given a goal and vocabulary, select tiles for a single focused page.

        WORLD INFERENCE — From the goal, brainstorm the common, concrete things a child would actually \
        SEE or DO for it: objects, animals, foods, places, people-roles, plus the core action or \
        describing words at the heart of it. Include the obvious items even when the goal did NOT name \
        them (e.g. potty training implies toilet, potty, pee, poop, wipe, flush, wash, dry, underwear). \
        Pull the FULL relevant set, not just a couple — reuse an existing key where one fits and declare \
        the rest as new words.

        You may optionally include navigation tiles that link to new sub-pages when the vocabulary genuinely \
        spans two distinct contexts (e.g. general emotions + detailed feelings). Keep navigation to a minimum — \
        prefer a flat page for focused, single-topic goals.

        Tile rules:
        - Prefer existing tile keys from the provided vocabulary; reuse an existing word \
          rather than proposing a new one whenever a suitable match already exists.
        - When the goal REFERENCES tiles already in the scene (e.g. "the vehicles from the home page", \
          "the animals already on the board"), SELECT those exact existing tiles by key from the \
          "Current scene" listing below — do NOT invent new words for things that are already there.
        - When the goal NAMES specific concrete things (animals, foods, places, objects), \
          include EVERY one named — reuse an existing key if present, otherwise declare it new.
        - A NEW word must be a COMMON, CONCRETE thing with a single clear visual (an animal, \
          object, food, place, or person). NEVER make abstract concepts, feelings, or actions new.
        - Choose wordClass by what the thing IS: "places" is ONLY a location you go to — for a physical \
          object, tool, vehicle, or piece of equipment use "object".
        - Declare every new word ONCE in the top-level "newWords" array with its "displayName" \
          and "wordClass" (one of: \(VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "))), \
          then reference it by the same "key" in tiles. Every tile key MUST be either an existing \
          vocabulary key or a key declared in "newWords".
        - Audible tiles (isAudible=true) contribute to the sentence tray.
        - Navigation tiles must have isAudible=false and a non-empty link matching a key in newPages.
        - Aim for 8–24 tiles on the primary page.

        Return ONLY valid JSON — no markdown, no prose:
        {
          "key": "string",
          "newWords": [
            { "key": "horse", "displayName": "horse", "wordClass": "animal" }
          ],
          "tiles": [
            { "key": "eat", "isAudible": true, "link": "" },
            { "key": "horse", "isAudible": true, "link": "" }
          ],
          "newPages": [
            {
              "key": "string",
              "tiles": [{ "key": "string", "isAudible": true, "link": "" }]
            }
          ]
        }
        """
    }

    private func buildUserPrompt(pageGoal: String, pageName: String, vocabBlock: String, sceneBlock: String) -> String {
        let sceneSection = sceneBlock.isEmpty ? "" : "\nCurrent scene (existing pages and their tiles):\n\(sceneBlock)\n"
        return """
        Page name: \(pageName)
        Goal: \(pageGoal)
        \(sceneSection)
        Available vocabulary by category:
        \(vocabBlock)
        """
    }

    // MARK: - Vocab formatting

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            // Hide structural navigation + page_link tiles so the model treats
            // them as neither selectable words nor page switchers.
            guard tile.wordClass != "navigation", tile.wordClass != PageLink.wordClass else { continue }
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    /// Describe the existing scene's pages and their tiles (key + class) so the
    /// model can honor relational goals like "the vehicles from the home page".
    private func buildSceneBlock(scenePages: [PageSpec], homePageKey: String, allTiles: [TileModel]) -> String {
        guard !scenePages.isEmpty else { return "" }
        let lookup = Dictionary(allTiles.map { ($0.key, $0.wordClass) }, uniquingKeysWith: { a, _ in a })
        return scenePages.map { page in
            let home = page.key == homePageKey ? " [home]" : ""
            let tiles = page.tiles.map { entry in
                "\(entry.key) (\(lookup[entry.key] ?? "?"))"
            }.joined(separator: ", ")
            return "page '\(page.key)'\(home): \(tiles)"
        }.joined(separator: "\n")
    }

    // MARK: - Response parsing

    private func parsePage(data: Data, pageName: String, validKeys: Set<String>,
                           extraNewWords: [GeneratedNewWord] = []) throws -> GeneratedPageResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }

        let jsonText: String
        if let start = content.firstIndex(of: "{"),
           let end = content.lastIndex(of: "}") {
            jsonText = String(content[start...end])
        } else {
            jsonText = content
        }

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw OpenAIError.decodingError("Response JSON was not valid UTF-8")
        }

        let raw = try JSONDecoder().decode(GeneratedPageResponse.self, from: jsonData)
        var newWords = GeneratedNewWord.lookup(from: raw.newWords)
        newWords.merge(GeneratedNewWord.lookup(from: extraNewWords)) { current, _ in current }

        let validPrimary = raw.tiles.compactMap {
            GeneratedTile.sanitize($0, validKeys: validKeys, newWords: newWords)
        }
        guard !validPrimary.isEmpty else {
            throw OpenAIError.decodingError("No valid tiles found in generated page")
        }

        let primaryPage = GeneratedPage(key: pageName, tiles: validPrimary)

        let subPages = raw.newPages.map { sub in
            let validTiles = sub.tiles.compactMap {
                GeneratedTile.sanitize($0, validKeys: validKeys, newWords: newWords)
            }
            return GeneratedPage(key: sub.key, tiles: validTiles)
        }.filter { !$0.tiles.isEmpty }

        return GeneratedPageResult(primaryPage: primaryPage, subPages: subPages)
    }
}
