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

    /// One profile, and it is the caregiver's. There is no longer a second
    /// seeded row: "Legacy" was a migration artefact that arrived beside the
    /// caregiver profile with nothing to tell a caregiver why either existed,
    /// and its name ended up as the title of the first usage report.
    @Test func freshInstall_seedsOnlyTheCaregiverProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.test", forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)

        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)

        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].isSystem == true)
        #expect(kids[0].isActive == true) // the resolver's fallback
        #expect(kids[0].id == kCaregiverProfileID) // stable, shared across devices
    }

    /// A returning user gets the same thing a fresh install does. Their prior
    /// voice and tile-cap are still in UserDefaults where the engine reads them;
    /// what is gone is the extra *profile* that used to be conjured to hold them.
    @Test func returningUser_getsNoExtraProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.compact.en-US.Samantha",
                     forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)
        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)

        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].isSystem == true)
        #expect(!kids.contains { $0.displayName == "Legacy" })
    }

    /// The caregiver profile is auto-seeded independently per device, so its id
    /// must be a fixed constant (not a random UUID) — otherwise `childID`-keyed
    /// data (durable overrides, cache, logs) would not line up cross-device.
    /// Simulate two independent installs and assert they converge.
    @Test func caregiverProfile_hasStableIdAcrossIndependentInstalls() throws {
        func seedID() throws -> String {
            let ctx = try makeContainer().mainContext
            ProfileMigration.ensureProfilesAfterBootstrap(
                context: ctx, defaults: isolatedDefaults())
            let caregiver = try #require(
                try ctx.fetch(FetchDescriptor<ChildProfile>()).first { $0.isSystem })
            return caregiver.id
        }
        #expect(try seedID() == kCaregiverProfileID)
        #expect(try seedID() == seedID())   // identical across installs
    }

    @Test func idempotent_neverDuplicatesTheCaregiverProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        for _ in 0..<3 {
            ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)
        }

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids.filter { $0.isSystem }.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
    }

    /// A child that arrived from another synced device keeps the active slot —
    /// seeding must not steal it, or the board changes under a caregiver who
    /// merely launched the app on a second device.
    @Test func existingChildKeepsTheActiveSlot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        let existing = ChildProfile(
            displayName: "Aubrey",
            brownsStage: .twoThree,
            voiceIdentifier: "real-voice",
            maxSelectedTiles: 6,
            isActive: true
        )
        ctx.insert(existing)

        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 2)   // Aubrey + the caregiver profile
        let aubrey = try #require(kids.first { !$0.isSystem })
        #expect(aubrey.displayName == "Aubrey")
        #expect(aubrey.isActive)
        let caregiver = try #require(kids.first { $0.isSystem })
        #expect(!caregiver.isActive)
    }

    // MARK: - Caregiver profile + role normalization

    @Test func caregiverProfile_seededOnce() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)

        let seeded = try ctx.fetch(FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isSystem }
        ))
        #expect(seeded.count == 1)
        #expect(seeded[0].displayName == kCaregiverProfileDefaultName)
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

        ProfileMigration.ensureProfilesAfterBootstrap(context: ctx, defaults: defaults)

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
            context: ctx, defaults: defaults)

        let fetched = try ctx.fetch(FetchDescriptor<DeviceProfile>())[0]
        #expect(fetched.roleRaw == "patient")
        #expect(fetched.role == .patient)
    }
}
}
