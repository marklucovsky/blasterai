// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LinkColorMode.swift
//  claudeBlast
//
//  One switch over every folder on the board.
//

import Foundation

/// How page links take their color, for one child, across every scene.
///
/// ## Why a global switch exists at all
///
/// Once folders are colored by what is behind them, a caregiver who decides
/// folders must instead stand out *as folders* would otherwise have to edit each
/// link by hand — twelve on our own home page, and more on a scene they were
/// sent. Mark: *"scenes with auto ... are going to need a full edit if that
/// caregiver wants to make links much more visible to their patients."*
///
/// ## Why it never writes to a tile
///
/// This decides which color is *looked up*, never what a link *stores*. Turning
/// it on and off restores exactly the board that was there before, and a scene
/// shared onward still carries the colors its author chose. A mode that rewrote
/// tiles would be a destructive edit wearing the costume of a preference.
///
/// ## Why there is no "always by destination"
///
/// It was drafted and cut. Telling a hand-picked color apart from an
/// auto-resolved one means storing both — the slot the resolver computed *and*
/// the slot someone chose instead — because a manual edit overwrites the
/// automatic answer and there is nothing left to fall back to. Recomputing at
/// render was the alternative and is the thing `TileEntry.linkColor` exists to
/// prevent. Two stored colors per link is a real cost for a case nobody has
/// asked for yet.
///
/// **Adding it later is free**, which is the whole reason this is a
/// string-backed enum rather than a Bool: a new case is a new raw value, not a
/// migration, and a client that has not seen it falls back to `perTile` through
/// the accessor on `ChildProfile`. That matters because this ships after
/// CloudKit promotion, when the property itself is permanent.
enum LinkColorMode: String, CaseIterable, Identifiable, Sendable {

    /// Each link uses the slot it carries. The default, and what a scene author
    /// meant.
    case perTile

    /// Every link draws as wayfinding, however it is stored — folders read as
    /// navigation first and vocabulary second.
    case alwaysWayfinding

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perTile: return "As Each Link Is Set"
        case .alwaysWayfinding: return "Always the Link Color"
        }
    }

    var detail: String {
        switch self {
        case .perTile:
            return "Folders look like the words behind them, unless someone changed one."
        case .alwaysWayfinding:
            return "Every folder uses the Page Links color, so links stand out from words."
        }
    }
}
