// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PINThrottle.swift
//  claudeBlast
//
//  How long to wait after a wrong PIN.
//

import Foundation

/// Escalating delays on repeated wrong PINs.
///
/// **Sized for the threat model, which is a curious child, not an attacker.**
/// A four-digit PIN is ten thousand combinations; unthrottled, a determined
/// eight-year-old with an afternoon will find it, and the point of the lock is
/// that Admin holds the API key, the child's history and every board. The delays
/// below turn an afternoon into weeks without ever making a caregiver who
/// mistyped their own PIN wait more than a moment.
///
/// The first few misses cost nothing on purpose. A parent fumbling a PIN twice
/// with a child on their lap is the common case by a wide margin, and punishing
/// it is how a lock stops being used.
///
/// Deliberately its own type rather than a couple of `if`s inside `AdminGate`:
/// the escalation is the security property here, and a security property that
/// lives in a view is one nothing can test.
enum PINThrottle {

    /// Misses allowed before any delay at all.
    static let freeAttempts = 4

    /// The delay owed after `failedAttempts` consecutive misses.
    ///
    /// Nil for the first few, then a minute, five, fifteen, and an hour — the
    /// last of which is a wall a child gives up at and a parent simply waits
    /// out, having by then almost certainly remembered the PIN.
    static func delay(afterFailedAttempts failedAttempts: Int) -> TimeInterval? {
        switch failedAttempts {
        case ..<(freeAttempts + 1): return nil
        case freeAttempts + 1:      return 60
        case freeAttempts + 2:      return 5 * 60
        case freeAttempts + 3:      return 15 * 60
        default:                    return 60 * 60
        }
    }

    /// When entry reopens after a miss, or nil if it never closed.
    static func lockedUntil(afterFailedAttempts failedAttempts: Int,
                            now: Date = .now) -> Date? {
        delay(afterFailedAttempts: failedAttempts).map { now.addingTimeInterval($0) }
    }

    /// Whether a stored lock is still in force.
    ///
    /// A lock in the past is not a lock. Written as a comparison against `now`
    /// rather than by clearing the field on a timer, because nothing runs while
    /// the app is closed and a timer that has to have fired is a lock that can
    /// be escaped by force-quitting.
    static func isLocked(until lockedUntil: Date?, now: Date = .now) -> Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > now
    }

    /// "Try again in 4 minutes." Deliberately rounded up and coarse: a
    /// to-the-second countdown invites watching it, and the number is a
    /// deterrent rather than a schedule.
    static func waitDescription(until lockedUntil: Date, now: Date = .now) -> String {
        let remaining = max(0, lockedUntil.timeIntervalSince(now))
        if remaining < 60 {
            let seconds = max(1, Int(remaining.rounded(.up)))
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let hours = Int((Double(minutes) / 60).rounded(.up))
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
}
