// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChatRequestTests.swift
//  claudeBlastTests
//
//  A chat body fits the model it names, every job's model is known and priced,
//  and GPT-6's cache writes are priced.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ChatRequestTests {

    /// Every chat job in `ModelID` — add a new one here when it is added there.
    static let chatJobs = [ModelID.sentence, ModelID.sceneAuthoring, ModelID.tileSuggest,
                           ModelID.wordAudit, ModelID.skinCheck]

    /// A job may only name a model the app knows how to call and to price.
    /// Without a capabilities entry the body falls back to gpt-4o-mini's shape —
    /// a 400 on GPT-6; without a price, every call records as unpriced.
    @Test func everyChatJobNamesAKnownPricedModel() {
        for model in Self.chatJobs {
            #expect(ModelCapabilities.table[model] != nil, "\(model) has no capabilities entry")
            #expect(ModelPricing.isPriced(model), "\(model) has no price")
        }
    }

    /// gpt-4o-mini gets exactly what the services used to build by hand.
    @Test func gpt4oMiniBodyIsUnchanged() {
        let body = ChatRequest.body(model: "gpt-4o-mini", messages: [["role": "user", "content": "hi"]],
                                    temperature: 0.3, maxTokens: 500)
        #expect(Set(body.keys) == ["model", "messages", "temperature", "max_tokens"])
        #expect(body["temperature"] as? Double == 0.3)
        #expect(body["max_tokens"] as? Int == 500)
    }

    /// GPT-6 rejects any temperature but the default (a 400), takes a reasoning
    /// effort, and counts reasoning against `max_completion_tokens`.
    @Test func lunaBodyDropsTemperatureAndAddsEffortNone() {
        let body = ChatRequest.body(model: "gpt-6-luna", messages: [["role": "user", "content": "hi"]],
                                    temperature: 0.3, maxTokens: 500)
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] == nil)
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(body["max_completion_tokens"] as? Int == 500)   // no reasoning at none
    }

    @Test func solBodyUsesLowEffortAndALargerBudget() {
        let body = ChatRequest.body(model: "gpt-6.1-sol", messages: [["role": "user", "content": "hi"]],
                                    temperature: 0.5, maxTokens: 3000)
        #expect(body["temperature"] == nil)
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["max_completion_tokens"] as? Int == 12000)
    }

    /// The word audit sends no token limit; none may appear for any model.
    @Test func noLimitStaysNoLimit() {
        for model in ["gpt-4o-mini", "gpt-6-luna"] {
            let body = ChatRequest.body(model: model, messages: [], temperature: 0)
            #expect(body["max_tokens"] == nil && body["max_completion_tokens"] == nil)
        }
    }

    @Test func datedSnapshotResolvesToItsModelsCapabilities() {
        #expect(ModelCapabilities.of("gpt-6-luna-2027-01-01").reasoningEffort == "none")
        #expect(ModelCapabilities.of("gpt-4o-mini-2024-07-18") == .classic)
    }

    // MARK: - Pricing

    /// GPT-6 bills a first-seen prompt as a cache write (1.25× input), and the
    /// cache-write portion must not ALSO be charged as plain input. Rates from
    /// the 2026-10-21 bill: Luna $0.10 input, $0.01 cached, $0.125 cache write,
    /// $0.50 output per 1M.
    @Test func gpt6CacheWritesArePricedOnce() {
        let cost = ModelPricing.costMicros(model: "gpt-6-luna", promptTokens: 2000,
                                           cachedPromptTokens: 1000, cacheWriteTokens: 800,
                                           completionTokens: 100)
        // 200 × 0.10 + 1000 × 0.01 + 800 × 0.125 + 100 × 0.50 = 20 + 10 + 100 + 50
        #expect(cost == 180)
    }

    /// The table is keyed by model name, so gpt-4o-mini stays priced whatever a
    /// job points at.
    @Test func ratesAreKeyedByModelNotJob() {
        #expect(ModelPricing.rates["gpt-4o-mini"] != nil)
        #expect(ModelPricing.rates["gpt-6-luna"]?.cacheWritePerM == 0.125)
        #expect(ModelPricing.rates["gpt-6.1-sol"]?.cacheWritePerM == 2.50)
    }
}
}
