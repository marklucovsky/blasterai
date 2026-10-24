// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PromptFixtureTests.swift
//  claudeBlastTests
//
//  Pins the exact chat-completions request every text surface sends — model,
//  sampling, and every message — for a fixed set of inputs, as JSON files in
//  `claudeBlastTests/Fixtures/prompts/`.
//
//  ## Why
//
//  The eval harness (`tools/eval/`) is Python, so prompts can be iterated
//  without a build. That only means anything if Python sends what the app
//  sends. These fixtures are the contract between the two: this suite proves
//  the Swift side renders them, and `tools/eval/check_prompt_parity.py` proves
//  the Python side does. Neither can drift without one of the two going red.
//
//  They are also what made moving the prompts out of Swift string literals
//  safe — the move had to leave every fixture byte-identical.
//
//  ## Changing a prompt on purpose
//
//  Re-record, and review the fixture diff as part of the change:
//
//      TEST_RUNNER_RECORD_PROMPT_FIXTURES=1 xcodebuild ... \
//        -only-testing:claudeBlastTests/PromptFixtureTests test
//
//  Recording writes next to this file via `#filePath`, which the simulator can
//  reach because it shares the host filesystem.

import Foundation
import Testing
@testable import claudeBlast

@MainActor
struct PromptFixtureTests {

    // MARK: - Sentences

    @Test("Sentence: plain request at each generating stage")
    func sentencePlain() throws {
        for stage in [BrownsStage.twoThree, .fourPlus] {
            try check("sentence__mom_eat_pizza__\(stage.rawValue)",
                      sentenceBody(stage: stage, tiles: Self.momEatPizza))
        }
    }

    @Test("Sentence: conversation history becomes prior assistant turns")
    func sentenceHistory() throws {
        try check("sentence__she_pool__history",
                  sentenceBody(stage: .twoThree,
                               tiles: [Self.tile("she", "people"), Self.tile("pool", "places")],
                               history: ["Mom, I am hungry.", "Can I have some juice?"]))
    }

    @Test("Sentence: escalation carries the rung it escalates from, and holds past the top")
    func sentenceEscalation() throws {
        for count in [1, 3, 4] {
            try check("sentence__chocolate__escalate_\(count)",
                      sentenceBody(stage: .twoThree, tiles: [Self.tile("chocolate", "food")],
                                   repetition: count, prior: "I want chocolate!"))
        }
    }

    @Test("Sentence: caregiver refine adds the directive and the sentence being revised")
    func sentenceRefine() throws {
        try check("sentence__mom_eat_pizza__refine",
                  sentenceBody(stage: .twoThree, tiles: Self.momEatPizza,
                               refine: ("Mom, I want pizza.", "make it a question")))
    }

    // MARK: - Authoring

    @Test("Scene generate")
    func sceneGenerate() throws {
        try check("scene_generate__potty_training",
                  SceneGeneratorService(apiKey: "").requestBody(
                    description: "Potty training at home: asking to go, saying when done, washing hands.",
                    allTiles: Self.vocabulary))
    }

    @Test("Scene refine")
    func sceneRefine() throws {
        try check("scene_refine__add_bath",
                  SceneRefinerService(apiKey: "").requestBody(
                    instruction: "add bath time",
                    currentTopical: Self.topical,
                    allTiles: Self.vocabulary))
    }

    @Test("Topic words: a scene's home page, a leaf page, a page added to a scene")
    func topicWords() throws {
        let service = TopicWordsService(apiKey: "")
        try check("topic_words__home",
                  service.requestBody(description: "visiting the fire station with my class",
                                      template: .home, allTiles: Self.vocabulary))
        try check("topic_words__leaf",
                  service.requestBody(description: "fire trucks", template: .leaf,
                                      allTiles: Self.vocabulary))
        try check("topic_words__addpage",
                  service.requestBody(description: "costumes", template: .leaf,
                                      scene: .init(name: "Halloween Night",
                                                   description: "Trick-or-treating with the family.",
                                                   words: ["pumpkin", "trick_or_treat", "candy"]),
                                      allTiles: Self.vocabulary))
    }

    @Test("Page generate, with and without a scene listing")
    func pageGenerate() throws {
        let service = PageGeneratorService(apiKey: "")
        try check("page_generate__potty",
                  service.requestBody(pageGoal: "potty training", pageName: "potty",
                                      allTiles: Self.vocabulary))
        try check("page_generate__vehicles_from_home",
                  service.requestBody(pageGoal: "the vehicles from the home page", pageName: "vehicles",
                                      allTiles: Self.vocabulary,
                                      scenePages: Self.scenePages, homePageKey: "home"))
    }

    @Test("Page refine")
    func pageRefine() throws {
        try check("page_refine__add_bath",
                  PageGeneratorService(apiKey: "").refineRequestBody(
                    instruction: "add bath time", pageName: "potty",
                    currentTiles: Self.topical, allTiles: Self.vocabulary,
                    scenePages: Self.scenePages, homePageKey: "home"))
    }

