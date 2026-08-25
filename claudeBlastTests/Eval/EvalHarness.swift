// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  EvalHarness.swift
//  claudeBlastTests
//
//  Developer/build-time AI-quality harness — NOT shipped on-device. Drives the
//  real generation prompts through a configurable model and (in A2) scores the
//  output. Lives in the test target and only makes network calls when explicitly
//  enabled (RUN_LIVE_EVAL=1 + a key), so normal CI/test runs stay free and fast.
//
//  Design note — subject vs. judge are decoupled by construction. Both the model
//  under test ("subject") and the future LLM judge run through the same
//  `EvalChatClient`, differing only by their `EvalModelConfig`. That keeps the
//  judge model independent of the test model from day one, even while we start
//  with a single model for both.

import Foundation
@testable import claudeBlast

// MARK: - Model configuration

/// A single (model, key, sampling) target. Two of these — a subject and a judge
/// — are what let the harness test one model and grade it with another.
struct EvalModelConfig {
    /// Human label for reports ("subject" / "judge").
    var role: String
    /// OpenAI model id, e.g. "gpt-4o-mini" (subject default) or "gpt-4o" (judge).
    var model: String
    var temperature: Double
    var apiKey: String

    /// The model actually under test today. Mirrors production
    /// (`OpenAISentenceProvider` / `SentenceGeneratorService` use gpt-4o-mini).
    static func subject(apiKey: String, model: String = "gpt-4o-mini") -> EvalModelConfig {
        EvalModelConfig(role: "subject", model: model, temperature: 0.3, apiKey: apiKey)
    }

    /// The grader. Defaults to a stronger model than the subject; deliberately a
    /// separate config so it can be pointed at any model (A2 will let this be a
    /// different provider entirely). Low temperature for stable scoring.
    static func judge(apiKey: String, model: String = "gpt-4o") -> EvalModelConfig {
        EvalModelConfig(role: "judge", model: model, temperature: 0.0, apiKey: apiKey)
    }
}

// MARK: - Chat client

struct EvalChatMessage {
    let role: String   // "system" | "user" | "assistant"
    let content: String
}

enum EvalHarnessError: Error, CustomStringConvertible {
    case http(Int, String)
    case decode(String)

    var description: String {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decode(let why):          return "decode: \(why)"
        }
    }
}

/// Minimal OpenAI chat-completions client used by both subject generation and
/// (A2) the judge. Kept separate from the app's `OpenAISentenceProvider` because
/// that hardcodes the production model; the harness needs the model to be a knob.
struct EvalChatClient {
    let config: EvalModelConfig

    func complete(_ messages: [EvalChatMessage], maxTokens: Int = 600) async throws -> String {
        let body: [String: Any] = [
            "model": config.model,
            "temperature": config.temperature,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EvalHarnessError.http(0, "no response")
        }
        guard http.statusCode == 200 else {
            throw EvalHarnessError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw EvalHarnessError.decode("no message content")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Subject generation (real prompts, configurable model)

/// Runs the *production* sentence prompts (`SentencePromptBuilder`) through the
/// subject model. Faithful to what ships — `OpenAISentenceProvider` sends these
/// same messages — while letting the harness vary the model.
struct SubjectRunner {
    let client: EvalChatClient
    /// Brown's Stage used for the prompt; mirrors the resolver's fallback so
    /// the eval isn't coupled to a specific child profile. Override it to
    /// compare stages against each other.
    ///
    /// Stage I is the resolver's floor but makes no API call in the app, so
    /// the eval defaults to II-III — the first stage that actually generates.
    var brownsStage: BrownsStage = .twoThree

    /// Single-shot generation for one tile combination.
    func generate(tiles: [TileSelection], repetition: Int = 0,
                  priorSentences: [String] = []) async throws -> String {
        var builder = SentencePromptBuilder(brownsStage: brownsStage)
        builder.repetitionCount = repetition
        builder.conversationContext = priorSentences
        let system = builder.buildSystemPrompt().map { EvalChatMessage(role: "system", content: $0.content) }
        let user = EvalChatMessage(role: "user", content: builder.formatUserPrompt(tiles: tiles))
        // Prior turns as assistant context, mirroring OpenAISentenceProvider.
        let context = priorSentences.map { EvalChatMessage(role: "assistant", content: $0) }
        return try await client.complete(system + context + [user])
    }

    /// Generate an escalation ladder: step 0 (baseline) then `extraSteps`
    /// repeats, each carrying the prior sentence forward as context — the same
    /// shape SentenceEngine uses for replay/escalation.
    func generateEscalationLadder(tiles: [TileSelection], extraSteps: Int) async throws -> [String] {
        var ladder: [String] = []
        for step in 0...extraSteps {
            let prior = Array(ladder.suffix(5))
            let text = try await generate(tiles: tiles, repetition: step, priorSentences: prior)
            ladder.append(text)
        }
        return ladder
    }
}

// MARK: - Environment gating

enum EvalEnv {
    /// Live generation/judging is opt-in: set RUN_LIVE_EVAL=1 in the scheme.
    static var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["RUN_LIVE_EVAL"] == "1"
    }

    /// Key for live runs: explicit env var wins, else the device Keychain vault.
    static var apiKey: String? {
        if let k = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespaces), !k.isEmpty { return k }
        return OpenAIKeyVault.currentKey()
    }

    /// Optional override for the subject model (EVAL_SUBJECT_MODEL).
    static var subjectModel: String {
        ProcessInfo.processInfo.environment["EVAL_SUBJECT_MODEL"] ?? "gpt-4o-mini"
    }

    /// Optional override for the judge model (EVAL_JUDGE_MODEL).
    static var judgeModel: String {
        ProcessInfo.processInfo.environment["EVAL_JUDGE_MODEL"] ?? "gpt-4o"
    }

    /// Optional file to append generated ladders/sentences to
    /// (EVAL_TRANSCRIPT_PATH).
    ///
    /// A live run that *passes* produces no failure message, and `print` from a
    /// test never reaches the `.xcresult` bundle — so from the command line a
    /// green run is completely opaque. That is the wrong way round: escalation
    /// quality is a judgement about wording, and the wording is exactly what a
    /// pass hides. Point this at a file to read what the model actually said.
    static var transcriptPath: String? {
        ProcessInfo.processInfo.environment["EVAL_TRANSCRIPT_PATH"]?
            .trimmingCharacters(in: .whitespaces)
            .nilIfEmpty
    }

    /// Append a block to the transcript file, if one was requested.
    static func appendTranscript(_ text: String) {
        guard let path = transcriptPath else { return }
        let block = text + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(block.utf8))
            try? handle.close()
        } else {
            try? block.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
