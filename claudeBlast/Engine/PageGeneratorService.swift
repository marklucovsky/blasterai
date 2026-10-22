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

    /// The model is `ModelID.sceneAuthoring` — page generation is scene authoring.
    private let temperature = 0.4
    private let maxTokens = 800

    // MARK: - Public API

    func generate(pageGoal: String, pageName: String, allTiles: [TileModel],
                  scenePages: [PageSpec] = [], homePageKey: String = "") async throws -> GeneratedPageResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let body = requestBody(pageGoal: pageGoal, pageName: pageName, allTiles: allTiles,
                               scenePages: scenePages, homePageKey: homePageKey)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: .pageGenerate, endpoint: OpenAIEndpoint.chatCompletions)

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

        let body = refineRequestBody(instruction: instruction, pageName: pageName,
                                     currentTiles: currentTiles, allTiles: allTiles,
                                     scenePages: scenePages, homePageKey: homePageKey)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: .pageRefine, endpoint: OpenAIEndpoint.chatCompletions)
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

    // MARK: - Request bodies
    // Pure, so the prompt fixtures (`PromptFixtureTests`) can pin exactly what
    // is sent without a network call.

    func requestBody(pageGoal: String, pageName: String, allTiles: [TileModel],
                     scenePages: [PageSpec] = [], homePageKey: String = "") -> [String: Any] {
        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let sceneBlock = buildSceneBlock(scenePages: scenePages, homePageKey: homePageKey, allTiles: allTiles)
        let system = buildSystemPrompt()
        let user = buildUserPrompt(pageGoal: pageGoal, pageName: pageName, vocabBlock: vocabBlock, sceneBlock: sceneBlock)
        return body(system: system, user: user)
    }

    func refineRequestBody(instruction: String, pageName: String,
                           currentTiles: [GeneratedTile], allTiles: [TileModel],
                           scenePages: [PageSpec] = [], homePageKey: String = "") -> [String: Any] {
        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let sceneBlock = buildSceneBlock(scenePages: scenePages, homePageKey: homePageKey, allTiles: allTiles)
        let system = buildRefineSystemPrompt(currentTiles: currentTiles)
        let user = buildUserPrompt(pageGoal: instruction, pageName: pageName, vocabBlock: vocabBlock, sceneBlock: sceneBlock)
        return body(system: system, user: user)
    }

    private func body(system: String, user: String) -> [String: Any] {
        ChatRequest.body(model: ModelID.sceneAuthoring,
                         messages: [["role": "system", "content": system],
                                    ["role": "user", "content": user]],
                         temperature: temperature, maxTokens: maxTokens)
    }

    // MARK: - Prompt builders

    private func buildRefineSystemPrompt(currentTiles: [GeneratedTile]) -> String {
        let listing = currentTiles.map { tile in
            let name = tile.displayName ?? tile.key.replacingOccurrences(of: "_", with: " ")
            return "\(tile.key) — \(name)"
        }.joined(separator: "\n")
        return PromptTemplate.render("page_refine_system", [
            "current_tiles": listing,
            "class_guidance": VocabularyClasses.classSelectionGuidance,
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
        ])
    }

    private func buildSystemPrompt() -> String {
        PromptTemplate.render("page_generate_system", ["class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", ")])
    }

    private func buildUserPrompt(pageGoal: String, pageName: String, vocabBlock: String, sceneBlock: String) -> String {
        let sceneSection = sceneBlock.isEmpty ? "" : "\nCurrent scene (existing pages and their tiles):\n\(sceneBlock)\n"
        return PromptTemplate.render("page_user", [
            "page_name": pageName,
            "goal": pageGoal,
            "scene_section": sceneSection,
            "vocab_block": vocabBlock,
        ])
    }

    // MARK: - Vocab formatting

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            // Hide structural navigation + page_link tiles so the model treats
            // them as neither selectable words nor page switchers.
            guard !tile.isStructuralChrome else { continue }
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
