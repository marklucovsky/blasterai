// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TopicWordsService.swift
//  claudeBlast
//
//  The words for one page about a topic, ranked by usefulness. The model
//  chooses words; code places them (`PagePlacer`) — so one prompt serves a
//  scene's home page and a leaf page alike, and only the template differs.
//  Prompts: `prompt_topic_words_{system,user}.txt`; evaluated in
//  `docs/eval/scenes.md` and mirrored by `tools/eval/prompts.topic_words_body`.
//

import Foundation

struct TopicWordsService {
    let apiKey: String

    /// Words the page holds; anything after becomes overflow.
    static let budget = 25
    /// Most words the model may return.
    static let maxWords = 32

    /// Sampling settings. The model is `ModelID.sceneAuthoring`; `ChatRequest`
    /// drops the temperature for a model that rejects it.
    private let temperature = 0.5
    private let maxTokens = 3000

    /// The scene a new page is being added to. Its name, the summary the model
    /// wrote for it (`descriptionText`, which syncs — the caregiver's own brief
    /// stays on the device) and its home page's words: a short page topic
    /// ("costumes") takes the rest from here (19 of 24 vs 2 of 24 in the eval).
    struct SceneContext {
        var name: String
        var description: String
        var words: [String]

        /// `scene` as the prompt sees it: its home page's words, not its
        /// links, gaps or folders.
        init(name: String, description: String, words: [String]) {
            self.name = name
            self.description = description
            self.words = words
        }

        init(_ scene: BlasterScene) {
            let home = scene.page(withKey: scene.homePageKey)?.tiles ?? []
            self.init(name: scene.name, description: scene.descriptionText,
                      words: home.filter { $0.link.isEmpty && !$0.isSpacer }.map(\.key))
        }
    }

    /// What the model returned, before matching to the vocabulary.
    struct Response: Decodable {
        struct Word: Decodable {
            let word: String
            let wordClass: String?
        }
        var refused: Bool
        var name: String
        var description: String
        var words: [Word]
        /// Total tokens billed, attached after the call; not in the model's JSON.
        var tokenUsage: Int? = nil

        private enum CodingKeys: String, CodingKey { case refused, name, description, words }

        /// Tolerant like `GeneratedTile`'s: a missing field is empty, and a
        /// word the model wrote as a bare string still counts.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            refused = (try? c.decode(Bool.self, forKey: .refused)) ?? false
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            description = (try? c.decode(String.self, forKey: .description)) ?? ""
            var list = (try? c.nestedUnkeyedContainer(forKey: .words))
            var out: [Word] = []
            while let l = list, !l.isAtEnd {
                if let w = try? list!.decode(Word.self) {
                    out.append(w)
                } else if let s = try? list!.decode(String.self) {
                    out.append(Word(word: s, wordClass: nil))
                } else {
                    _ = try? list!.decode(Discarded.self)
                }
            }
            words = out
        }

        private struct Discarded: Decodable {}
    }

    /// The topic is not one for a young child's board. `explanation` is the
    /// model's own kid-friendly reason, shown as is.
    struct Refusal: LocalizedError {
        let explanation: String
        var errorDescription: String? {
            explanation.isEmpty ? "This topic can't be made into a board." : explanation
        }
    }

    // MARK: - Public API

    func generate(description: String, template: PageTemplate.Kind,
                  scene: SceneContext? = nil, allTiles: [TileModel]) async throws -> Response {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let body = requestBody(description: description, template: template,
                               scene: scene, allTiles: allTiles)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await OpenAIClient.send(
            request, cause: template == .home ? .sceneGenerate : .pageGenerate,
            endpoint: OpenAIEndpoint.chatCompletions)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: http.statusCode,
                                        body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }
        var parsed = try Self.parse(content: content)
        if parsed.refused { throw Refusal(explanation: parsed.description) }
        parsed.tokenUsage = (json["usage"] as? [String: Any])?["total_tokens"] as? Int
        return parsed
    }

    /// The exact chat-completions body `generate` sends. Pure, so the prompt
    /// fixtures (`PromptFixtureTests`) can pin it without a network call.
    func requestBody(description: String, template: PageTemplate.Kind,
                     scene: SceneContext? = nil, allTiles: [TileModel]) -> [String: Any] {
        let system = PromptTemplate.render("topic_words_system", [
            "budget": String(Self.budget),
            "max_words": String(Self.maxWords),
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
        ])
        let frame = template.frameKeys
        let exclude = frame.isEmpty ? "" :
            "\n\nThis page already has these words, always in the same place — never return them: "
            + frame.map(Self.spoken).joined(separator: ", ") + "."
        let user = PromptTemplate.render("topic_words_user", [
            "description": description,
            "vocab_block": SceneGeneratorService.vocabBlock(allTiles: allTiles),
            "exclude_rule": exclude,
            "scene_context": scene.map(Self.sceneContext) ?? "",
        ])
        return ChatRequest.body(model: ModelID.sceneAuthoring,
                                messages: [["role": "system", "content": system],
                                           ["role": "user", "content": user]],
                                temperature: temperature, maxTokens: maxTokens)
    }

    /// Decode the model's JSON, ignoring any prose around it.
    static func parse(content: String) throws -> Response {
        let text: String
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") {
            text = String(content[start...end])
        } else {
            text = content
        }
        guard let data = text.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw OpenAIError.decodingError("Response was not the expected JSON")
        }
        return response
    }

    /// A scene whose home page is `response`'s words, laid out on the home
    /// template when it is shown and built. Words the frame or the system row
    /// already has are left out; the rest are cut at the budget.
    static func scene(from response: Response, systemHome: PageSpec?,
                      allTiles: [TileModel]) throws -> GeneratedScene {
        let taken = PageFrame(systemHome: systemHome, kind: .home).keys
            .union(PageTemplate.homeFrame)
        let selection = TopicWordMatcher.select(response.words, excluding: taken, allTiles: allTiles)
        guard !selection.page.isEmpty else {
            throw OpenAIError.decodingError("No words came back for this topic")
        }
        return GeneratedScene(name: response.name, description: response.description,
                              homePageKey: "home",
                              pages: [GeneratedPage(key: "home", tiles: selection.page)],
                              tokenUsage: response.tokenUsage, template: .home)
    }

    /// A page added to a scene, from `response`'s words: laid out on the leaf
    /// template when it is shown and built, so words the system row already
    /// has are left out, and the rest cut at the budget.
    static func page(from response: Response, key: String, systemHome: PageSpec?,
                     allTiles: [TileModel]) throws -> GeneratedPageResult {
        let taken = PageFrame(systemHome: systemHome, kind: .leaf).keys
        let selection = TopicWordMatcher.select(response.words, excluding: taken, allTiles: allTiles)
        guard !selection.page.isEmpty else {
            throw OpenAIError.decodingError("No words came back for this page")
        }
        return GeneratedPageResult(primaryPage: GeneratedPage(key: key, tiles: selection.page),
                                   subPages: [])
    }

    // MARK: - Prompt pieces

    nonisolated private static func sceneContext(_ scene: SceneContext) -> String {
        PromptTemplate.render("topic_scene_context", [
            "scene_name": scene.name,
            "scene_description": scene.description,
            "scene_words": scene.words.map(spoken).joined(separator: ", "),
        ])
    }

    /// A key as the prompt says it: `all_done` → "all done".
    nonisolated private static func spoken(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
    }
}
