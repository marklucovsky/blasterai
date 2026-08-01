// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileResolverTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ChildProfileResolverTests {

    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func unconfigured_returnsFallbacks() {
        let resolver = ChildProfileResolver()
        #expect(resolver.active == nil)
        #expect(resolver.ageGrade == ChildProfileResolver.fallbackAgeGrade)
        #expect(resolver.voiceIdentifier == "")
        #expect(resolver.ttsRate == ChildProfileResolver.fallbackTTSRate)
        #expect(resolver.ttsVolume == ChildProfileResolver.fallbackTTSVolume)
        #expect(resolver.maxSelectedTiles == ChildProfileResolver.fallbackMaxTiles)
        #expect(resolver.activeChildID == nil)
    }

    @Test func emptyStore_resolvesToNil() throws {
        let container = try makeContainer()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: container.mainContext)
        #expect(resolver.active == nil)
        #expect(resolver.ageGrade == ChildProfileResolver.fallbackAgeGrade)
    }

    @Test func singleActive_resolvesAndExposesGetters() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let bday = ChildProfile.synthesizeBirthday(age: 7, asOf: date(2026, 6, 4))
        let aubrey = ChildProfile(
            displayName: "Aubrey",
            birthday: bday,
            voiceIdentifier: "com.apple.voice.Samantha",
            maxSelectedTiles: 5,
            isActive: true
        )
        aubrey.ttsRate = 0.45
        aubrey.ttsVolume = 0.8
        ctx.insert(aubrey)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)

        #expect(resolver.active?.displayName == "Aubrey")
        #expect(resolver.ageGrade == 2) // age 7 → 7-5=2 grade
        #expect(resolver.voiceIdentifier == "com.apple.voice.Samantha")
        #expect(resolver.maxSelectedTiles == 5)
        #expect(resolver.ttsRate == 0.45)
        #expect(resolver.ttsVolume == 0.8)
        #expect(resolver.activeChildID == aubrey.id)
    }

    @Test func setActive_deactivatesPriorActiveProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let a = ChildProfile(displayName: "A", birthday: date(2020, 1, 1), isActive: true)
        let b = ChildProfile(displayName: "B", birthday: date(2021, 1, 1), isActive: false)
        ctx.insert(a)
        ctx.insert(b)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(resolver.active?.displayName == "A")

        resolver.setActive(id: b.id)

        #expect(resolver.active?.displayName == "B")
        #expect(a.isActive == false)
        #expect(b.isActive == true)
    }

    @Test func multipleActive_resolverPicksTiebreakerWinner() throws {
        // Simulate a CloudKit race: two profiles both marked active. The
        // resolver should pick the most-recently-modified, not crash or
        // return both.
        let container = try makeContainer()
        let ctx = container.mainContext

        let older = ChildProfile(displayName: "Older", birthday: date(2020, 1, 1), isActive: true)
        older.modifiedAt = date(2026, 1, 1)
        let newer = ChildProfile(displayName: "Newer", birthday: date(2020, 1, 1), isActive: true)
        newer.modifiedAt = date(2026, 6, 1)
        ctx.insert(older)
        ctx.insert(newer)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)

        #expect(resolver.active?.displayName == "Newer")
    }

    @Test func noRealActive_fallsBackToSandbox() throws {
        // When no real profile is active, the resolver returns the
        // Sandbox profile (isSystem == true). Engine never sees nil.
        let container = try makeContainer()
        let ctx = container.mainContext

        let sandbox = ChildProfile(
            displayName: "Sandbox",
            birthday: date(2018, 1, 1),
            isActive: false, // intentionally false; resolver still picks it
            isSystem: true
        )
        ctx.insert(sandbox)
        let inactive = ChildProfile(
            displayName: "Aubrey",
            birthday: date(2020, 1, 1),
            isActive: false
        )
        ctx.insert(inactive)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)

        #expect(resolver.active?.displayName == "Sandbox")
        #expect(resolver.active?.isSystem == true)
    }

    @Test func realActive_preemptsSandbox() throws {
        // A real active profile takes precedence even when a Sandbox
        // exists in the store.
        let container = try makeContainer()
        let ctx = container.mainContext

        let sandbox = ChildProfile(
            displayName: "Sandbox",
            birthday: date(2018, 1, 1),
            isActive: true,
            isSystem: true
        )
        ctx.insert(sandbox)
        let aubrey = ChildProfile(
            displayName: "Aubrey",
            birthday: date(2020, 1, 1),
            isActive: true
        )
        ctx.insert(aubrey)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)

        #expect(resolver.active?.displayName == "Aubrey")
        #expect(resolver.active?.isSystem == false)
    }

    @Test func refresh_picksUpExternalChanges() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let a = ChildProfile(displayName: "A", birthday: date(2020, 1, 1), isActive: true)
        ctx.insert(a)

        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        #expect(resolver.active?.displayName == "A")

        // External mutation — onboarding completes and creates a new profile,
        // overriding the legacy seed.
        a.isActive = false
        let b = ChildProfile(displayName: "B", birthday: date(2021, 1, 1), isActive: true)
        ctx.insert(b)
        try ctx.save()

        resolver.refresh()
        #expect(resolver.active?.displayName == "B")
    }
}
}
