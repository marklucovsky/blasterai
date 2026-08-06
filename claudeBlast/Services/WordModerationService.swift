// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordModerationService.swift
//  claudeBlast
//
//  Audits caregiver- and AI-proposed NEW vocabulary words BEFORE they become
//  tiles and BEFORE they are sent to image generation. Layered, most→least
//  authoritative:
//    1. Offline blocklist — a tiny hard-coded backstop for unambiguous terms,
//       so the worst cases are caught even with no network. NOT the primary gate.
//    2. OpenAI /v1/moderations (free) — deterministic policy net (sexual, hate,
//       self-harm, violence-as-content). Catches explicit content the rubric
//       might occasionally miss.
//    3. gpt-4o-mini age-appropriateness rubric — THE primary gate. Rates each
//       word for a young non-verbal child's AAC board: appropriate / questionable
//       / inappropriate. This is what catches CATEGORIES the other two can't —
//       weapons, drugs, alcohol, gambling, adult themes — which /v1/moderations
//       does NOT flag (a lone "gun" isn't a policy violation) and a static list
//       can never fully enumerate.
//
//  Verdict → caller: `blocked` never materializes / never reaches image-gen and
//  is recorded on the tile (`retiredReason`); `flagged` is surfaced for review.
//

import Foundation
import SwiftData

/// Outcome of auditing one proposed new word.
enum WordVerdict: Equatable {
    case allowed
    /// Must not materialize or reach image-gen — a hard block. `reason` is shown
    /// to the caregiver as the record of why the word was hidden.
    case blocked(reason: String)
    /// Legal but off for a young board — surface for caregiver review.
    case flagged(reason: String)

    var isBlocked: Bool { if case .blocked = self { return true }; return false }
    var isFlagged: Bool { if case .flagged = self { return true }; return false }
}

struct WordModerationService {
    let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    /// Offline HARD-BLOCK backstop for unambiguous terms — covers the worst cases
    /// when the network is unavailable. Intentionally short; the rubric is the real
    /// gate. Lowercased.
    static let localBlocklist: Set<String> = [
        "sex", "porn", "nigger", "faggot",
    ]

    /// Legal but sensitive — anatomical terms a caregiver may legitimately need
    /// (body/health/safety education). Flagged for the caregiver to decide, NOT
    /// blocked. (Per Mark: penis/vagina are caregiver choice, not auto-hidden.)
    static let localFlagList: Set<String> = [
        "penis", "vagina",
    ]

    /// Audit a batch of proposed words. Returns a verdict per input word (keyed by
    /// the ORIGINAL string). Runs the three tiers in order, short-circuiting each
    /// word once it's blocked; a failed network tier leaves the prior verdict.
    func audit(_ words: [String]) async -> [String: WordVerdict] {
        var result: [String: WordVerdict] = [:]
        var pending: [String] = []

        // Tier 1 — offline local lists (block + sensitive-flag).
        for word in words {
            let key = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.localBlocklist.contains(key) {
                result[word] = .blocked(reason: "blocklisted term")
            } else if Self.localFlagList.contains(key) {
                result[word] = .flagged(reason: "sensitive — review before adding")
            } else {
                result[word] = .allowed
                pending.append(word)
            }
        }
        guard !pending.isEmpty, !apiKey.isEmpty else { return result }

        // Tier 2 — free moderations endpoint (hard policy).
        if let flags = try? await moderationFlags(for: pending) {
            for (word, categories) in flags where !categories.isEmpty {
                result[word] = .blocked(reason: "policy: \(categories.sorted().joined(separator: ", "))")
            }
        }
        let stillAllowed = pending.filter { result[$0] == .allowed }
        guard !stillAllowed.isEmpty else { return result }

        // Tier 3 — age-appropriateness rubric (the real gate).
        if let ratings = try? await appropriatenessRatings(for: stillAllowed) {
            for (word, rating) in ratings {
                switch rating {
                case .inappropriate:
                    result[word] = .blocked(reason: "not appropriate for a young board")
                case .questionable:
                    result[word] = .flagged(reason: "may be inappropriate for a young board")
                case .appropriate:
                    break
                }
            }
        }
        return result
    }

