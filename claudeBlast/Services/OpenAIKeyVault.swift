// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeyVault.swift
//  claudeBlast
//

import Foundation

/// Typed accessor for the OpenAI API key.
///
/// Resolution order at read time:
/// 1. `OPENAI_API_KEY` environment variable — a developer override that exists
///    only in DEBUG builds. See `environmentOverride`.
/// 2. Keychain entry under `service = com.lucovsky.claudeBlast.api`,
///    `account = openai`.
///
/// Key writes go to the Keychain only — never UserDefaults. On first run
/// after upgrading, `migrateFromUserDefaultsIfNeeded` copies any prior
/// `AppSettingsKey.openaiApiKey` UserDefaults value across once and clears
/// the UserDefaults entry, so the key stops sitting in plist-readable
/// storage even if the user never opens Admin again.
enum OpenAIKeyVault {
    static let service = "com.lucovsky.claudeBlast.api"
    static let account = "openai"

    static func defaultStore() -> SecretStore {
        KeychainSecretStore(service: service, account: account)
    }

    /// The developer key override, and the only place the app reads it.
    ///
    /// **DEBUG only.** A shipping build has no override and no copy that
    /// mentions one: the variable name is compiled out, so a Release binary does
    /// not contain it at all, and `preflight_release.py` checks exactly that.
    /// Nothing a family can do sets a scheme environment variable, so in Release
    /// the path could only ever be dead code — and dead code that describes a
    /// way to inject a key is not something to ship to App Review.
    ///
    /// Blank and whitespace-only values count as absent, so an exported but
    /// empty `OPENAI_API_KEY` cannot swallow a real stored key.
    static func environmentOverride(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        #if DEBUG
        guard let key = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty else { return nil }
        return key
        #else
        return nil
        #endif
    }

    /// The effective key right now. Returns `nil` (not an empty string) when
    /// no key is available, so callers can branch on `if let`.
    static func currentKey(
        env: ProcessInfo = .processInfo,
        store: SecretStore = defaultStore()
    ) -> String? {
        if let envKey = environmentOverride(env.environment) {
            return envKey
        }
        guard let stored = store.read(), !stored.isEmpty else { return nil }
        return stored
    }

    /// Persist a new key. Empty/whitespace-only input deletes the entry —
    /// matches the "clear it from Admin" affordance.
    ///
    /// **A key is only installed with permission** (`AIConsent`). Every screen
    /// that takes a key shows the disclosure first, so a refusal here means a
    /// path forgot to — and returns false rather than storing a key the
    /// caregiver never agreed to use. Deleting is always allowed.
    @discardableResult
    static func setKey(_ key: String,
                       store: SecretStore = defaultStore(),
                       consentGranted: Bool = AIConsent.isGranted()) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.delete()
        }
        guard consentGranted else { return false }
        return store.write(trimmed)
    }

    /// Drop the persisted key. Env var still wins at the next read.
    @discardableResult
    static func clearKey(store: SecretStore = defaultStore()) -> Bool {
        store.delete()
    }

    /// Drop a key the previous install left behind.
    ///
    /// iOS deletes an app's container and its UserDefaults on removal, but
    /// **not its Keychain items** — so a reinstall comes up already holding the
    /// last install's key, with nothing on screen to say so. Onboarding's key
    /// field starts empty, so a caregiver is looking at a blank field while the
    /// vault is full.
    ///
    /// The visible symptom was small: "Someone sent me a key file" answering
    /// "this device already has a key" on a fresh install. The real cost is that
    /// an iPad passed to another child, or handed back by the therapist who lent
    /// it, keeps billing the previous family's OpenAI account — invisibly,
    /// because nothing in a fresh setup ever mentions a key that is already
    /// there.
    ///
    /// `hasRunBefore` must be read **before bootstrap**, which sets the flag it
    /// comes from. An upgrade keeps its UserDefaults, so it reports `true` and
    /// the caregiver's own key is untouched.
    ///
    /// Returns whether anything was cleared.
    @discardableResult
    static func clearIfInherited(hasRunBefore: Bool,
                                 store: SecretStore = defaultStore()) -> Bool {
        guard !hasRunBefore else { return false }
        // `store.read()`, not `currentKey`: an env var is supplied by whoever is
        // launching the app right now and is not an inheritance.
        guard let existing = store.read(),
              !existing.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return store.delete()
    }

    /// One-shot migration. Idempotent.
    ///
    /// Behavior:
    /// - If Keychain already has a non-empty value, ensure the legacy
    ///   UserDefaults entry is cleared and return `false`.
    /// - If Keychain is empty and UserDefaults has a non-empty value, copy
    ///   it to Keychain, clear UserDefaults, and return `true`.
    /// - Otherwise return `false`.
    @discardableResult
    static func migrateFromUserDefaultsIfNeeded(
        store: SecretStore = defaultStore(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let existing = store.read(), !existing.isEmpty {
            if defaults.string(forKey: AppSettingsKey.openaiApiKey) != nil {
                defaults.removeObject(forKey: AppSettingsKey.openaiApiKey)
            }
            return false
        }
        guard let legacy = defaults.string(forKey: AppSettingsKey.openaiApiKey),
              !legacy.isEmpty else {
            return false
        }
        let ok = store.write(legacy)
        if ok {
            defaults.removeObject(forKey: AppSettingsKey.openaiApiKey)
        }
        return ok
    }
}
