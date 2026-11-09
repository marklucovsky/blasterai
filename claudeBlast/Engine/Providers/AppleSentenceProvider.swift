// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppleSentenceProvider.swift
//  claudeBlast
//

import Foundation
import FoundationModels

/// Output schema for the on-device Foundation Models session.
@available(iOS 26, *)
@Generable
struct GeneratedSentence {
    @Guide(description: "A single short friendly sentence using the given words. No markdown.")
    var sentence: String
}

enum AppleProviderError: Error, LocalizedError {
    case notAvailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device."
        case .emptyResponse:
            return "Apple Intelligence returned an empty response."
        }
    }
}

@available(iOS 26, *)
struct AppleSentenceProvider: SentenceProvider {
    let displayName = "Apple Intelligence"

    // Minimal system instruction for the on-device ~3B model.
    // Avoids any mention of children, disabilities, age — Apple's safety
    // guardrails flag those terms combined with everyday words.
    private static let systemInstruction = """
    You are a friendly sentence builder. Given a list of words, \
    combine them into one short sentence from a first-person perspective. \
    The speaker usually wants something for themselves. \
    For example, "dad" and "cheese" becomes "Dad, can I have some cheese?" \
    Output exactly one sentence.
    """

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        conversationContext: [String]
    ) async throws -> SentenceResult {
        guard SystemLanguageModel.default.isAvailable else {
            throw AppleProviderError.notAvailable
        }

        let session = LanguageModelSession(
            instructions: Self.systemInstruction
        )

        // Include word class to disambiguate (e.g. "play" as action vs noun)
        let words = tiles.map { VocabularyClasses.promptLabel($0.value, wordClass: $0.wordClass) }
        let userMessage = "Words: " + words.joined(separator: ", ")

        let response = try await session.respond(
            to: userMessage,
            generating: GeneratedSentence.self
        )

        let text = response.content.sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppleProviderError.emptyResponse
        }

        return SentenceResult(text: text)
    }
}

/// Availability check usable from non-availability-gated code.
enum AppleIntelligenceAvailability {
    static var isSupported: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }
}
