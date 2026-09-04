// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CaregiverMenuCoordinator.swift
//  claudeBlast
//
//  Bridges the caregiver menu (opened by long-pressing Home in the tray, deep
//  in the view tree) up to ContentView, which owns the Admin presentation. The
//  tray sets `requested`; ContentView observes it and drives its
//  fullScreenCover. Replaces the old hidden triple-tap → hamburger → menu entry
//  chain.

import Foundation
import Observation

@MainActor
@Observable
final class CaregiverMenuCoordinator {
    /// A gated/admin destination the caregiver requested from the menu.
    ///
    /// One case, and it stays an enum rather than collapsing to a Bool because
    /// the menu is the natural place for a second gated destination to appear.
    /// `tileScript` was that second case until it was removed: presented from
    /// here the runner trapped on a missing `TileScriptRunner`, and Admin ->
    /// Device -> TileScript is the door that works.
    enum Destination: Equatable {
        case admin       // presented behind AdminGate (Face ID / PIN)
    }

    /// Set by the caregiver menu; observed and cleared by ContentView.
    var requested: Destination?
}