    // MARK: - Tier 3: age-appropriateness rubric (gpt-4o-mini)

    enum Rating: String { case appropriate, questionable, inappropriate }

    private func appropriatenessRatings(for words: [String]) async throws -> [String: Rating] {
        let system = """
        You screen vocabulary words for a YOUNG NON-VERBAL CHILD's AAC communication \
        board. For every input word, rate it exactly one of: "appropriate", \
        "questionable", "inappropriate".
        - inappropriate: weapons/firearms/ammunition, drugs, alcohol, tobacco/vaping, \
          gambling, sexual/adult themes, graphic violence, or anything unsuitable for a \
          young child's board.
        - questionable: borderline — mild risk, or only appropriate in narrow contexts.
        - appropriate: ordinary everyday child vocabulary (people, food, animals, \
          actions, feelings, places, toys, school, home).
        Return ONLY JSON, no prose: {"ratings": {"<word>": "<rating>", ...}} with an \
        entry for every input word, keyed by the word exactly as given.
        """
        let content = try await chat(system: system, user: words.joined(separator: ", "))
        return Self.parseRatings(content, words: words)
    }

    /// Parse the rubric's `{"ratings": {...}}` payload. `nonisolated static` + pure
    /// so it's unit-testable without a network round-trip. Unknown/missing words
    /// default to `.appropriate` (fail-open on the rubric — the blocklist +
    /// moderations tiers already caught the unambiguous cases).
    nonisolated static func parseRatings(_ content: String, words: [String]) -> [String: Rating] {
        guard let start = content.firstIndex(of: "{"),
              let data = String(content[start...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ratings = json["ratings"] as? [String: Any] else { return [:] }
        var out: [String: Rating] = [:]
        for word in words {
            if let raw = ratings[word] as? String, let r = Rating(rawValue: raw.lowercased()) {
                out[word] = r
            }
        }
        return out
    }

    private func chat(system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw OpenAIError.decodingError("no rubric content")
        }
        return text
    }

    // MARK: - Tier 2: OpenAI /v1/moderations

    private func moderationFlags(for words: [String]) async throws -> [String: [String]] {
        let url = URL(string: "https://api.openai.com/v1/moderations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "omni-moderation-latest",
            "input": words,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        return Self.parseFlags(data: data, words: words)
    }

    // MARK: - Add-Tiles path (persist review state on materialized tiles)

    /// Audit already-materialized NEW tiles (the Add-Tiles flow has no Accept gate)
    /// and stamp their persistent review state so the page editor + scene list can
    /// surface it and the child grid can hide the unresolved ones:
    ///   • blocked  → `isRetired` + `retiredReason` (auto-hidden, cache purged)
    ///   • flagged  → `needsReview` (shown 🟡, hidden from the child until resolved)
    ///   • approved → cleared (`needsReview = false`, visible)
    @MainActor
    static func reviewTiles(_ tiles: [TileModel], apiKey: String, context: ModelContext) async {
        guard !tiles.isEmpty, !apiKey.isEmpty else { return }
        let name: (TileModel) -> String = { $0.displayName.isEmpty ? $0.value : $0.displayName }
        let verdicts = await WordModerationService(apiKey: apiKey).audit(tiles.map(name))
        let cache = SentenceCacheManager(modelContext: context)
        for tile in tiles {
            switch verdicts[name(tile)] {
            case .blocked(let reason):
                tile.retire(reason: reason)
                _ = cache.invalidate(containingTileKey: tile.key)
            case .flagged:
                tile.flagForReview()
            default:
                tile.approveReview()
            }
        }
        try? context.save()
    }

    /// Parse the `results` array (aligned with input order) into word → [flagged
    /// category names]. `nonisolated static` + pure so it's unit-testable.
    nonisolated static func parseFlags(data: Data, words: [String]) -> [String: [String]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [:] }
        var out: [String: [String]] = [:]
        for (i, res) in results.enumerated() where i < words.count {
            guard (res["flagged"] as? Bool) == true,
                  let categories = res["categories"] as? [String: Any] else { continue }
            let flagged = categories.compactMap { key, value in
                (value as? Bool) == true ? key : nil
            }
            if !flagged.isEmpty { out[words[i]] = flagged }
        }
        return out
    }
}
