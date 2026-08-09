// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfileMigration.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Default display name for the Sandbox profile. The caregiver can rename
/// it from Admin → Profiles, but the row is always identified by `isSystem`.
let kSandboxProfileDefaultName = "Sandbox"

/// Stable, SHARED id for the Sandbox profile — fixed, not a random UUID. The
/// Sandbox is auto-seeded independently on every device, so a random id would
/// give each device a different `childID`; anything keyed on the active child
/// (durable-override `stableKey`, `SentenceCache.childID`, `LoggedUtterance`)
/// would then only line up cross-device by luck of CloudKit dedup. A fixed id
/// makes the Sandbox's childID identical everywhere by construction, so caregiver
/// overrides sync correctly on the profile caregivers actually test on.
let kSandboxProfileID = "system.sandbox"

/// One-shot migration that runs after `BootstrapLoader` at app launch.
///
/// Three jobs:
/// 1. Materialize the singleton `DeviceProfile` and normalize any unrecognized
///    role value onto the two-mode model (anything but `patient` → `caregiver`).
/// 2. Ensure exactly one Sandbox (`isSystem == true`) ChildProfile exists.
///    The resolver returns this profile when no real child is active, so
///    the engine never has to handle an empty roster.
/// 3. For *returning users* (`bootstrapInstalled` was already true at
///    launch), seed a "Legacy" real ChildProfile pre-populated with their
///    prior voice and tile-cap. Onboarding pre-fills from it.
enum ProfileMigration {

    /// Run after `BootstrapLoader.loadDefaultVocabulary` / `needsBootstrap`.
    ///
    /// - Parameters:
    ///   - context: model context to mutate
    ///   - seedLegacy: pass `true` for returning users (the
    ///     `bootstrapInstalled` flag was set before this launch), `false`
    ///     for fresh installs.
    ///   - defaults: injected for test isolation. Defaults to `.standard`.
    ///   - now: clock injection for the Legacy birthday synthesis.
    static func ensureProfilesAfterBootstrap(
        context: ModelContext,
        seedLegacy: Bool,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        let device = DeviceProfileStore.ensure(context: context)
        normalizeLegacyRole(device)
        ensureSandboxProfile(context: context, now: now)

        guard seedLegacy else { return }

        let existing = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        // Skip if there's already a real (non-Sandbox) child profile.
        if existing.contains(where: { !$0.isSystem }) { return }

        let voiceID = defaults.string(forKey: AppSettingsKey.speechVoiceIdentifier) ?? ""
        // tile_cap_per_group is engine-clamped to [2, 8]; mirror that here.
        let rawCap = defaults.integer(forKey: AppSettingsKey.tileCapPerGroup)
        let tileCap = rawCap > 0 ? min(8, max(2, rawCap)) : 4

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let legacy = ChildProfile(
            displayName: "Legacy",
            birthday: ChildProfile.synthesizeBirthday(age: 7, asOf: now),
            voiceIdentifier: voiceID,
            maxSelectedTiles: tileCap,
            defaultSceneKey: "",
            notes: "Seeded from prior install at \(isoFormatter.string(from: now))",
            isActive: true
        )
        context.insert(legacy)
        // The Legacy real profile is now active — deactivate Sandbox so the
        // resolver routes engine config through Legacy rather than the
        // generic defaults.
        deactivateSandboxIfActive(context: context)
    }

    // MARK: - Sandbox profile

    private static func ensureSandboxProfile(context: ModelContext, now: Date) {
        let existing = (try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
        )) ?? []
        guard existing.isEmpty else { return }

        let realProfiles = (try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { !$0.isSystem })
        )) ?? []
        let anyRealActive = realProfiles.contains(where: { $0.isActive })

        let sandbox = ChildProfile(
            displayName: kSandboxProfileDefaultName,
            birthday: ChildProfile.synthesizeBirthday(age: 8, asOf: now),
            voiceIdentifier: "",
            maxSelectedTiles: 4,
            defaultSceneKey: "",
            notes: "Default profile used when no real child is active.",
            // Sandbox is active iff no real profile owns the slot already.
            isActive: !anyRealActive,
            isSystem: true
        )
        sandbox.id = kSandboxProfileID   // stable across devices (see constant)
        context.insert(sandbox)
    }

    private static func deactivateSandboxIfActive(context: ModelContext) {
        let sandboxes = (try? context.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
        )) ?? []
        for s in sandboxes where s.isActive {
            s.isActive = false
            s.modifiedAt = .now
        }
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
