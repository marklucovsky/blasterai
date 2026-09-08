// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfileMigration.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Default display name for the caregiver's own profile. Renameable from
/// Admin → Profiles; the row is always identified by `isSystem`, never by name.
///
/// It was called "Sandbox", which described its job to us and nothing at all to
/// a caregiver. The name matters more than it used to: it heads the usage report
/// a therapist reads, and it sits in a list beside real children's names.
let kCaregiverProfileDefaultName = "My Profile"

/// Stable, SHARED id for the caregiver profile — fixed, not a random UUID. It is
/// auto-seeded independently on every device, so a random id would give each
/// device a different `childID`; anything keyed on the active child
/// (durable-override `stableKey`, `SentenceCache.childID`, `LoggedUtterance`)
/// would then only line up cross-device by luck of CloudKit dedup. A fixed id
/// makes this row's childID identical everywhere by construction, so caregiver
/// overrides sync correctly on the profile caregivers actually test on.
///
/// The string is unchanged on purpose. The value is internal — nothing displays it — and it is
/// the join key that makes this row the same row on every one of the caregiver's
/// devices. Renaming the constant is free; changing the string would fork it.
let kCaregiverProfileID = "system.sandbox"

/// One-shot migration that runs after `BootstrapLoader` at app launch.
///
/// Two jobs:
/// 1. Materialize the singleton `DeviceProfile` and normalize any unrecognized
///    role value onto the two-mode model (anything but `patient` → `caregiver`).
/// 2. Ensure exactly one caregiver (`isSystem == true`) ChildProfile exists.
///    The resolver returns this profile when no child is active, so the engine
///    never has to handle an empty roster.
///
/// It used to have a third: seeding a "Legacy" profile from a returning user's
/// prior voice and tile-cap. That is gone. It produced a second undeletable-
/// looking row beside the caregiver profile with no way for anyone to tell why
/// either was there, and the name — chosen when nothing displayed it — ended up
/// as the largest word on the first usage report. One profile now covers both
/// jobs, and a returning user's settings are already on the device anyway.
enum ProfileMigration {

    /// Run after `BootstrapLoader.loadDefaultVocabulary` / `needsBootstrap`.
    ///
    /// - Parameters:
    ///   - context: model context to mutate
    ///   - defaults: injected for test isolation. Defaults to `.standard`.
    ///   - now: clock injection for the seeded profile's timestamp.
    static func ensureProfilesAfterBootstrap(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        let device = DeviceProfileStore.ensure(context: context)
        normalizeLegacyRole(device)
        ensureCaregiverProfile(context: context, now: now)
    }

    // MARK: - Caregiver profile

    private static func ensureCaregiverProfile(context: ModelContext, now: Date) {
        let existing = (try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
        )) ?? []
        guard existing.isEmpty else { return }

        let realProfiles = (try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { !$0.isSystem })
        )) ?? []
        let anyRealActive = realProfiles.contains(where: { $0.isActive })

        // Stage I is the floor and the safe direction to fail: a device with
        // no real child yet speaks one word per tap rather than generating
        // sentences for a child nobody has described. Onboarding replaces this
        // with a stage a caregiver actually chose.
        let caregiver = ChildProfile(
            displayName: kCaregiverProfileDefaultName,
            brownsStage: .one,
            voiceIdentifier: "",
            defaultSceneKey: "",
            notes: "Used when no child is selected. Holds this caregiver's own settings.",
            // Active iff no real profile owns the slot already.
            isActive: !anyRealActive,
            isSystem: true
        )
        caregiver.id = kCaregiverProfileID   // stable across devices (see constant)
        context.insert(caregiver)
    }

    // MARK: - Role normalization

    /// Rewrite any stored role that isn't already canonical (`patient` /
    /// `caregiver`) to its resolved value, so the store converges on the
    /// two-mode vocabulary. Idempotent.
    private static func normalizeLegacyRole(_ device: DeviceProfile) {
        let normalized = DeviceRole.fromRawValue(device.roleRaw).rawValue
        if device.roleRaw != normalized {
            device.roleRaw = normalized
            device.modifiedAt = .now
        }
    }
}
