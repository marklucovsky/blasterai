// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PINThrottleTests.swift
//  claudeBlastTests
//
//  The escalation is the security property, so it is tested rather than eyeballed.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct PINThrottleTests {

    /// A parent fumbling their own PIN with a child on their lap is the common
    /// case by a wide margin. Punishing it is how a lock stops being used.
    @Test("The first few misses cost nothing")
    func earlyMissesAreFree() {
        for attempts in 1...PINThrottle.freeAttempts {
            #expect(PINThrottle.delay(afterFailedAttempts: attempts) == nil,
                    "attempt \(attempts) should not be throttled")
        }
    }

    @Test("Delays escalate rather than staying flat")
    func delaysEscalate() throws {
        let first = try #require(PINThrottle.delay(afterFailedAttempts: PINThrottle.freeAttempts + 1))
        let second = try #require(PINThrottle.delay(afterFailedAttempts: PINThrottle.freeAttempts + 2))
        let third = try #require(PINThrottle.delay(afterFailedAttempts: PINThrottle.freeAttempts + 3))

        #expect(first < second)
        #expect(second < third)
    }

    /// The property that matters: guessing gets arbitrarily expensive. A flat
    /// delay is a delay someone can budget for.
    @Test("Sustained guessing reaches a wall")
    func sustainedGuessingHitsACeiling() throws {
        let late = try #require(PINThrottle.delay(afterFailedAttempts: 20))
        #expect(late >= 60 * 60)
    }

    // MARK: - Lock state

    @Test("No lock means not locked")
    func nilIsNotLocked() {
        #expect(!PINThrottle.isLocked(until: nil))
    }

    /// A lock in the past is not a lock. Written as a comparison rather than by
    /// clearing the field on a timer, because nothing runs while the app is
    /// closed — and a lock that has to be cleared by a timer is one you escape
    /// by force-quitting.
    @Test("An expired lock has lapsed")
    func expiredLockHasLapsed() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(!PINThrottle.isLocked(until: now.addingTimeInterval(-1), now: now))
    }

    @Test("A future lock is in force")
    func futureLockHolds() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(PINThrottle.isLocked(until: now.addingTimeInterval(30), now: now))
    }

    /// Force-quitting must not clear it — the stored date is absolute, so a
    /// later "now" is the only thing that releases it.
    @Test("A lock survives a gap in which the app was not running")
    func lockSurvivesRelaunch() {
        let locked = Date(timeIntervalSince1970: 10_000).addingTimeInterval(15 * 60)
        let relaunch = Date(timeIntervalSince1970: 10_060) // a minute later
        #expect(PINThrottle.isLocked(until: locked, now: relaunch))
    }

    @Test("The lock is computed from the attempt count")
    func lockedUntilFollowsAttempts() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(PINThrottle.lockedUntil(afterFailedAttempts: 1, now: now) == nil)

        let locked = PINThrottle.lockedUntil(afterFailedAttempts: PINThrottle.freeAttempts + 1,
                                             now: now)
        #expect(locked == now.addingTimeInterval(60))
    }

    // MARK: - What the caregiver reads

    @Test("The wait is described in whole units, rounded up")
    func waitDescriptionRoundsUp() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(PINThrottle.waitDescription(until: now.addingTimeInterval(30), now: now)
                == "30 seconds")
        // 61s is "2 minutes", not "1" — rounding down would invite a retry that
        // is still refused.
        #expect(PINThrottle.waitDescription(until: now.addingTimeInterval(61), now: now)
                == "2 minutes")
        #expect(PINThrottle.waitDescription(until: now.addingTimeInterval(60 * 60), now: now)
                == "1 hour")
    }

    @Test("Singulars read as singulars")
    func singularsAreSingular() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(PINThrottle.waitDescription(until: now.addingTimeInterval(1), now: now)
                == "1 second")
        #expect(PINThrottle.waitDescription(until: now.addingTimeInterval(60), now: now)
                == "1 minute")
    }

    /// An elapsed lock still has to render something rather than "0 seconds" or
    /// a negative — the view can be a tick behind the clock.
    @Test("An elapsed wait does not render as zero or negative")
    func elapsedWaitStillReads() {
        let now = Date(timeIntervalSince1970: 10_000)
        let text = PINThrottle.waitDescription(until: now.addingTimeInterval(-5), now: now)
        #expect(text == "1 second")
    }
}
}
