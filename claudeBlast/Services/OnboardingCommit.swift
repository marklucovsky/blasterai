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
    var childStage: BrownsStage
    var childVoiceID: String
    var childMaxTiles: Int
    /// `nil` = don't touch the vault (the DEBUG env-var path is in play, and
    /// that key is read from the environment, never stored). `""` = explicit
    /// clear (user pressed Skip after a prior key was stored). Non-empty
    /// string = set to that value — stored only if `aiConsent` is true.
    var apiKey: String?
    /// The caregiver's answer to the AI disclosure. Onboarding records it the
    /// moment they answer, so a key file opened mid-setup can install; the
    /// commit writes it again so the final state is whatever they settled on
    /// after any Back and forth. See `AIConsent`.
    var aiConsent: Bool = false

    /// What the onboarding screen's key field means for the vault.
    ///
    /// An empty field means "leave the vault alone", not "delete". The field is
    /// not the only way a key arrives during setup: a key file installs straight
    /// into the Keychain, and Skip used to clear the field and commit that
    /// emptiness — deleting the gifted key the caregiver had just installed.
    /// Nothing typed is stored before the commit, so there is nothing an empty
    /// field ever needs to delete. The DEBUG environment key is never stored.
    static func keyToCommit(_ field: String, hasEnvKey: Bool) -> String? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasEnvKey || trimmed.isEmpty ? nil : trimmed
    }
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
                kid.brownsStage = inputs.childStage
                kid.voiceIdentifier = inputs.childVoiceID
                // setTileCap after the stage so the two reconcile — and so a
                // caregiver who picked a wider cap promotes the stage rather
                // than silently having the number clamped back.
                kid.setTileCap(inputs.childMaxTiles)
                kid.isActive = true
                kid.modifiedAt = .now
            } else {
                let kid = ChildProfile(
                    displayName: inputs.childName.trimmingCharacters(in: .whitespaces),
                    brownsStage: inputs.childStage,
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

        // 3. AI permission, then the key it permits. Accepting again is not a
        // no-op — it would move the accepted date — so an answer already on
        // record is left alone.
        if inputs.aiConsent {
            if !AIConsent.isGranted(defaults) { AIConsent.accept(defaults) }
        } else {
            AIConsent.revoke(defaults)
        }
        // Vault handles trim + empty-as-delete, and refuses a key without
        // permission. Skip entirely when inputs.apiKey is nil (env-var path).
        if let apiKey = inputs.apiKey {
            OpenAIKeyVault.setKey(apiKey, store: secretStore,
                                  consentGranted: AIConsent.isGranted(defaults))
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
