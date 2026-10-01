// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AIConsent.swift
//  claudeBlast
//

import Foundation

/// Explicit permission to send anything to OpenAI, recorded per device.
///
/// A child's words are sometimes the most personal thing on the device —
/// *mom, hospital, tomorrow*; *I, feel, sick*; *grandma, died*. No name or
/// identifier goes with them, but they are still the family's to send or not,
/// and App Review guideline 5.1.2 asks for explicit permission before personal
/// data reaches a third-party AI. This is that permission.
///
/// ## A version, not a flag
///
/// What a caregiver agreed to is the disclosure they read. If what goes to
/// OpenAI ever changes — a new feature, a new kind of data — `currentVersion`
/// goes up with the new text, every device reads as not granted, and each one
/// is asked again. Nothing else in the app has to know that happened.
///
/// A device that has never answered reads as version 0. That is exactly the
/// state of every tester's device from before this existed, which is why there
/// is no migration: their key goes dormant and they are shown version 1 once.
///
/// ## Where it is enforced
///
/// Two places, not every call site. `OpenAIClient.send` refuses — every request
/// in the app passes through it, so nothing can reach OpenAI without permission.
/// And `SentenceEngine.canGenerateSentences` is false without it, so the board
/// drops to single words rather than failing every tap.
///
/// Revoking leaves an installed key where it is, dormant: turning AI back on is
/// one tap, not a new key. Installing a key, on the other hand, requires
/// permission first — `OpenAIKeyVault.setKey` refuses without it.
///
/// Device-local UserDefaults, never synced. Each device's caregiver answers for
/// that device, and a Patient device is often not the one where the key was
/// first entered.
enum AIConsent {

    /// The disclosure every device must have accepted.
    ///
    /// History — what each version said, so it is always possible to say what
    /// someone agreed to. Append when raising; never edit an old entry.
    ///
    /// - **1** (2026-09-30): Sentence Generation (selected words), Vocabulary
    ///   Images (a word or description), Scene Generation (a description of a
    ///   situation). No name, device identifiers or other
    ///   identifying information. See `AIDisclosureView`.
    static let currentVersion = 1

    /// The version this device accepted; 0 if it never has, or revoked.
    static func acceptedVersion(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: AppSettingsKey.aiConsentVersion)
    }

    /// When the accepted version was accepted.
    static func acceptedAt(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: AppSettingsKey.aiConsentAcceptedAt) as? Date
    }

    /// Whether this device may send anything to OpenAI right now.
    ///
    /// `current` is a parameter so a test can raise the version without
    /// shipping a new disclosure.
    static func isGranted(_ defaults: UserDefaults = .standard,
                          current: Int = currentVersion) -> Bool {
        acceptedVersion(defaults) >= current
    }

    /// The caregiver accepted the disclosure they were shown.
    static func accept(_ defaults: UserDefaults = .standard,
                       version: Int = currentVersion,
                       now: Date = .now) {
        defaults.set(version, forKey: AppSettingsKey.aiConsentVersion)
        defaults.set(now, forKey: AppSettingsKey.aiConsentAcceptedAt)
        markPrompted(defaults, version: version)
    }

    /// Permission withdrawn. Any installed key stays, unused.
    static func revoke(_ defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: AppSettingsKey.aiConsentVersion)
        defaults.removeObject(forKey: AppSettingsKey.aiConsentAcceptedAt)
    }

    // MARK: - Asking once

    /// Whether to put the disclosure in front of a caregiver without being asked.
    ///
    /// Only when there is a key that permission would switch on — a device with
    /// no key has nothing to decide yet, and meets the disclosure when it goes
    /// to add one. And only once per version: "Not now" is an answer, and asking
    /// again at every launch would make it a nag.
    static func shouldPrompt(_ defaults: UserDefaults = .standard,
                             hasKey: Bool,
                             current: Int = currentVersion) -> Bool {
        hasKey
            && !isGranted(defaults, current: current)
            && defaults.integer(forKey: AppSettingsKey.aiConsentPromptedVersion) < current
    }

    /// Record that this version's disclosure was shown, whatever the answer.
    static func markPrompted(_ defaults: UserDefaults = .standard,
                             version: Int = currentVersion) {
        defaults.set(version, forKey: AppSettingsKey.aiConsentPromptedVersion)
    }

    #if DEBUG
    /// Back to a device that has never been asked, so the disclosure flow can be
    /// walked again without reinstalling.
    static func resetForTesting(_ defaults: UserDefaults = .standard) {
        revoke(defaults)
        defaults.removeObject(forKey: AppSettingsKey.aiConsentPromptedVersion)
    }
    #endif
}

/// Thrown by `OpenAIClient.send` when a request would reach OpenAI without
/// permission.
enum AIConsentError: LocalizedError, Equatable {
    case notGranted

    var errorDescription: String? {
        "AI features are turned off on this device."
    }
}
