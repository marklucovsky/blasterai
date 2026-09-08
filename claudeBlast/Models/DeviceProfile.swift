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
    var roleRaw: String = DeviceProfile.defaultRole.rawValue
    /// Patient devices: always true (forced at onboarding). Caregiver
    /// devices: false by default; the therapist can opt in.
    var requireFaceIDForAdmin: Bool = false
    /// PBKDF2-hashed PIN used as the biometric fallback — and as the *only*
    /// unlock on a device with no biometry, such as a Mac. nil = no PIN set yet.
    /// Wired in commit 6; declared here so the schema is stable.
    var adminPINHash: Data?
    var adminPINSalt: Data?
    var onboardingCompleted: Bool = false
    /// Temporarily run **this device** in a different interaction mode than the
    /// active child's Brown's Stage implies. `InteractionMode.rawValue`, or
    /// empty for "follow the stage". Persists until changed back — it does not
    /// time out, because there is no defined session boundary to time out on,
    /// and a mode that changes by itself mid-session is worse than one that
    /// doesn't.
    ///
    /// **Both directions, deliberately.** A first version stored a
    /// `singleWordOverride: Bool` that could only force single words *on*. With
    /// Stage I as the default, a child profile already resolves to single words,
    /// so "Switch to AI Sentences" cleared a flag that was never set and the
    /// toggle did nothing at all — a no-op in exactly the default configuration.
    /// A one-way override cannot back a two-way control.
    ///
    /// ## Why this lives here and not on `ChildProfile`
    ///
    /// A caregiver removing the sentence button for Thursday's session is
    /// making a statement about *this afternoon on this iPad* — not about the
    /// child's development. Until 2026-08-24 the toggle wrote
    /// `ChildProfile.interactionMode`, a **synced** field, so a situational
    /// flip propagated to every device the child's profile touched and
    /// overwrote a clinical setting with a scheduling one.
    ///
    /// `DeviceProfile` is `cloudKitDatabase: .none`, so this never leaves the
    /// device. The child's Brown's Stage stays the durable answer and is
    /// untouched; this is the transient one. Two settings, two lifetimes, two
    /// homes.
    var modeOverrideRaw: String = ""

    /// Typed accessor over `modeOverrideRaw`. `nil` means "follow the active
    /// child's stage".
    var modeOverride: InteractionMode? {
        get { InteractionMode(rawValue: modeOverrideRaw) }
        set {
            modeOverrideRaw = newValue?.rawValue ?? ""
            modifiedAt = .now
        }
    }
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

    /// What a device is until someone says otherwise, and the value onboarding
    /// preselects. One constant, because two independent "defaults" for the
    /// same field is how they came to disagree.
    ///
    /// Caregiver, because it is the safe answer for a device that never
    /// finishes setup: a device wrongly marked patient is PIN-gated with no PIN
    /// enrolled, while one wrongly marked caregiver is merely more open than it
    /// should be — and the person holding an unconfigured device is the adult
    /// setting it up, not the child.
    static let defaultRole: DeviceRole = .caregiver

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
            return "This device is for a non-verbal child to use as their voice. Admin is locked behind a PIN (and biometrics where the device has them) so the child can't change things by accident. The child's profile drives the voice and AI prompts."
        case .caregiver:
            return "This device is for you — a therapist, parent, or family member. Your own profile drives generic use; you can add child profiles and switch between them to tune scenes. Admin is open by default."
        }
    }

    /// Used as the onboarding step-2 footer so the user knows nothing they
    /// pick here is permanent. Reinforces that the modes are reversible.
    static var reversibilityNote: String {
        "You can switch a device between Patient and Caregiver mode anytime from Admin → Device. None of these choices are permanent."
    }
}