    @Test("Tile suggestions")
    func tileSuggest() throws {
        try check("tile_suggest__dentist",
                  TileSuggestionService(apiKey: "").requestBody(
                    goal: "a visit to the dentist", allTiles: Self.vocabulary))
    }

    @Test("Word moderation rubric")
    func moderationRubric() throws {
        try check("moderation_rubric__mixed",
                  WordModerationService.rubricRequestBody(words: ["puppy", "poop", "beer", "toy gun"]))
    }

    /// Values the app derives in code rather than from a template — the class
    /// list, the bundled vocabulary blocks, the stage descriptors. Python reads
    /// these instead of re-deriving them, so this file is part of the contract.
    @Test("App-derived prompt inputs")
    func appInputs() throws {
        func block(_ tiles: [TileModel]) -> String {
            var byClass: [String: [String]] = [:]
            for t in tiles { byClass[t.wordClass, default: []].append(t.key) }
            return byClass.keys.sorted().map { "\($0): \(byClass[$0]!.joined(separator: ", "))" }
                .joined(separator: "\n")
        }
        var stages: [String: String] = [:]
        for stage in BrownsStage.allCases {
            stages[stage.rawValue] = stage.promptDescriptor(escalating: false)
            stages[stage.rawValue + "/escalating"] = stage.promptDescriptor(escalating: true)
        }
        try check("_inputs", [
            "class_list": VocabularyClasses.caregiverSelectable.map(\.name).joined(separator: ", "),
            "class_guidance": VocabularyClasses.classSelectionGuidance,
            "vocab_block": block(Self.vocabulary.filter { !$0.isStructuralChrome }),
            "vocab_block_all": block(Self.vocabulary),
            "stages": stages,
        ])
    }

    // MARK: - Inputs

    static let momEatPizza = [tile("mom", "people"), tile("eat", "actions"), tile("pizza", "food")]

    /// A topical layer with one existing word and one proposed new word, so the
    /// refine listings exercise both the `displayName` and key fallbacks.
    static let topical = [
        GeneratedTile(key: "toilet", isAudible: true, link: ""),
        GeneratedTile(key: "flush", isAudible: true, link: "", displayName: "flush", wordClass: "object"),
    ]

    static let scenePages = [
        PageSpec(key: "home", tiles: [TileEntry(key: "car"), TileEntry(key: "bus"), TileEntry(key: "eat")]),
        PageSpec(key: "potty", tiles: [TileEntry(key: "toilet")]),
    ]

    /// The bundled vocabulary, in file order — the order a fresh install's
    /// vocabulary block is built in.
    static let vocabulary: [TileModel] = {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TileModelCodable].self, from: data)
        else { return [] }
        return decoded.map(TileModel.init(from:))
    }()

    static func tile(_ key: String, _ wordClass: String) -> TileSelection {
        TileSelection(key: key, value: key, wordClass: wordClass)
    }

    /// Build a sentence request the way `SentenceEngine.generate` does.
    func sentenceBody(stage: BrownsStage, tiles: [TileSelection], history: [String] = [],
                      repetition: Int = 0, prior: String? = nil,
                      refine: (original: String, instruction: String)? = nil) -> [String: Any] {
        var builder = SentencePromptBuilder(brownsStage: stage)
        builder.repetitionCount = repetition
        if repetition > 0 { builder.escalatingFrom = prior }
        builder.conversationContext = history
        var system = builder.buildSystemPrompt()
        if let refine {
            system.append(PromptMessage(role: .system, content: SentencePromptBuilder.refinePrompt(
                previous: refine.original, instruction: refine.instruction)))
        }
        let context = SentencePromptBuilder.context(
            history: history, escalatingFrom: repetition > 0 ? prior : nil,
            refining: refine?.original, userPrompt: builder.formatUserPrompt(tiles: tiles))
        return OpenAISentenceProvider.requestBody(systemPrompt: system, conversationContext: context)
    }

    // MARK: - Fixture plumbing

    static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()        // Eval/
        .deletingLastPathComponent()        // claudeBlastTests/
        .appendingPathComponent("Fixtures/prompts", isDirectory: true)

    static var recording: Bool {
        ProcessInfo.processInfo.environment["RECORD_PROMPT_FIXTURES"] == "1"
    }

    func check(_ name: String, _ body: [String: Any]) throws {
        #expect(!Self.vocabulary.isEmpty, "bundled vocabulary did not load")
        var data = try JSONSerialization.data(
            withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        let url = Self.fixtureDir.appendingPathComponent("\(name).json")
        if Self.recording {
            try FileManager.default.createDirectory(at: Self.fixtureDir, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        guard let expected = try? Data(contentsOf: url) else {
            Issue.record("No fixture \(name).json — record with TEST_RUNNER_RECORD_PROMPT_FIXTURES=1")
            return
        }
        #expect(data == expected,
                "\(name): request differs from its fixture. If the prompt changed on purpose, re-record and review the diff.")
    }
}
