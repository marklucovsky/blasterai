// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileColorSlot.swift
//  claudeBlast
//
//  Everything on a board that can carry a color of its own.
//

import SwiftUI

/// A thing a `TileColorMap` can assign a color to.
///
/// ## Why this exists rather than a twelfth `PartOfSpeech`
///
/// A palette is keyed by *what the color means*, and until now that was always a
/// part of speech, so `TileColorMap.overrides` was keyed by
/// `PartOfSpeech.rawValue`. Page links broke that: a folder is not a word and has
/// no part of speech, yet it very much carries a color — a deep royal blue that
/// some children cannot distinguish from the adjective blue beside it, and that
/// a caregiver may need to match against the WordPower device the child already
/// uses.
///
/// Adding `.wayfinding` to `PartOfSpeech` would have been the small change and
/// the wrong one. That enum is not a palette key: it drives
/// `resolvedPartOfSpeech`, `parts_of_speech.json`, word moderation and the
/// sentence prompt, and a member that is not a part of speech would have to be
/// special-cased out of every one of them. So the palette gets its own key type
/// and `PartOfSpeech` stays a fact about words.
///
/// ## The raw values are storage, and they are already in the field
///
/// `rawValue` for a part of speech is *exactly* `PartOfSpeech.rawValue`, not a
/// prefixed or wrapped form. Every palette a caregiver has already saved — in
/// `ChildProfile.colorMapData`, in the library on the system profile, in a
/// colorway file someone has been sent — is keyed that way, and this type has to
/// read them unchanged. `slotRawValuesDoNotCollide` in the tests holds the other
/// half of that bargain: no part of speech may ever be named `wayfinding` or
/// `chrome`.
enum TileColorSlot: Hashable, Identifiable, Sendable {

    /// A word, colored by the Modified Fitzgerald key.
    case partOfSpeech(PartOfSpeech)

    /// A tile that takes the board somewhere — a page link, a folder.
    case wayfinding

    /// Structural furniture with no word behind it, and the fallback for a tile
    /// whose part of speech will not resolve.
    ///
    /// Deliberately **not** offered in the palette editor. It is a degraded path
    /// rather than a category a caregiver means to style, and a row for "words we
    /// could not identify" invites someone to color it meaningfully — at which
    /// point the color says something true about our data and nothing about
    /// their child. It is a slot because it is one; it is not a choice.
    case chrome

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .partOfSpeech(let part): return part.rawValue
        case .wayfinding: return "wayfinding"
        case .chrome: return "chrome"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "wayfinding": self = .wayfinding
        case "chrome": self = .chrome
        default:
            guard let part = PartOfSpeech(rawValue: rawValue) else { return nil }
            self = .partOfSpeech(part)
        }
    }

    /// What the palette editor lists, in the order a therapist scans: the word
    /// colors they already know, then the one that is not a word.
    ///
    /// Page links sit last and alone because the question it answers is a
    /// different question — not "what do describing words look like" but "can
    /// this child tell a folder from the words around it".
    static let display: [TileColorSlot] =
        PartOfSpeech.display.map(TileColorSlot.partOfSpeech) + [.wayfinding]

    /// The label shown beside the swatch.
    var label: String {
        switch self {
        case .partOfSpeech(let part): return part.label
        case .wayfinding: return "Page Links"
        case .chrome: return "Unrecognized"
        }
    }
}
