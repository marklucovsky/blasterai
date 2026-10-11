// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LoggedNavigation.swift
//  claudeBlast
//

import Foundation
import SwiftData

/// One press of a tile that opens a page: a folder, the keyboard, a word that
/// speaks *and* navigates, or the Home cell.
///
/// ## Why its own record, and not a field on `LoggedUtterance`
///
/// An utterance is written when a sentence is finished. A child who is lost —
/// Home, Actions, Home, Groups, Home — never finishes one, so a trail stored on
/// the utterance would be empty in exactly the case it exists to show. The
/// navigation has to stand on its own.
///
/// ## Why synced
///
/// Coverage and the activity log read `LoggedUtterance`, which syncs. A folder
/// press kept on one device while word presses arrive from every device would
/// make a page's coverage depend on which iPad you open the report on.
///
/// ## Schema rules
///
/// Added to `BlasterSchemaV1` after promotion. Synced, so additive-only once deployed to
/// Production — every property has a non-optional default (see
/// `BlasterSchemaV1` for why optionals are unsafe here). **Deploy the schema to
/// Production before a build that writes this ships**, or Production rejects
/// the records.
@Model
final class LoggedNavigation {
    var id: String = UUID().uuidString
    /// The page the press was made on — the page whose coverage it counts on.
    var fromPageKey: String = ""
    /// The page it opened. With `fromPageKey`, the trail between pages.
    var toPageKey: String = ""
    /// The tile pressed: usually the page key itself for a folder, `home` for
    /// the Home cell. Coverage matches it against the page's cells.
    var linkKey: String = ""
    var createdAt: Date = Date.now
    /// `BlasterScene.sceneID`. **Empty** when no scene was active.
    var sceneID: String = ""
    /// `ChildProfile.id`. **Empty means unknown**, as on `LoggedUtterance`.
    var childID: String = ""

    init(fromPageKey: String, toPageKey: String, linkKey: String,
         sceneID: String = "", childID: String = "", createdAt: Date = .now) {
        self.fromPageKey = fromPageKey
        self.toPageKey = toPageKey
        self.linkKey = linkKey
        self.sceneID = sceneID
        self.childID = childID
        self.createdAt = createdAt
    }
}
