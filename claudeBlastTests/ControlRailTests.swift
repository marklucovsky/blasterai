// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ControlRailTests.swift
//  claudeBlastTests
//
//  Which rail a device shows, and what is on it.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct ControlRailTests {

    /// A patient device always gets the child's rail; a caregiver device gets
    /// the caregiver's until Child mode locks it.
    @Test func theRoleAndTheLockChooseTheRail() {
        #expect(RailProfile.resolve(role: .patient, childLock: false) == .child)
        #expect(RailProfile.resolve(role: .patient, childLock: true) == .child)
        #expect(RailProfile.resolve(role: .caregiver, childLock: false) == .caregiver)
        #expect(RailProfile.resolve(role: .caregiver, childLock: true) == .child)
        // No profile yet is a child's device: nothing on its rail changes the board.
        #expect(RailProfile.resolve(role: nil, childLock: false) == .child)
    }

    /// Home first and Keyboard last on both rails: the two places a child
    /// learns, wherever the device came from.
    @Test func homeAndKeyboardKeepTheirPlaces() {
        for profile in [RailProfile.child, .caregiver] {
            let slots = profile.slots
            #expect(slots.count == 6)
            #expect(slots.first == .one(.home), "\(profile)")
            #expect(slots.last == .one(.keyboard), "\(profile)")
        }
    }

    /// The child's rail changes nothing about the board: no search, no edit,
    /// no level, no way out of Child mode.
    @Test func theChildsRailHoldsNoCaregiverTools() {
        let items = Set(RailProfile.child.slots.flatMap(\.items))
        #expect(items == [.home, .back, .topics, .keyboard])
    }

    /// Mark's layout, top to bottom: Levels over Topics, Search over Edit.
    @Test func theCaregiversRailIsTheChosenOne() {
        #expect(RailProfile.caregiver.slots == [
            .one(.home), .one(.back), .pair(.levels, .topics), .pair(.search, .edit),
            .one(.childMode), .one(.keyboard),
        ])
    }

    /// Until a therapist settles which stage drops the tray's pictures, the
    /// stage only sets the default: a caregiver can pick either way.
    @Test func trayPicturesFollowTheStageUntilChosen() {
        let suite = "ControlRailTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        #expect(TrayPictures.current(d) == .auto)
        d.set(TrayPictures.words.rawValue, forKey: AppSettingsKey.trayPictures)
        #expect(TrayPictures.current(d) == .words)
        d.set("nonsense", forKey: AppSettingsKey.trayPictures)
        #expect(TrayPictures.current(d) == .auto)
    }
}
}
