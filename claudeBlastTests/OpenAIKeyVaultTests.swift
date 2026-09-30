// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeyVaultTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

struct OpenAIKeyVaultTests {

    /// Isolated UserDefaults so writes from one test don't leak into another.
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "OpenAIKeyVaultTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    /// Build a `ProcessInfo` whose `environment` returns the given key. Note:
    /// the framework's `ProcessInfo.environment` is read-only, so we use a
    /// subclass that overrides it.
    private final class FakeProcessInfo: ProcessInfo, @unchecked Sendable {
        let env: [String: String]
        init(env: [String: String]) {
            self.env = env
            super.init()
        }
        override var environment: [String: String] { env }
    }

    // MARK: - read precedence

    @Test func envVar_winsOverKeychain() {
        let store = InMemorySecretStore(initial: "from-keychain")
        let env = FakeProcessInfo(env: ["OPENAI_API_KEY": "from-env"])
        #expect(OpenAIKeyVault.currentKey(env: env, store: store) == "from-env")
    }

    @Test func keychain_returnsWhenEnvVarUnset() {
        let store = InMemorySecretStore(initial: "sk-abc")
        let env = FakeProcessInfo(env: [:])
        #expect(OpenAIKeyVault.currentKey(env: env, store: store) == "sk-abc")
    }

    @Test func emptyKeychain_returnsNil() {
        let store = InMemorySecretStore()
        let env = FakeProcessInfo(env: [:])
        #expect(OpenAIKeyVault.currentKey(env: env, store: store) == nil)
    }

    @Test func emptyEnvVar_treatedAsUnset() {
        // Avoid the foot-gun where `OPENAI_API_KEY=""` swallows a real
        // Keychain key. Whitespace counts too.
        let store = InMemorySecretStore(initial: "sk-real")
        let env = FakeProcessInfo(env: ["OPENAI_API_KEY": "   "])
        #expect(OpenAIKeyVault.currentKey(env: env, store: store) == "sk-real")
    }

    // MARK: - the override accessor

    /// Every reader of the override — onboarding, Admin, the gift importer,
    /// provider selection — now asks this one function, so they cannot disagree.
    /// Admin used to test `!= nil`, which counted an exported-but-empty variable
    /// as an override while everything else ignored it.
    ///
    /// Tests run a DEBUG build, so this pins the development behaviour. That a
    /// shipping build has no override at all is checked on the Release binary by
    /// `tools/preflight_release.py`, which is the only place it can be seen.
    @Test func environmentOverrideTrimsAndIgnoresBlank() {
        #expect(OpenAIKeyVault.environmentOverride(["OPENAI_API_KEY": " sk-env "]) == "sk-env")
        #expect(OpenAIKeyVault.environmentOverride(["OPENAI_API_KEY": ""]) == nil)
        #expect(OpenAIKeyVault.environmentOverride(["OPENAI_API_KEY": "   "]) == nil)
        #expect(OpenAIKeyVault.environmentOverride([:]) == nil)
    }

    // MARK: - set + clear

    @Test func setKey_writesToStore() {
        let store = InMemorySecretStore()
        #expect(OpenAIKeyVault.setKey("sk-123", store: store))
        #expect(store.read() == "sk-123")
    }

    @Test func setKey_trimsWhitespace() {
        let store = InMemorySecretStore()
        OpenAIKeyVault.setKey("  sk-trimmed  ", store: store)
        #expect(store.read() == "sk-trimmed")
    }

    @Test func setKey_emptyStringDeletesEntry() {
        let store = InMemorySecretStore(initial: "sk-old")
        OpenAIKeyVault.setKey("", store: store)
        #expect(store.read() == nil)
    }

    @Test func clearKey_removesStoredValue() {
        let store = InMemorySecretStore(initial: "sk-old")
        OpenAIKeyVault.clearKey(store: store)
        #expect(store.read() == nil)
    }

    // MARK: - migration

    @Test func migration_movesUserDefaultsValueToStore() {
        let store = InMemorySecretStore()
        let defaults = isolatedDefaults()
        defaults.set("sk-legacy", forKey: AppSettingsKey.openaiApiKey)

        let migrated = OpenAIKeyVault.migrateFromUserDefaultsIfNeeded(
            store: store, defaults: defaults)

        #expect(migrated)
        #expect(store.read() == "sk-legacy")
        #expect(defaults.string(forKey: AppSettingsKey.openaiApiKey) == nil)
    }

