// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  KeyRejectionTests.swift
//  claudeBlastTests
//
//  A dead key must not mean a silent device.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct KeyRejectionTests {

    /// Stage IV+, deliberately.
    ///
    /// The seeded caregiver profile is Stage I, which already resolves to
    /// `.singleWord` — so an engine built on it would "pass" the fallback test
    /// without the fallback existing. The child has to be in sentence mode for
    /// the drop out of it to mean anything.
    private func engine() -> SentenceEngine {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        ProfileMigration.ensureProfilesAfterBootstrap(context: context)
        let child = ChildProfile(displayName: "Aubrey",
                                 brownsStage: .fourPlus,
                                 isActive: true)
        // A profile with AI sentences on: what these tests take away is the
        // device's ability to make them, not the profile's wish for them.
        child.aiMode = .sentences
        context.insert(child)
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: context)
        resolver.setActive(id: child.id)
        let engine = SentenceEngine(provider: MockSentenceProvider())
        engine.configure(modelContext: context, profileResolver: resolver)
        return engine
    }

    private func http(_ status: Int) -> Error {
        OpenAIError.httpError(statusCode: status,
                              body: "{\"error\":{\"code\":\"invalid_api_key\"}}")
    }

    /// A 429 carrying the body OpenAI actually sends when the money runs out.
    /// See `OpenAIFailureTests` for the verbatim capture and the four-way table.
    private func outOfCredit() -> Error {
        OpenAIError.httpError(
            statusCode: 429,
            body: #"{"error":{"type":"insufficient_quota","code":"project_spend_limit_exceeded"}}"#)
    }

    // MARK: - Terminal vs transient

    /// The distinction the whole fix rests on. Before it, every failure looked
    /// alike and a revoked key produced silence on every tap, forever, with
    /// nothing anywhere to explain it.
    @Test("Rejection is 401 and 403, and nothing else", arguments: [401, 403])
    func authFailuresAreTerminal(_ status: Int) {
        #expect(SentenceEngine.isKeyRejection(http(status)))
    }

    /// A server having a bad day is not a credential problem.
    ///
    /// 429 stays in this list, but for a narrower reason than it once had: an
    /// ordinary rate limit is transient, while a 429 whose body says
    /// `insufficient_quota` is not — it stops the device, just under a different
    /// name than rejection. See `quotaExhaustionIsNotRejection` below.
    @Test("Other HTTP failures are not rejections", arguments: [429, 500, 503])
    func otherStatusesAreTransient(_ status: Int) {
        #expect(!SentenceEngine.isKeyRejection(http(status)))
    }

    /// The train went into a tunnel. Condemning the key here would drop a
    /// perfectly good device into fallback until it was relaunched.
    @Test("A network failure is not a rejection")
    func networkFailureIsTransient() {
        #expect(!SentenceEngine.isKeyRejection(URLError(.timedOut)))
        #expect(!SentenceEngine.isKeyRejection(URLError(.notConnectedToInternet)))
    }

    @Test("A decoding failure is not a rejection")
    func decodingFailureIsTransient() {
        #expect(!SentenceEngine.isKeyRejection(OpenAIError.decodingError("nonsense")))
    }

    // MARK: - What it does to the device

    @Test("A fresh engine has not written off its key")
    func startsTrusting() {
        let e = engine()
        #expect(!e.isKeyRejected)
        #expect(e.interactionMode == .sentence)
    }

    /// The property that matters for the child. Sentence mode with a dead key is
    /// silence on every tap — strictly worse than having no key at all, which at
    /// least speaks each word as it is pressed.
    @Test("A rejected key drops the device into single-word mode")
    func rejectionForcesSingleWord() {
        let e = engine()
        e.noteGenerationFailure(http(401))
        #expect(e.isKeyRejected)
        #expect(e.interactionMode == .singleWord)
    }

    @Test("A transient failure leaves the mode alone")
    func transientFailureLeavesModeAlone() {
        let e = engine()
        e.noteGenerationFailure(URLError(.timedOut))
        #expect(!e.isKeyRejected)
        #expect(e.interactionMode == .sentence)
    }

    // MARK: - Out of credit

    /// The failure this whole change exists to fix.
    ///
    /// Before it, a 429 was transient: the device did not fall back, so every
    /// tap reached for a model that would refuse again and the child got silence
    /// with nothing anywhere to explain it. Exactly the condition the original
    /// 401 work removed, arriving through a different door.
    @Test("An exhausted key drops the device into single-word mode")
    func exhaustionForcesSingleWord() {
        let e = engine()
        e.noteGenerationFailure(outOfCredit())
        #expect(e.isQuotaExhausted)
        #expect(e.isKeyUnusable)
        #expect(e.interactionMode == .singleWord)
    }

    /// Exhaustion and rejection stop the device the same way and are told apart
    /// only in what the caregiver is shown. Collapsing them would put "paste a
    /// new key" in front of someone whose key is perfectly good.
    @Test("An exhausted key is not a rejected one")
    func quotaExhaustionIsNotRejection() {
        let e = engine()
        e.noteGenerationFailure(outOfCredit())
        #expect(!e.isKeyRejected)
        #expect(!SentenceEngine.isKeyRejection(outOfCredit()))
    }

    /// Adding credit or raising the limit is the fix, and it arrives as a new
    /// key or a relaunch. Either way the device must come back.
    @Test("Clearing restores sentences after exhaustion")
    func clearingRestoresAfterExhaustion() {
        let e = engine()
        e.noteGenerationFailure(outOfCredit())
        #expect(e.interactionMode == .singleWord)

        e.clearKeyRejection()
        #expect(!e.isQuotaExhausted)
        #expect(e.interactionMode == .sentence)
    }

    /// A rate limit is a burst, not a bill. Condemning the key here is the
    /// failure the original doc comment warned about, and the reason exhaustion
    /// is matched on the body rather than on the status code.
    @Test("An ordinary rate limit changes nothing")
    func rateLimitChangesNothing() {
        let e = engine()
        e.noteGenerationFailure(OpenAIError.httpError(
            statusCode: 429,
            body: #"{"error":{"type":"requests","code":"rate_limit_exceeded"}}"#))
        #expect(!e.isKeyUnusable)
        #expect(e.interactionMode == .sentence)
    }

    // MARK: - The one predicate behind the rule
    //
    // `canGenerateSentences` gates two things that must agree: what
    // `interactionMode` returns, and whether the caregiver menu offers the
    // switch into sentences. They used to be decided separately, which is how
    // "Switch to AI Sentences" became a button that set the override and then
    // watched `interactionMode` override it straight back — no change, no
    // explanation.

    @Test("A device with a working key can generate")
    func canGenerateWithAKey() {
        let e = engine()
        e.isMissingKey = false
        #expect(e.canGenerateSentences)
    }

    @Test("Every reason the key is unusable stops generation")
    func cannotGenerateWhenKeyIsUnusable() {
        let noKey = engine()
        noKey.isMissingKey = true
        #expect(!noKey.canGenerateSentences)

        let rejected = engine()
        rejected.isMissingKey = false
        rejected.noteGenerationFailure(http(401))
        #expect(!rejected.canGenerateSentences)

        let dry = engine()
        dry.isMissingKey = false
        dry.noteGenerationFailure(outOfCredit())
        #expect(!dry.canGenerateSentences)
    }

    /// The property that makes it safe for the menu to read: whenever the device
    /// cannot generate, the mode it reports is already single-word. A menu row
    /// gated on this can never offer something the engine will refuse.
    @Test("Unable to generate always means single-word")
    func inabilityImpliesSingleWord() {
        for e in [engine(), engine(), engine()] where !e.canGenerateSentences {
            #expect(e.interactionMode == .singleWord)
        }

        let dry = engine()
        dry.isMissingKey = false
        dry.noteGenerationFailure(outOfCredit())
        #expect(!dry.canGenerateSentences)
        #expect(dry.interactionMode == .singleWord)
    }

    /// Capability is not a stage. A Stage I child on a device with a perfect key
    /// still speaks single words, and that must not read as "this device cannot
    /// do sentences" — it would disable a menu row for the wrong reason.
    @Test("A Stage I child does not make the device incapable")
    func stageIsNotCapability() {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        ProfileMigration.ensureProfilesAfterBootstrap(context: context)
        let child = ChildProfile(displayName: "Stage One", brownsStage: .one, isActive: true)
        context.insert(child)
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: context)
        resolver.setActive(id: child.id)

        let e = SentenceEngine(provider: MockSentenceProvider())
        e.configure(modelContext: context, profileResolver: resolver)
        e.isMissingKey = false

        #expect(e.canGenerateSentences)          // the machinery works
        #expect(e.interactionMode == .singleWord) // the child is Stage I
    }

    /// A model this key may not call says nothing about the key. Allowlist
    /// changes propagate with a lag, so latching here would keep a
    /// newly-granted key broken until the app was relaunched.
    @Test("A withheld model never condemns the key")
    func capabilityFailureNeverLatches() {
        let e = engine()
        e.noteGenerationFailure(OpenAIError.httpError(
            statusCode: 403,
            body: #"{"error":{"type":"invalid_request_error","code":"model_not_found","message":"does not have access to model `gpt-image-1`"}}"#))
        #expect(!e.isKeyRejected)
        #expect(!e.isQuotaExhausted)
        #expect(e.interactionMode == .sentence)
    }

    // MARK: - Recovery

    /// The flag belongs to one credential. A caregiver who pastes a working key
    /// must not be left in the fallback with nothing to tell them why.
    @Test("Entering a new key clears the rejection and restores sentences")
    func newKeyClearsRejection() {
        let e = engine()
        e.noteGenerationFailure(http(401))
        #expect(e.interactionMode == .singleWord)

        e.clearKeyRejection()
        #expect(!e.isKeyRejected)
        #expect(e.interactionMode == .sentence)
    }

    /// Latching matters: one refusal is enough, and the state must not be
    /// undone by the next unrelated hiccup.
    @Test("A later transient failure does not clear a rejection")
    func transientFailureDoesNotUndoRejection() {
        let e = engine()
        e.noteGenerationFailure(http(401))
        e.noteGenerationFailure(URLError(.timedOut))
        #expect(e.isKeyRejected)
    }

    // MARK: - Having a key does not promote the child

    /// The rule, stated whole: no key ⇒ single-word; with a key, the stage
    /// decides, and Stage I is still single-word.
    ///
    /// A key arriving used to flip a Stage I child into sentence mode, because
    /// the fallback for "no resolver yet" was `.sentence` and only the keyless
    /// short-circuit was hiding it. A key is permission to generate, not a
    /// judgement about how a child communicates.
    @Test("A key does not move a Stage I child into sentence mode")
    func keyDoesNotOverrideStageOne() {
        let container = TestStore.freshContainer()
        let context = container.mainContext
        ProfileMigration.ensureProfilesAfterBootstrap(context: context)
        let child = ChildProfile(displayName: "Stage One", brownsStage: .one, isActive: true)
        context.insert(child)
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: context)
        resolver.setActive(id: child.id)

        let e = SentenceEngine(provider: MockSentenceProvider())
        e.configure(modelContext: context, profileResolver: resolver)
        e.isMissingKey = false   // a key is present

        #expect(e.interactionMode == .singleWord)
    }

    /// The other half, so the fix cannot be "always single-word".
    @Test("With a key, a sentences profile generates sentences")
    func stageFourPlusWithKeyGeneratesSentences() {
        let e = engine()
        e.isMissingKey = false
        #expect(e.interactionMode == .sentence)
    }


}
}
