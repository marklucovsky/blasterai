// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingCommit.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Inputs collected by `OnboardingView`, factored out so the final mutation
/// step is a pure function we can unit-test without instantiating SwiftUI.
struct OnboardingInputs {
    var role: DeviceRole
    /// The owner's display name, credited when this device shares content.
    /// Captured (skippably) only in caregiver setup; empty for patient setup.
    var authorName: String
    /// `true` when a real `ChildProfile` should be created/updated.
    /// Patient onboarding sets this; Caregiver onboarding leaves it false
    /// and the Sandbox profile (auto-seeded by `ProfileMigration`) serves
    /// as the active fallback.
    var createChild: Bool
    var childName: String
    var childBirthday: Date
    var childVoiceID: String
    var childMaxTiles: Int
    /// `nil` = don't touch the vault (env-var path is in play — the launch
    /// code already persisted the env key to the Keychain). `""` = explicit
    /// clear (user pressed Skip after a prior key was stored). Non-empty
    /// string = set to that value.
    var apiKey: String?
    var icloudEnabled: Bool
    /// 4–6 digit numeric PIN captured during patient onboarding. `nil` for
    /// therapist / personal flows. Commit hashes with a fresh salt and
    /// writes to DeviceProfile.adminPIN{Hash,Salt}.
    var adminPIN: String?
}

/// Materializes onboarding answers into SwiftData + UserDefaults + Keychain.
/// Called exactly once when the user taps "Open Blaster" on the final step.
///
/// Idempotent against re-runs: upserts the `DeviceProfile` singleton and the
/// `ChildProfile` if a Legacy one was seeded by `ProfileMigration`.
enum OnboardingCommit {
    static func apply(
        _ inputs: OnboardingInputs,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        secretStore: SecretStore = OpenAIKeyVault.defaultStore()
    ) {
        // 1. DeviceProfile — upsert.
        let device = DeviceProfileStore.ensure(context: context)
        device.role = inputs.role
        device.authorName = inputs.authorName.trimmingCharacters(in: .whitespaces)
        // Patient devices are *always* gated; therapists opt in later from
        // Admin → Device. Personal devices stay ungated.
        if inputs.role == .patient {
            device.requireFaceIDForAdmin = true
        }
        // Admin PIN — only set when supplied (patient onboarding step).
        // Skipping leaves the existing hash/salt in place so a returning
        // user doesn't accidentally lose their PIN by re-running onboarding.
        if let pin = inputs.adminPIN, PINAuth.isValidPINShape(pin) {
            let salt = PINAuth.newSalt()
            if let hash = PINAuth.hash(pin: pin, salt: salt) {
                device.adminPINSalt = salt
                device.adminPINHash = hash
            }
        }
        device.onboardingCompleted = true
        device.modifiedAt = .now

        // 2. ChildProfile — upsert if applicable.
        if inputs.createChild
            && !inputs.childName.trimmingCharacters(in: .whitespaces).isEmpty {
            // Only consider *real* profiles when deciding whether to
            // update-in-place vs create. The Sandbox profile (isSystem)
            // always exists post-migration and must never be repurposed
            // as the patient — that turns it into a real-looking profile
            // and leaves the resolver without a fallback target.
            let realProfiles = (try? context.fetch(
                FetchDescriptor<ChildProfile>(predicate: #Predicate { !$0.isSystem })
            )) ?? []
            if let kid = realProfiles.first {
                kid.displayName = inputs.childName.trimmingCharacters(in: .whitespaces)
                kid.birthday = inputs.childBirthday
                kid.voiceIdentifier = inputs.childVoiceID
                kid.maxSelectedTiles = inputs.childMaxTiles
                kid.isActive = true
                kid.modifiedAt = .now
            } else {
                let kid = ChildProfile(
                    displayName: inputs.childName.trimmingCharacters(in: .whitespaces),
                    birthday: inputs.childBirthday,
                    voiceIdentifier: inputs.childVoiceID,
                    maxSelectedTiles: inputs.childMaxTiles,
                    isActive: true
                )
                context.insert(kid)
            }
            // A real profile now owns the active slot — deactivate the
            // Sandbox so the resolver routes engine config through the
            // patient, not the generic defaults.
            let sandboxes = (try? context.fetch(
                FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
            )) ?? []
            for s in sandboxes where s.isActive {
                s.isActive = false
                s.modifiedAt = .now
            }
        }

        // 3. API key — Vault handles trim + empty-as-delete. Skip entirely
        // when inputs.apiKey is nil (env-var path) to avoid clobbering the
        // launch-persisted key.
        if let apiKey = inputs.apiKey {
            OpenAIKeyVault.setKey(apiKey, store: secretStore)
        }

        // 4. iCloud preference — UserDefaults. Container rebuilds at next launch.
        defaults.set(inputs.icloudEnabled, forKey: AppSettingsKey.icloudEnabled)

        // No explicit context.save() — SwiftUI's .modelContainer enables
        // autosave (flushes on background + every few seconds). An explicit
        // save() at this point also throws an unrecoverable SIGABRT on the
        // in-memory test container when inserting DeviceProfile +
        // ChildProfile in the same transaction; needs investigation if a
        // similar crash ever surfaces in production.
    }
}
