// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileLook.swift
//  claudeBlast
//
//  The square tile: one shape, three ways of holding a picture.
//

import SwiftUI

/// Which tile the board draws.
///
/// `.square` is the refresh (2026-10-26): a square tile in a light tint of its
/// Fitzgerald colour, 2pt apart, the word in a band at the bottom of the square
/// instead of under it. `.classic` is the card-and-caption tile it replaced.
///
/// Square is the only tile from 1.0 (Mark 2026-10-30): the Tile Look setting
/// is gone and a stored "classic" is ignored. `.classic` stays as code until
/// its drawing paths are removed, so nothing reaches it from the UI.
enum TileLook: String, CaseIterable, Identifiable {
    case classic, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .square:  return "Square"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> TileLook {
        .square
    }
}

/// How a square tile holds its picture. Each image set declares one
/// (`ImageSetID.tileLayout`), because what works depends on the art.
enum TileLayout: Equatable {
    /// The art straight on the tint, its white cut away (`TileCutout`). Only
    /// for art with black outlines, which is what lets the cut stop: Classic
    /// and its tones.
    case cutOut
    /// The art on a white card floating a point above the tint, a soft shadow
    /// and no frame. Playful 3D, whose clay whites cannot be cut; and the
    /// fallback for any picture without a clean cut — a photo, a variant made
    /// before cutting, a Classic tile left uncut.
    case card
    /// High Contrast's black plate in a white frame, on the full colour: its
    /// figures are white, and a tint would wash them out.
    case plate

    /// The tint a cut-out or a card sits on, as the share mixed toward white.
    /// 55%: Mark's pick from the mocks, light enough for black outlines to
    /// read, strong enough for the colour to scan across a room.
    static let tintMix: CGFloat = 0.55

    /// The space between tiles, both ways.
    static let gap: CGFloat = 2
    static let cornerRadius: CGFloat = 6
    /// The picture's margin inside the tile, above and at the sides.
    static let margin: CGFloat = 4
}

extension EnvironmentValues {
    /// A square-look tile's width over its height: 1 everywhere but a phone on
    /// its side (`GridLayoutSpec.tileHeight`).
    @Entry var tileAspect: CGFloat = 1
}
