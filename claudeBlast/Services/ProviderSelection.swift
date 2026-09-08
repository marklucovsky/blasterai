// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProviderSelection.swift
//  claudeBlast
//
//  Which sentence provider a launch gets, and why.
//

import Foundation

/// Decides between the live provider and the mock at launch.
///
/// Lifted out of `claudeBlastApp.init` because nothing there can be tested, and
/// **this is the one path our own devices can never exercise.** Every machine we
/// develop on has a key, so the keyless branch is invisible to us by
/// construction: a change that assumes a live provider keeps working for
/// everyone here, and the first person to find out otherwise is a reviewer on a
/// fresh install — the one launch that must not go wrong.
///
/// Keyless is not a degraded mode. It is the expected configuration on a child's
/// device, where speech, boards, packs, the editor, print, export, coverage and
/// the activity log all work with no key at all. A key buys sentence generation,
/// scene and page generation, moderation, and art for new words — nothing else.
enum ProviderSelection {

    /// The decision, separated from acting on it.
    ///
    /// Pure: takes the environment, the defaults and the vault, and returns what
    /// should happen. The side effects — persisting an env key, constructing a
    /// provider — live in `makeProvider`, so the *rule* can be tested without a
    /// Keychain, a network stack or an app.
    enum Choice: Equatable {
        /// `OPENAI_API_KEY` was set. Wins outright, and the key is persisted so a
        /// later launch outside the scheme keeps working.
        case environmentKey(String)
        /// A key the caregiver entered, from the Keychain.
        case storedKey(String)
        /// Mock, because somebody asked for it — the provider picker is set to
        /// Mock, or a load script is running. Sentence mode still applies: fake
        /// sentences are the point.
        case mockByChoice
        /// No usable key at all.
        ///
        /// **Not the same as `mockByChoice`, and the difference is the whole
        /// point of splitting them.** A device with no key is a plain AAC
        /// device: it speaks each word as it is tapped. Quietly handing it the
        /// mock instead would leave a child hearing invented sentences that no
        /// model produced and nobody asked for.
        case noKey
    }

    static func choose(environment: [String: String] = ProcessInfo.processInfo.environment,
                       defaults: UserDefaults = .standard,
                       store: SecretStore = OpenAIKeyVault.defaultStore()) -> Choice {
        // Env var first. It is how the eval harness and a developer scheme
        // supply a key, and it has to beat whatever is in the Keychain or you
        // cannot override a stored key without deleting it.
        if let envKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespaces),
           !envKey.isEmpty {
            return .environmentKey(envKey)
        }
        // An explicit choice of Mock is honoured even when a key exists. Someone
        // testing without spending money means it.
        let choice = defaults.string(forKey: AppSettingsKey.providerChoice) ?? "openai"
        // `store.read()`, deliberately, not `OpenAIKeyVault.currentKey`.
        //
        // That helper consults `ProcessInfo.environment` itself before falling
        // through to the store, so calling it here would make **two** layers
        // decide env-versus-stored precedence. The redundancy was invisible
        // until these tests ran on a machine with `OPENAI_API_KEY` exported, and
        // then the real key walked straight past an injected in-memory store.
        // One place owns that rule, and it is the block above.
        guard choice == "openai" else { return .mockByChoice }
        guard let stored = store.read(),
              !stored.trimmingCharacters(in: .whitespaces).isEmpty
        else { return .noKey }
        return .storedKey(stored)
    }

    /// Apply the decision. The only side effect is persisting an env key, which
    /// is deliberate: a developer who ran once with the variable set should not
    /// lose the key by launching from the Home screen afterwards.
    static func makeProvider(environment: [String: String] = ProcessInfo.processInfo.environment,
                             defaults: UserDefaults = .standard,
                             store: SecretStore = OpenAIKeyVault.defaultStore())
        -> any SentenceProvider {
        switch choose(environment: environment, defaults: defaults, store: store) {
        case .environmentKey(let key):
            _ = OpenAIKeyVault.setKey(key, store: store)
            return OpenAISentenceProvider(apiKey: key)
        case .storedKey(let key):
            return OpenAISentenceProvider(apiKey: key)
        case .mockByChoice, .noKey:
            // Both build the mock — it is the only thing that can stand in for a
            // provider — but the *engine* is told which, and a `.noKey` device
            // never asks it for a sentence.
            return MockSentenceProvider()
        }
    }
}
