// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  Biometry.swift
//  claudeBlast
//
//  What this device calls its biometric unlock, if it has one.
//

import Foundation
import LocalAuthentication

/// The biometric capability of the current device, named the way the person
/// holding it would name it.
///
/// ## Why this exists
///
/// The app said "Face ID" in seven pieces of user-facing copy, including a
/// button labelled *Try Face ID*. That was true on the iPads it was written for
/// and false everywhere else: an iPhone SE has Touch ID, and a Mac running the
/// app as Designed-for-iPad may have Touch ID or no biometry at all. Telling a
/// caregiver on a MacBook that "Face ID isn't enrolled on this device" is
/// confusing at best; offering them a Face ID button is simply wrong.
///
/// `AdminGate` already *behaved* correctly — `canEvaluatePolicy` returning false
/// sends it to the PIN path — so this is about the words, which is exactly the
/// part a caregiver locked out of Admin has to rely on.
///
/// ## Reading `biometryType`
///
/// `LAContext.biometryType` is only populated **after** `canEvaluatePolicy` has
/// been called on that context. Reading it from a fresh `LAContext` returns
/// `.none` regardless of hardware, which is a quiet way to get this wrong.
enum Biometry {

    /// What the device supports and whether it is usable right now.
    struct Capability {
        let type: LABiometryType
        /// True when biometric evaluation can actually be attempted — hardware
        /// present *and* enrolled *and* not locked out.
        let isAvailable: Bool

        /// The device's name for its biometry, e.g. "Face ID". Falls back to a
        /// generic phrase when there is no biometric hardware, so copy that
        /// interpolates this never reads as a broken sentence.
        var displayName: String {
            switch type {
            case .faceID:  return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            default:       return "biometric unlock"
            }
        }

        /// True when the device has biometric hardware at all, enrolled or not.
        /// Distinct from `isAvailable`: a Mac with no Touch Bar has no hardware
        /// and should never be told to "enroll", while an iPhone with Face ID
        /// switched off should.
        var hasHardware: Bool { type != .none }
    }

    /// Probe the current device. Cheap and local, but not free — cache it in a
    /// view's state rather than calling from a `body` that re-renders.
    static func capability() -> Capability {
        let ctx = LAContext()
        var error: NSError?
        let can = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error)
        // biometryType is only meaningful after canEvaluatePolicy — see above.
        return Capability(type: ctx.biometryType, isAvailable: can)
    }

    /// The device's biometry name for use in static copy (onboarding, settings
    /// footers) where carrying a `Capability` through would be noise.
    static var displayName: String { capability().displayName }
}
