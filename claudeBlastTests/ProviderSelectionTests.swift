// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProviderSelectionTests.swift
//  claudeBlastTests
//
//  The launch path our own devices never take.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct ProviderSelectionTests {

    private func isolatedDefaults(_ line: Int = #line) -> UserDefaults {
        let suite = "ProviderSelectionTests.\(line).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - Keyless

    /// The configuration a reviewer and most child devices launch in, and the
    /// one no development machine ever reproduces — every one of ours has a key.
    @Test("With no key anywhere, the launch is keyless — not silently mocked")
    func noKeyAnywhereIsKeyless() {
        let choice = ProviderSelection.choose(environment: [:],
                                              defaults: isolatedDefaults(),
                                              store: InMemorySecretStore())
        #expect(choice == .noKey)
    }

    /// The provider is still the mock — something has to stand in — but the
    /// *choice* records that this is a keyless device, and the engine reads that
    /// to stay in single-word mode rather than speaking invented sentences.
    @Test("A keyless device still gets a provider object")
    func noKeyBuildsMockProvider() {
        let provider = ProviderSelection.makeProvider(environment: [:],
                                                      defaults: isolatedDefaults(),
                                                      store: InMemorySecretStore())
        #expect(provider is MockSentenceProvider)
    }

    /// An empty string is not a key. It is what a cleared field leaves behind,
    /// and treating it as one would build a live provider that fails on the
    /// child's first tap rather than falling back cleanly.
    @Test("A blank stored key is not a key")
    func blankStoredKeyIsNotAKey() {
        let store = InMemorySecretStore(initial: "   ")
        let choice = ProviderSelection.choose(environment: [:],
                                              defaults: isolatedDefaults(),
                                              store: store)
        #expect(choice == .noKey)
    }

    @Test("A blank environment variable is not a key")
    func blankEnvironmentKeyIsNotAKey() {
        let choice = ProviderSelection.choose(environment: ["OPENAI_API_KEY": "  "],
                                              defaults: isolatedDefaults(),
                                              store: InMemorySecretStore())
        #expect(choice == .noKey)
    }

    // MARK: - Precedence

    @Test("A stored key is used when there is one")
    func storedKeyIsUsed() {
        let choice = ProviderSelection.choose(environment: [:],
                                              defaults: isolatedDefaults(),
                                              store: InMemorySecretStore(initial: "sk-stored"))
        #expect(choice == .storedKey("sk-stored"))
    }

    /// The env var has to beat the Keychain or a developer cannot override a
    /// stored key without deleting it first.
    @Test("The environment beats the Keychain")
    func environmentBeatsKeychain() {
        let choice = ProviderSelection.choose(environment: ["OPENAI_API_KEY": "sk-env"],
                                              defaults: isolatedDefaults(),
                                              store: InMemorySecretStore(initial: "sk-stored"))
        #expect(choice == .environmentKey("sk-env"))
    }

    /// So a launch under the scheme does not have to be repeated to keep working
    /// from the Home screen afterwards.
    @Test("An environment key is persisted for later launches")
    func environmentKeyIsPersisted() {
        let store = InMemorySecretStore()
        _ = ProviderSelection.makeProvider(environment: ["OPENAI_API_KEY": "sk-env"],
                                           defaults: isolatedDefaults(),
                                           store: store)
        // `store.read()` rather than `OpenAIKeyVault.currentKey`, which would
        // consult the real process environment and pass whether or not anything
        // was written.
        #expect(store.read() == "sk-env")
    }

    /// Someone who picked Mock while holding a key means it — usually to stop
    /// spending money — so the choice wins over the key being present.
    @Test("Choosing Mock is honoured even with a key stored")
    func explicitMockWinsOverStoredKey() {
        let defaults = isolatedDefaults()
        defaults.set("mock", forKey: AppSettingsKey.providerChoice)
        let choice = ProviderSelection.choose(environment: [:],
                                              defaults: defaults,
                                              store: InMemorySecretStore(initial: "sk-stored"))
        #expect(choice == .mockByChoice)
    }

    /// …but not over an explicit environment variable, which is the more
    /// deliberate of the two signals: it had to be typed into a scheme.
    @Test("The environment still wins over a Mock preference")
    func environmentWinsOverMockPreference() {
        let defaults = isolatedDefaults()
        defaults.set("mock", forKey: AppSettingsKey.providerChoice)
        let choice = ProviderSelection.choose(environment: ["OPENAI_API_KEY": "sk-env"],
                                              defaults: defaults,
                                              store: InMemorySecretStore())
        #expect(choice == .environmentKey("sk-env"))
    }

    /// An unset preference must behave as "openai", not as "mock" — the default
    /// on a fresh install where the caregiver has just entered a key.
    @Test("An unset provider preference uses a stored key")
    func unsetPreferenceUsesStoredKey() {
        let choice = ProviderSelection.choose(environment: [:],
                                              defaults: isolatedDefaults(),
                                              store: InMemorySecretStore(initial: "sk-stored"))
        #expect(choice == .storedKey("sk-stored"))
    }
}
}

extension SerialTests {
@Suite(.serialized)
struct KeylessModeTests {

    /// The distinction that matters at the child's end: choosing Mock is a
    /// request for fake sentences; having no key is not.
    @Test("Choosing Mock and having no key are different states")
    func mockByChoiceIsNotNoKey() {
        #expect(ProviderSelection.Choice.mockByChoice != ProviderSelection.Choice.noKey)
    }
}
}