    @Test func migration_isIdempotent() {
        let store = InMemorySecretStore()
        let defaults = isolatedDefaults()
        defaults.set("sk-legacy", forKey: AppSettingsKey.openaiApiKey)

        _ = OpenAIKeyVault.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)
        let second = OpenAIKeyVault.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        #expect(!second) // no-op on subsequent calls
        #expect(store.read() == "sk-legacy")
    }

    @Test func migration_skipsWhenKeychainAlreadyPopulated() {
        // Keychain already has a value (e.g., set by env-var persist path).
        // UserDefaults also has a stale value. Migration should NOT clobber
        // the Keychain, but SHOULD clear the stale UserDefaults entry to
        // stop leaking the key through plist-readable storage.
        let store = InMemorySecretStore(initial: "sk-from-env")
        let defaults = isolatedDefaults()
        defaults.set("sk-stale-userdefaults", forKey: AppSettingsKey.openaiApiKey)

        let migrated = OpenAIKeyVault.migrateFromUserDefaultsIfNeeded(
            store: store, defaults: defaults)

        #expect(!migrated)
        #expect(store.read() == "sk-from-env")
        #expect(defaults.string(forKey: AppSettingsKey.openaiApiKey) == nil)
    }

    @Test func migration_skipsWhenUserDefaultsEmpty() {
        let store = InMemorySecretStore()
        let defaults = isolatedDefaults()
        // No legacy value.

        let migrated = OpenAIKeyVault.migrateFromUserDefaultsIfNeeded(
            store: store, defaults: defaults)

        #expect(!migrated)
        #expect(store.read() == nil)
    }

    // MARK: - A fresh install must not inherit the last install's key
    //
    // iOS deletes the app container and UserDefaults on removal but keeps
    // Keychain items, so a reinstall comes up already holding a key with nothing
    // on screen to say so — onboarding's field starts empty while the vault is
    // full. Found 2026-09-17 when "Someone sent me a key file" answered "this
    // device already has a key" on a genuinely fresh install.
    //
    // The dialog was the small half. An iPad passed to another child, or handed
    // back by the therapist who lent it, otherwise keeps billing the previous
    // family's OpenAI account.

    @Test("A fresh install drops the key the last install left behind")
    func freshInstallClearsInheritedKey() {
        let store = InMemorySecretStore(initial: "sk-the-previous-familys-key")
        #expect(OpenAIKeyVault.clearIfInherited(hasRunBefore: false, store: store))
        #expect(store.read() == nil)
    }

    /// The case that makes this safe to ship. An upgrade keeps its UserDefaults,
    /// so it reports `true` — wiping there would delete a caregiver's own key on
    /// the first launch after an App Store update.
    @Test("An upgrade keeps the key it already had")
    func upgradeKeepsItsKey() {
        let store = InMemorySecretStore(initial: "sk-the-caregivers-own-key")
        #expect(!OpenAIKeyVault.clearIfInherited(hasRunBefore: true, store: store))
        #expect(store.read() == "sk-the-caregivers-own-key")
    }

    @Test("A first-ever install has nothing to clear")
    func firstEverInstallIsANoOp() {
        let store = InMemorySecretStore()
        #expect(!OpenAIKeyVault.clearIfInherited(hasRunBefore: false, store: store))
        #expect(store.read() == nil)
    }

    /// An env key belongs to whoever is launching the app right now — it is not
    /// an inheritance, and `clearIfInherited` reads the store directly so it
    /// cannot mistake one for the other.
    @Test("An environment key is not treated as inherited")
    func environmentKeyIsNotInherited() {
        let store = InMemorySecretStore()
        let env = ProcessInfo()
        #expect(!OpenAIKeyVault.clearIfInherited(hasRunBefore: false, store: store))
        // Nothing was stored, so nothing is there to have been wrongly cleared.
        #expect(OpenAIKeyVault.currentKey(env: env, store: store)
                == env.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespaces))
    }
}
