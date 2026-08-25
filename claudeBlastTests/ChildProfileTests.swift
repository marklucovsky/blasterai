// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ChildProfileTests {

    private func makeContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Active resolution (tiebreaker for CloudKit races)

    @Test func resolveActive_noneActive_returnsNil() throws {
        let a = ChildProfile(displayName: "A")
        let b = ChildProfile(displayName: "B")
        #expect(ChildProfile.resolveActive(from: [a, b]) == nil)
    }

    @Test func resolveActive_oneActive_returnsIt() throws {
        let a = ChildProfile(displayName: "A", isActive: false)
        let b = ChildProfile(displayName: "B", isActive: true)
        #expect(ChildProfile.resolveActive(from: [a, b])?.displayName == "B")
    }

    @Test func resolveActive_multipleActive_picksMostRecentlyModified() throws {
        let older = ChildProfile(displayName: "Older", isActive: true)
        older.modifiedAt = date(2026, 1, 1)
        let newer = ChildProfile(displayName: "Newer", isActive: true)
        newer.modifiedAt = date(2026, 6, 1)
        let picked = ChildProfile.resolveActive(from: [older, newer])
        #expect(picked?.displayName == "Newer")
    }

    @Test func resolveActive_tiedModifiedAt_picksLowestId() throws {
        // Deterministic tiebreaker — same modifiedAt → lowest id wins.
        let stamp = date(2026, 6, 1)
        let a = ChildProfile(displayName: "A", isActive: true)
        a.id = "aaaa"
        a.modifiedAt = stamp
        let b = ChildProfile(displayName: "B", isActive: true)
        b.id = "zzzz"
        b.modifiedAt = stamp
        let picked = ChildProfile.resolveActive(from: [b, a])
        #expect(picked?.id == "aaaa")
    }

    // MARK: - SwiftData round-trip

    @Test func childProfileRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let profile = ChildProfile(
            displayName: "Aubrey",
            brownsStage: .fourPlus,
            voiceIdentifier: "com.apple.voice.compact.en-US.Samantha",
            maxSelectedTiles: 5,
            defaultSceneKey: "core_first",
            notes: "Loves dinosaurs",
            isActive: true
        )
        ctx.insert(profile)

        let fetched = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Aubrey")
        #expect(fetched[0].brownsStage == .fourPlus)
        #expect(fetched[0].maxSelectedTiles == 5)
        #expect(fetched[0].isActive == true)
    }

    // MARK: - Pre-promotion insurance fields

    /// `languageRaw` and `brownsStageRaw` exist, carry their intended defaults,
    /// and survive a save/fetch cycle.
    ///
    /// This is the *whole* assertion the insurance PR is buying, and nothing
    /// else covers it: `SchemaVersionTests` guards which **models** are in the
    /// synced partition, not which **fields** are on them. The synced schema
    /// becomes additive-only at promotion, so a field that isn't here before
    /// S6 Phase 4 cannot be added to Production later without a new field plus
    /// a backfill of every tester's records.
    ///
    /// Round-tripping matters as much as existence. Per the no-optionals rule
    /// on `BlasterSchemaV1`, a property must be written on every save for its
    /// CloudKit field to materialize at all — an unwritten field never appears
    /// in the Development schema and therefore never exists in Production.
    @Test func insuranceFieldsDefaultAndRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let profile = ChildProfile(displayName: "Aubrey")
        // Empty ⇒ unspecified ⇒ English.
        #expect(profile.languageRaw == "")
        // A real stage, not an "unset" sentinel: every profile that will ever
        // exist is created after the 3E selector does, so there is no
        // pre-existing state to distinguish a default from a choice.
        #expect(profile.brownsStageRaw == "I")

        ctx.insert(profile)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(fetched.count == 1)
        #expect(fetched[0].languageRaw == "")
        #expect(fetched[0].brownsStageRaw == "I")
    }

    /// Both fields accept and persist a non-default value, which is what proves
    /// they are writable stored properties rather than constants.
    @Test func insuranceFieldsPersistAssignedValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let profile = ChildProfile(displayName: "Aubrey")
        profile.languageRaw = "km"
        profile.brownsStageRaw = "IV+"
        ctx.insert(profile)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(fetched[0].languageRaw == "km")
        #expect(fetched[0].brownsStageRaw == "IV+")
    }

    // MARK: - DeviceProfile + Store

    @Test func deviceProfileStore_ensureCreatesPlaceholder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let created = DeviceProfileStore.ensure(context: ctx)
        #expect(created.role == .caregiver)
        #expect(created.onboardingCompleted == false)

        let fetched = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(fetched.count == 1)
    }

    @Test func deviceProfileStore_ensureReturnsSingleton() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let first = DeviceProfileStore.ensure(context: ctx)
        first.role = .caregiver
        first.authorName = "Dr. Yalcin"

        let second = DeviceProfileStore.ensure(context: ctx)
        #expect(second.role == .caregiver)
        #expect(second.authorName == "Dr. Yalcin")

        let count = try ctx.fetch(FetchDescriptor<DeviceProfile>()).count
        #expect(count == 1)
    }

    @Test func deviceProfileStore_ensureDedupsExtras() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Simulate two devices both seeding a row (would happen on a CloudKit
        // race even though we explicitly disable sync — defensive).
        let early = DeviceProfile(role: .caregiver)
        early.authorName = "Early"
        early.createdAt = date(2026, 1, 1)
        ctx.insert(early)
        let late = DeviceProfile(role: .caregiver)
        late.authorName = "Late"
        late.createdAt = date(2026, 6, 1)
        ctx.insert(late)

        let kept = DeviceProfileStore.ensure(context: ctx)
        #expect(kept.authorName == "Early")
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
    }

    @Test func deviceRoleSummariesPresent() throws {
        // Smoke test: every case has a non-empty user-facing summary so the
        // onboarding role picker can render something.
        for role in DeviceRole.allCases {
            #expect(!role.displayName.isEmpty)
            #expect(!role.summary.isEmpty)
        }
    }
}
}
