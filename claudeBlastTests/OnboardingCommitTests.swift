// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingCommitTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct OnboardingCommitTests {

    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "OnboardingCommitTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func patientInputs(name: String = "Aubrey", age: Int = 5,
                               pin: String? = "1234") -> OnboardingInputs {
        OnboardingInputs(
            role: .patient,
            authorName: "  Sammy  ",
            createChild: true,
            childName: name,
            childBirthday: ChildProfile.synthesizeBirthday(age: age, asOf: date(2026, 6, 4)),
            childVoiceID: "com.apple.voice.Samantha",
            childMaxTiles: 6,
            apiKey: "sk-onboarding",
            icloudEnabled: false,
            adminPIN: pin
        )
    }

    @Test func patient_withOnlySandbox_createsNewProfileAndDeactivatesSandbox() throws {
        // Regression: caregiver mode leaves a Sandbox row behind, and a
        // subsequent patient onboarding used to repurpose it instead of
        // creating a new real profile. The Sandbox must keep its identity;
        // a fresh ChildProfile is the patient.
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        // Seed the Sandbox the way ProfileMigration would.
        let sandbox = ChildProfile(
            displayName: "Sandbox",
            birthday: ChildProfile.synthesizeBirthday(age: 8),
            isActive: true,
            isSystem: true
        )
        ctx.insert(sandbox)

        OnboardingCommit.apply(patientInputs(name: "Aubrey"),
                               context: ctx, defaults: defaults, secretStore: secret)

        let all = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(all.count == 2) // Sandbox + new real profile
        let sandboxAfter = all.first(where: { $0.isSystem })!
        let aubrey = all.first(where: { !$0.isSystem })!
        #expect(sandboxAfter.displayName == "Sandbox")  // unchanged
        #expect(sandboxAfter.isActive == false)          // deactivated
        #expect(aubrey.displayName == "Aubrey")
        #expect(aubrey.isActive == true)
    }

    @Test func patient_supplyingPIN_hashesAndStoresIt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        OnboardingCommit.apply(patientInputs(pin: "654321"),
                               context: ctx, defaults: defaults, secretStore: secret)

        let device = try ctx.fetch(FetchDescriptor<DeviceProfile>())[0]
        #expect(device.adminPINSalt != nil)
        #expect(device.adminPINHash != nil)
        // Verifying with the supplied PIN must succeed.
        #expect(PINAuth.verify(pin: "654321",
                               hash: device.adminPINHash!,
                               salt: device.adminPINSalt!))
        #expect(!PINAuth.verify(pin: "0000",
                                hash: device.adminPINHash!,
                                salt: device.adminPINSalt!))
    }

    @Test func patient_skipPIN_leavesExistingPINUntouched() throws {
        // Returning patient device that already has a PIN from a prior
        // onboarding pass. Re-running commit without a PIN must not wipe it.
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        let device = DeviceProfileStore.ensure(context: ctx)
        let priorSalt = PINAuth.newSalt()
        let priorHash = PINAuth.hash(pin: "9999", salt: priorSalt)!
        device.adminPINSalt = priorSalt
        device.adminPINHash = priorHash

        OnboardingCommit.apply(patientInputs(pin: nil),
                               context: ctx, defaults: defaults, secretStore: secret)

        #expect(device.adminPINSalt == priorSalt)
        #expect(device.adminPINHash == priorHash)
    }

    @Test func patient_createsDeviceAndChild_andForcesFaceID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        OnboardingCommit.apply(patientInputs(), context: ctx, defaults: defaults, secretStore: secret)

        let devices = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.role == .patient)
        #expect(device.authorName == "Sammy") // whitespace trimmed
        #expect(device.requireFaceIDForAdmin == true)
        #expect(device.onboardingCompleted == true)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].displayName == "Aubrey")
        #expect(kids[0].isActive == true)
        #expect(kids[0].voiceIdentifier == "com.apple.voice.Samantha")
        #expect(kids[0].maxSelectedTiles == 6)
        #expect(kids[0].age == 5)

        #expect(secret.read() == "sk-onboarding")
        #expect(defaults.bool(forKey: AppSettingsKey.icloudEnabled) == false)
    }

    @Test func caregiver_skipsChildProfileCreation() throws {
        // Caregiver mode (formerly therapist + personal merged) doesn't
        // create a real ChildProfile during onboarding; the Sandbox
        // profile seeded by ProfileMigration carries the engine.
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs(pin: nil)
        inputs.role = .caregiver
        inputs.createChild = false
        inputs.adminPIN = nil

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        let devices = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(devices.first?.role == .caregiver)
        #expect(devices.first?.requireFaceIDForAdmin == false)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.isEmpty)
    }

    @Test func returningUser_updatesLegacyChildInPlace() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        // Simulate the post-migration state: Legacy ChildProfile + placeholder
        // DeviceProfile already exist before onboarding runs.
        let legacy = ChildProfile(
            displayName: "Legacy",
            birthday: ChildProfile.synthesizeBirthday(age: 7),
            voiceIdentifier: "",
            maxSelectedTiles: 4,
            isActive: true
        )
        ctx.insert(legacy)
        _ = DeviceProfileStore.ensure(context: ctx)

        OnboardingCommit.apply(patientInputs(name: "Aubrey", age: 5),
                               context: ctx, defaults: defaults, secretStore: secret)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1) // updated in place, not duplicated
        #expect(kids[0].displayName == "Aubrey")
        #expect(kids[0].maxSelectedTiles == 6)
        #expect(kids[0].isActive == true)
    }

    @Test func emptyChildName_doesNotCreateChild_evenWhenCreateChildTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.childName = "   " // whitespace only

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        // Device still gets set up, but no child profile created.
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ChildProfile>()).isEmpty)
    }

    @Test func nilApiKey_doesNotClobberStoredKey() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore(initial: "sk-from-env")
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.apiKey = nil // env-var path — leave Keychain alone

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(secret.read() == "sk-from-env")
    }

    @Test func emptyApiKey_explicitlyClears() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore(initial: "sk-old")
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.apiKey = "" // user pressed Skip

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(secret.read() == nil)
    }

    @Test func icloudFlag_isPersistedToDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.icloudEnabled = true

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(defaults.bool(forKey: AppSettingsKey.icloudEnabled) == true)
    }

    @Test func rerunningCommit_doesNotDuplicateRows() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        OnboardingCommit.apply(patientInputs(), context: ctx, defaults: defaults, secretStore: secret)
        OnboardingCommit.apply(patientInputs(name: "Aubrey 2"), context: ctx, defaults: defaults, secretStore: secret)

        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].displayName == "Aubrey 2")
    }
}
}
