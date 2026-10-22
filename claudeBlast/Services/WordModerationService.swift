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
    /// **A tier that should have run did not.** Not a judgement about the word —
    /// a statement that no judgement was reached.
    ///
    /// Distinct from `.allowed` because the two were indistinguishable, and the
    /// consequence was silent: an exhausted key made tier 3 throw, `try?`
    /// swallowed it, every word kept tier 1's `.allowed` default, and the
    /// Add-Tiles path then stamped it **approved** — recording "checked and
    /// fine" for a word nothing had checked. Under a spend-capped key that is
    /// not an edge case; running out of credit is an expected state, so the
    /// primary gate being off would have been an expected state too.
    ///
    /// Treated as `flagged` by every consumer: the word is still created (a
    /// billing state must not stop a caregiver adding "grandma"), but it waits
    /// for a human instead of going straight to the child.
    case unreviewed(reason: String)

    var isBlocked: Bool { if case .blocked = self { return true }; return false }
    var isFlagged: Bool { if case .flagged = self { return true }; return false }
    var isUnreviewed: Bool { if case .unreviewed = self { return true }; return false }

    /// Whether the word must wait for a caregiver before the child sees it.
    var needsCaregiver: Bool { isFlagged || isUnreviewed }
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

        // Why a failed tier is recorded rather than shrugged off.
        //
        // Failing *open* is right — a tunnel must not stop a caregiver adding a
        // word. What was wrong was failing open *silently*: the word came out
        // `.allowed`, identical to one the rubric had cleared, and downstream
        // stamped it approved. The reason is carried so the caregiver is told
        // "we couldn't check this" rather than left to wonder.
        var unavailable: String?

        // Tier 2 — free moderations endpoint (hard policy).
        //
        // Free at OpenAI's price list, which is not the same as reachable: a
        // project spend limit gates the project, not the line item.
        do {
            let flags = try await moderationFlags(for: pending)
            for (word, categories) in flags where !categories.isEmpty {
                result[word] = .blocked(reason: "policy: \(categories.sorted().joined(separator: ", "))")
            }
        } catch {
            unavailable = Self.unavailableReason(error)
        }

        let stillAllowed = pending.filter { result[$0] == .allowed }

        // Tier 3 — age-appropriateness rubric (the real gate).
        //
        // Billed `gpt-4o-mini`, so this is the tier an exhausted key loses — and
        // it is the only tier that catches weapons, drugs, alcohol, gambling and
        // adult themes. Tier 2 does not flag a lone "gun"; tier 1 cannot
        // enumerate them. Losing this quietly is the whole problem.
        if !stillAllowed.isEmpty {
            do {
                let ratings = try await appropriatenessRatings(for: stillAllowed)
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
            } catch {
                unavailable = Self.unavailableReason(error)
            }
        }

        if let unavailable {
            result = Self.downgradingUnchecked(result, among: pending, reason: unavailable)
        }
        return result
    }

    /// Turn "nothing objected" into "nothing checked" for the words a failed
    /// tier never reached a verdict on.
    ///
    /// Only words still sitting on tier 1's `.allowed` default are downgraded. A
    /// word tier 2 blocked, or tier 3 rated before the other tier failed, has a
    /// real verdict and keeps it — a partial outage must not discard the
    /// judgements that did land.
    ///
    /// `static` and pure so the rule is testable without a network. The tiers
    /// themselves are not injectable, so this is the part that can be pinned.
    static func downgradingUnchecked(_ verdicts: [String: WordVerdict],
                                     among words: [String],
                                     reason: String) -> [String: WordVerdict] {
        var out = verdicts
        for word in words where out[word] == .allowed {
            out[word] = .unreviewed(reason: reason)
        }
        return out
    }

    /// Caregiver-facing reason a tier could not run.
    ///
    /// `static` and pure so it is testable without a network — see the note in
    /// CLAUDE.md about tests that reach into private paths and silently pass.
    static func unavailableReason(_ error: Error) -> String {
        switch OpenAIFailure.classify(error) {
        case .exhausted:
            return "the key is out of credit"
        case .rejected:
            return "the key was refused"
        case .capability:
            return "this key cannot use the review model"
        case .requestRefused:
            return "the review service refused the request"
        case .transient:
            return "the review service could not be reached"
        }
    }

    // MARK: - Tier 3: age-appropriateness rubric (gpt-4o-mini)

    enum Rating: String { case appropriate, questionable, inappropriate }

    private func appropriatenessRatings(for words: [String]) async throws -> [String: Rating] {
        let content = try await chat(body: Self.rubricRequestBody(words: words))
        return Self.parseRatings(content, words: words)
    }

    /// The exact chat-completions body the rubric sends. Pure, so the prompt
    /// fixtures (`PromptFixtureTests`) can pin it without a network call.
    nonisolated static func rubricRequestBody(words: [String]) -> [String: Any] {
        ChatRequest.body(model: ModelID.wordAudit,
                         messages: [["role": "system", "content": PromptTemplate.raw("moderation_rubric_system")],
                                    ["role": "user", "content": words.joined(separator: ", ")]],
                         temperature: 0)
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

    private func chat(body: [String: Any]) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Tier 3 — the age-appropriateness rubric. The only billable part of a
        // word audit; tier 1 is offline and tier 2 (below) is free.
        let (data, response) = try await OpenAIClient.send(
            request, cause: .wordAuditRubric, endpoint: OpenAIEndpoint.chatCompletions)
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
        // Tier 2 — free policy screen. Recorded so the call volume behind an
        // add-word is visible even though it costs nothing.
        let (data, response) = try await OpenAIClient.send(
            request, cause: .wordAuditScreen, endpoint: OpenAIEndpoint.moderations)
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
            case .unreviewed:
                // The word is created, but it is not stamped approved — nothing
                // approved it. It waits for a caregiver, which is what
                // `needsReview` already means and what `isHiddenFromChild`
                // already honours.
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
