// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  DeviceProfile.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Per-device identity + posture. Never synced — each device has its own.
/// Backed by a separate ModelConfiguration with `cloudKitDatabase: .none`
/// so a therapist's iPad and their iPhone can have different roles even
/// when ChildProfile data syncs between them.
@Model
final class DeviceProfile {
    var id: String = UUID().uuidString
    /// `DeviceRole.rawValue`. Stored as String for SwiftData/CloudKit compat
    /// even though this entity is local-only — keeps modeling consistent.
    var roleRaw: String = DeviceRole.caregiver.rawValue
    /// Patient devices: always true (forced at onboarding). Caregiver
    /// devices: false by default; the therapist can opt in.
    var requireFaceIDForAdmin: Bool = false
    /// PBKDF2-hashed PIN used as Face ID fallback. nil = no PIN set yet.
    /// Wired in commit 6; declared here so the schema is stable.
    var adminPINHash: Data?
    var adminPINSalt: Data?
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    /// Stable, self-generated author identity for scenes this device authors —
    /// the "phone number". Minted lazily (empty until first needed) by
    /// `DeviceProfileStore.ensureAuthorID`; never synced. Two authors' scenes of
    /// the same name are distinguished by this, with no central registry.
    var authorID: String = ""
    /// The device owner's optional display name — the one identity the app
    /// captures. Credited when this device shares scenes, pages, or vocabulary
    /// packs it creates ("by Greta"); travels inside exported files. May stay
    /// empty; captured (skippably) at caregiver setup or set later in Scenes.
    var authorName: String = ""

    var role: DeviceRole {
        get { DeviceRole.fromRawValue(roleRaw) }
        set { roleRaw = newValue.rawValue; modifiedAt = .now }
    }

    init(role: DeviceRole = .caregiver,
         requireFaceIDForAdmin: Bool = false, onboardingCompleted: Bool = false) {
        self.roleRaw = role.rawValue
        self.requireFaceIDForAdmin = requireFaceIDForAdmin
        self.onboardingCompleted = onboardingCompleted
    }
}

/// Two-mode model after the role simplification:
///
/// - `.patient` — the device is in the hands of a non-verbal child. The
///   engine uses the active ChildProfile (a real kid). Admin is gated.
/// - `.caregiver` — the device belongs to an adult (therapist, parent,
///   tester). The engine uses the Sandbox ChildProfile by default; adults
///   can also activate any real patient profile for preview / management.
///   Admin is ungated unless the therapist opts in.
enum DeviceRole: String, CaseIterable, Codable {
    case patient
    case caregiver

    /// Any value that isn't the explicit patient role resolves to `.caregiver` —
    /// the safe default, since it never silently gates a device the owner didn't
    /// intend to lock down. This also absorbs values written by other builds
    /// (the retired `"personal"` / `"therapist"` raws normalized here before the
    /// pre-promotion audit; `ProfileMigration` rewrites stored values to canonical
    /// form on launch).
    static func fromRawValue(_ raw: String) -> DeviceRole {
        switch raw {
        case "patient": return .patient
        default:        return .caregiver
        }
    }

    var displayName: String {
        switch self {
        case .patient:   return "Patient"
        case .caregiver: return "Caregiver"
        }
    }

    var summary: String {
        switch self {
        case .patient:
            return "This device is for a non-verbal child to use as their voice. Admin is locked behind Face ID + PIN so the child can't change things by accident. The child's profile drives the voice and AI prompts."
        case .caregiver:
            return "This device is for you — a therapist, parent, or family member. The Sandbox profile drives generic use; you can add real patient profiles and switch between them to tune scenes. Admin is open by default."
        }
    }

    /// Used as the onboarding step-2 footer so the user knows nothing they
    /// pick here is permanent. Reinforces that the modes are reversible.
    static var reversibilityNote: String {
        "You can switch a device between Patient and Caregiver mode anytime from Admin → Device. None of these choices are permanent."
    }
}
