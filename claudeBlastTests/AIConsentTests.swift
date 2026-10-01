// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AIConsentTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

/// Permission to send anything to OpenAI. See `AIConsent`.
struct AIConsentTests {

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIConsentTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    // MARK: - The stored answer

    /// Every tester's device before this existed: nothing stored. It must read
    /// as not granted — that is the whole of the migration.
    @Test func neverAskedIsNotGranted() {
        let d = isolatedDefaults()
        #expect(AIConsent.acceptedVersion(d) == 0)
        #expect(!AIConsent.isGranted(d))
    }

    @Test func acceptingRecordsVersionAndDate() {
        let d = isolatedDefaults()
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        AIConsent.accept(d, now: when)
        #expect(AIConsent.isGranted(d))
        #expect(AIConsent.acceptedVersion(d) == AIConsent.currentVersion)
        #expect(AIConsent.acceptedAt(d) == when)
    }

    /// The reason it is a version: a new disclosure un-grants everyone who
    /// accepted the old one, with nothing else in the app involved.
    @Test func raisingTheVersionAsksAgain() {
        let d = isolatedDefaults()
        AIConsent.accept(d, version: 1)
        #expect(AIConsent.isGranted(d, current: 1))
        #expect(!AIConsent.isGranted(d, current: 2))
    }

    @Test func revokingClearsTheGrant() {
        let d = isolatedDefaults()
        AIConsent.accept(d)
        AIConsent.revoke(d)
        #expect(!AIConsent.isGranted(d))
        #expect(AIConsent.acceptedAt(d) == nil)
    }

    // MARK: - Asking once

    /// No key, nothing to switch on: the disclosure waits until one is added.
    @Test func noKeyNoPrompt() {
        #expect(!AIConsent.shouldPrompt(isolatedDefaults(), hasKey: false))
    }

    @Test func dormantKeyPromptsOncePerVersion() {
        let d = isolatedDefaults()
        #expect(AIConsent.shouldPrompt(d, hasKey: true))
        // "Not now" is an answer.
        AIConsent.markPrompted(d)
        #expect(!AIConsent.shouldPrompt(d, hasKey: true))
        // A new disclosure is a new question.
        #expect(AIConsent.shouldPrompt(d, hasKey: true, current: AIConsent.currentVersion + 1))
    }

    @Test func grantedNeverPrompts() {
        let d = isolatedDefaults()
        AIConsent.accept(d)
        #expect(!AIConsent.shouldPrompt(d, hasKey: true))
    }

    // MARK: - Enforcement

    /// The one line every OpenAI request passes through. Refused before any
    /// network is touched — the URL here would fail loudly if it were.
    @Test func sendRefusesWithoutConsent() async {
        let request = URLRequest(url: URL(string: "https://invalid.example/should-not-be-called")!)
        await #expect(throws: AIConsentError.notGranted) {
            _ = try await OpenAIClient.send(request, cause: .keyValidation,
                                            endpoint: OpenAIEndpoint.models,
                                            consentGranted: false)
        }
    }

    /// A refusal is about permission, not the key: it must not condemn a good
    /// key into the rejected state.
    @MainActor
    @Test func refusalIsNotAKeyRejection() {
        #expect(!SentenceEngine.isKeyRejection(AIConsentError.notGranted))
    }

    // MARK: - The engine

    @MainActor
    private func engineWithKey() -> SentenceEngine {
        let engine = SentenceEngine(provider: OpenAISentenceProvider(apiKey: "sk-test"))
        engine.isMissingKey = false
        return engine
    }

    /// A key on the device is not permission to use it.
    @MainActor
    @Test func keyWithoutConsentCannotGenerate() {
        let engine = engineWithKey()
        engine.loadAIConsent(defaults: isolatedDefaults())
        #expect(!engine.canGenerateSentences)
        #expect(engine.interactionMode == .singleWord)
    }

    /// Enable picks up a key the device already holds — dormant, or the DEBUG
    /// environment key — with no relaunch.
    @MainActor
    @Test func grantingAdoptsTheKeyWithoutRelaunch() {
        let d = isolatedDefaults()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.isMissingKey = true   // how a launch without consent leaves it
        engine.loadAIConsent(defaults: d)

        engine.grantAIConsent(defaults: d, key: "sk-from-env")

        #expect(AIConsent.isGranted(d))
        #expect(engine.canGenerateSentences)
        #expect(engine.provider is OpenAISentenceProvider)
    }

    /// Off is immediate, and the key is left in place so on is one tap.
    @MainActor
    @Test func revokingDropsToSingleWordAndKeepsTheProvider() {
        let d = isolatedDefaults()
        let engine = engineWithKey()
        engine.grantAIConsent(defaults: d, key: nil)
        #expect(engine.canGenerateSentences)

        engine.revokeAIConsent(defaults: d)

        #expect(!AIConsent.isGranted(d))
        #expect(!engine.canGenerateSentences)
        #expect(engine.provider is OpenAISentenceProvider)
    }

    /// Mock sends nothing anywhere, so it needs no permission — the eval harness
    /// and load scripts run on it.
    @MainActor
    @Test func mockNeedsNoConsent() {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.loadAIConsent(defaults: isolatedDefaults())
        #expect(engine.canGenerateSentences)
    }
}
