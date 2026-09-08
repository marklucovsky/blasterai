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

    // MARK: - Terminal vs transient

    /// The distinction the whole fix rests on. Before it, every failure looked
    /// alike and a revoked key produced silence on every tap, forever, with
    /// nothing anywhere to explain it.
    @Test("Rejection is 401 and 403, and nothing else", arguments: [401, 403])
    func authFailuresAreTerminal(_ status: Int) {
        #expect(SentenceEngine.isKeyRejection(http(status)))
    }

    /// A server having a bad day is not a credential problem.
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
    @Test("With a key, Stage IV+ generates sentences")
    func stageFourPlusWithKeyGeneratesSentences() {
        let e = engine()
        e.isMissingKey = false
        #expect(e.interactionMode == .sentence)
    }


}
}
