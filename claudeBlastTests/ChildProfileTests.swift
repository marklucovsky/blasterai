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

    // MARK: - Birthday synthesis

    @Test func synthesizeBirthday_wrapMonth_preservesAge() throws {
        // Today 2026-06-04, age 5 → synth birthday 2021-02-04 (Mark's worked
        // example). On 2026-06-04 the child should still read as age 5.
        let now = date(2026, 6, 4)
        let bday = ChildProfile.synthesizeBirthday(age: 5, asOf: now)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: bday)
        #expect(comps.year == 2021)
        #expect(comps.month == 2)
        #expect(comps.day == 4)
        #expect(ChildProfile.age(from: bday, asOf: now) == 5)
    }

    @Test func synthesizeBirthday_noWrap_preservesAge() throws {
        // Today 2026-03-04, age 5 → synth birthday 2020-11-04. The +8 month
        // offset doesn't wrap the year, but the birthYear formula still has
        // to back off by an extra year to keep the kid actually age 5 today.
        let now = date(2026, 3, 4)
        let bday = ChildProfile.synthesizeBirthday(age: 5, asOf: now)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: bday)
        #expect(comps.year == 2020)
        #expect(comps.month == 11)
        #expect(comps.day == 4)
        #expect(ChildProfile.age(from: bday, asOf: now) == 5)
    }

    @Test func synthesizeBirthday_ageTicksOverAtSyntheticBirthday() throws {
        // The whole point of the synth: ~8 months from now, the displayed
        // age increments without any admin action.
        let now = date(2026, 6, 4)
        let bday = ChildProfile.synthesizeBirthday(age: 5, asOf: now)
        // Same age on the synthesis date.
        #expect(ChildProfile.age(from: bday, asOf: now) == 5)
        // Still 5 the day before the synthetic birthday.
        let dayBefore = date(2027, 2, 3)
        #expect(ChildProfile.age(from: bday, asOf: dayBefore) == 5)
        // 6 on the synthetic birthday.
        let onBday = date(2027, 2, 4)
        #expect(ChildProfile.age(from: bday, asOf: onBday) == 6)
    }

    @Test func synthesizeBirthday_clampsLeapDay() throws {
        // Today 2024-06-29 (leap year). +8 months would land on Feb 29 2025
        // which doesn't exist. Calendar pre-clamps to Feb 28, so the synth
        // should produce Feb 28.
        let now = date(2024, 6, 29)
        let bday = ChildProfile.synthesizeBirthday(age: 5, asOf: now)
        let comps = Calendar.current.dateComponents([.month, .day], from: bday)
        #expect(comps.month == 2)
        #expect(comps.day == 28)
    }

    // MARK: - Age grade derivation

    @Test func ageGrade_followsAge() throws {
        // 6yo → 1st grade. 7yo → 2nd. Clamp at 1 below, 12 above.
        let now = date(2026, 6, 4)
        let bday6 = ChildProfile.synthesizeBirthday(age: 6, asOf: now)
        let profile6 = ChildProfile(displayName: "A", birthday: bday6)
        #expect(profile6.age == 6)
        #expect(profile6.ageGrade == 1)

        let bday7 = ChildProfile.synthesizeBirthday(age: 7, asOf: now)
        let profile7 = ChildProfile(displayName: "B", birthday: bday7)
        #expect(profile7.ageGrade == 2)

        let bday3 = ChildProfile.synthesizeBirthday(age: 3, asOf: now)
        let profile3 = ChildProfile(displayName: "C", birthday: bday3)
        #expect(profile3.ageGrade == 1) // floor

        let bday20 = ChildProfile.synthesizeBirthday(age: 20, asOf: now)
        let profile20 = ChildProfile(displayName: "D", birthday: bday20)
        #expect(profile20.ageGrade == 12) // ceiling
    }

    // MARK: - Active resolution (tiebreaker for CloudKit races)

    @Test func resolveActive_noneActive_returnsNil() throws {
        let a = ChildProfile(displayName: "A", birthday: date(2020, 1, 1))
        let b = ChildProfile(displayName: "B", birthday: date(2020, 1, 1))
        #expect(ChildProfile.resolveActive(from: [a, b]) == nil)
    }

    @Test func resolveActive_oneActive_returnsIt() throws {
        let a = ChildProfile(displayName: "A", birthday: date(2020, 1, 1), isActive: false)
        let b = ChildProfile(displayName: "B", birthday: date(2020, 1, 1), isActive: true)
        #expect(ChildProfile.resolveActive(from: [a, b])?.displayName == "B")
    }

    @Test func resolveActive_multipleActive_picksMostRecentlyModified() throws {
        let older = ChildProfile(displayName: "Older", birthday: date(2020, 1, 1), isActive: true)
        older.modifiedAt = date(2026, 1, 1)
        let newer = ChildProfile(displayName: "Newer", birthday: date(2020, 1, 1), isActive: true)
        newer.modifiedAt = date(2026, 6, 1)
        let picked = ChildProfile.resolveActive(from: [older, newer])
        #expect(picked?.displayName == "Newer")
    }

    @Test func resolveActive_tiedModifiedAt_picksLowestId() throws {
        // Deterministic tiebreaker — same modifiedAt → lowest id wins.
        let stamp = date(2026, 6, 1)
        let a = ChildProfile(displayName: "A", birthday: date(2020, 1, 1), isActive: true)
        a.id = "aaaa"
        a.modifiedAt = stamp
        let b = ChildProfile(displayName: "B", birthday: date(2020, 1, 1), isActive: true)
        b.id = "zzzz"
        b.modifiedAt = stamp
        let picked = ChildProfile.resolveActive(from: [b, a])
        #expect(picked?.id == "aaaa")
    }

    // MARK: - SwiftData round-trip

    @Test func childProfileRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let bday = ChildProfile.synthesizeBirthday(age: 5, asOf: date(2026, 6, 4))
        let profile = ChildProfile(
            displayName: "Aubrey",
            birthday: bday,
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
        #expect(fetched[0].age == 5)
        #expect(fetched[0].maxSelectedTiles == 5)
        #expect(fetched[0].isActive == true)
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
