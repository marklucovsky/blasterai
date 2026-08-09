// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfileMigrationTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ProfileMigrationTests {

    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    /// Isolated UserDefaults so writes from one test don't leak into another.
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ProfileMigrationTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    @Test func freshInstall_doesNotSeedLegacy() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.test", forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: false,
            defaults: defaults
        )

        // DeviceProfile always materialized.
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        // Sandbox profile is always present; no real (Legacy) profile on
        // a fresh install.
        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].isSystem == true)
        #expect(kids[0].isActive == true) // Sandbox is the resolver fallback
        #expect(kids[0].id == kSandboxProfileID) // stable, shared across devices
    }

    /// The Sandbox is auto-seeded independently per device, so its id must be a
    /// fixed constant (not a random UUID) — otherwise `childID`-keyed data
    /// (durable overrides, cache, logs) wouldn't line up cross-device. Simulate
    /// two independent installs and assert they converge on the same Sandbox id.
    @Test func sandbox_hasStableIdAcrossIndependentInstalls() throws {
        func seedSandboxID() throws -> String {
            let ctx = try makeContainer().mainContext
            ProfileMigration.ensureProfilesAfterBootstrap(
                context: ctx, seedLegacy: false, defaults: isolatedDefaults())
            let sandbox = try #require(
                try ctx.fetch(FetchDescriptor<ChildProfile>()).first { $0.isSystem })
            return sandbox.id
        }
        #expect(try seedSandboxID() == kSandboxProfileID)
        #expect(try seedSandboxID() == seedSandboxID())   // identical across installs
    }

    @Test func returningUser_seedsLegacyFromUserDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.compact.en-US.Samantha",
                     forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)

        let stableNow = Calendar.current.date(from: DateComponents(
            year: 2026, month: 6, day: 4))!
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults,
            now: stableNow
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        // Legacy real profile + Sandbox.
        #expect(kids.count == 2)
        let legacy = kids.first(where: { !$0.isSystem })!
        #expect(legacy.displayName == "Legacy")
        #expect(legacy.isActive == true)
        #expect(legacy.voiceIdentifier == "com.apple.voice.compact.en-US.Samantha")
        #expect(legacy.maxSelectedTiles == 5)
        #expect(legacy.age == 7)
        // Sandbox exists but is NOT active (Legacy owns the active slot).
        let sandbox = kids.first(where: { $0.isSystem })!
        #expect(sandbox.isActive == false)
    }

    @Test func returningUser_withUnsetDefaults_seedsLegacyWithSafeDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        // No keys set.

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        // Legacy real profile + Sandbox.
        #expect(kids.count == 2)
        let legacy = kids.first(where: { !$0.isSystem })!
        #expect(legacy.voiceIdentifier == "")
        #expect(legacy.maxSelectedTiles == 4) // safe fallback
    }

    @Test func returningUser_clampsOutOfRangeTileCap() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set(99, forKey: AppSettingsKey.tileCapPerGroup) // out of range

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        let legacy = kids.first(where: { !$0.isSystem })!
        #expect(legacy.maxSelectedTiles == 8) // clamped to engine max
    }

    @Test func idempotent_doesNotSeedLegacyTwice() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)

        // Legacy + Sandbox, never duplicated.
        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 2)
        #expect(kids.filter { $0.isSystem }.count == 1)
        #expect(kids.filter { !$0.isSystem }.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
    }

    @Test func skipsLegacy_whenChildProfileAlreadyExists() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.test", forKey: AppSettingsKey.speechVoiceIdentifier)

        // User already has a child (e.g., went through onboarding on another
        // synced device).
        let existing = ChildProfile(
            displayName: "Aubrey",
            birthday: ChildProfile.synthesizeBirthday(age: 5),
            voiceIdentifier: "real-voice",
            maxSelectedTiles: 6,
            isActive: true
        )
        ctx.insert(existing)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        // Aubrey (existing real) + Sandbox. Legacy not seeded since real exists.
        #expect(kids.count == 2)
        let aubrey = kids.first(where: { !$0.isSystem })!
        #expect(aubrey.displayName == "Aubrey") // unchanged
        #expect(aubrey.voiceIdentifier == "real-voice")
    }

    // MARK: - Sandbox + role normalization

    @Test func sandboxProfile_seededOnce() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: false, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: false, defaults: defaults)

        let sandboxes = try ctx.fetch(FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isSystem }
        ))
        #expect(sandboxes.count == 1)
        #expect(sandboxes[0].displayName == kSandboxProfileDefaultName)
    }

    /// The invariant, stated without reference to any particular retired value:
    /// a role string this build doesn't recognize resolves to `.caregiver` and is
    /// rewritten to canonical form on launch. `.caregiver` is the safe landing
    /// spot — it never silently gates a device the owner didn't mean to lock.
    ///
    /// Covers the retired `"personal"` / `"therapist"` raws (removed from
    /// `DeviceRole.fromRawValue` in the pre-promotion schema audit) and anything
    /// else an older or newer build might have written.
    @Test(arguments: ["personal", "therapist", "", "some_future_role"])
    func unrecognizedRoleValue_normalizesToCaregiver(_ raw: String) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        let device = DeviceProfile(role: .caregiver)
        device.roleRaw = raw
        ctx.insert(device)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: false, defaults: defaults)

        let fetched = try ctx.fetch(FetchDescriptor<DeviceProfile>())[0]
        #expect(fetched.roleRaw == "caregiver")
        #expect(fetched.role == .caregiver)
    }

    /// The one value that must NOT be absorbed by the default branch.
    @Test func patientRoleValue_isPreserved() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        let device = DeviceProfile(role: .patient)
        ctx.insert(device)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: false, defaults: defaults)

        let fetched = try ctx.fetch(FetchDescriptor<DeviceProfile>())[0]
        #expect(fetched.roleRaw == "patient")
        #expect(fetched.role == .patient)
    }
}
}
