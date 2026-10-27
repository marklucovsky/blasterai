// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageView.swift
//  claudeBlast
//
//  Unified tile image rendering. Replaces all inline UIImage(named:)/Image()
//  patterns with a single component that respects the active image set and
//  provides a composed placeholder for missing tiles in sparse sets.

import SwiftUI

struct TileImageView: View {
    let key: String
    let wordClass: String
    /// Draw the art straight on whatever is behind it. Off by default: shipped
    /// art is cut off its white ground (`TileCutout`), and on a list row or a
    /// tray chip in dark mode its black outlines would vanish into the dark.
    /// Every surface that was drawn on white stays on white; only a tile that
    /// paints its own colour behind the art turns this on.
    var drawsOnTint: Bool = false

    @Environment(TileImageResolver.self) private var resolver

    var body: some View {
        // Touch `revision` so adding/removing a photo override re-renders this
        // tile — NSCache mutations alone are not observable.
        let _ = resolver.revision
        if let uiImage = resolver.image(for: key) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .background(drawsOnTint ? Color.clear : Color.white)
        } else {
            // Composed placeholder for missing tiles in sparse sets.
            // Shows the word-class color with the first letter of the key,
            // plus a subtle indicator that this tile needs artwork.
            missingTilePlaceholder
        }
    }

    @ViewBuilder
    private var missingTilePlaceholder: some View {
        Rectangle()
            .fill(TileColorResolver.color(forWordClass: wordClass))
            .overlay {
                VStack(spacing: 4) {
                    Text(String(key.replacingOccurrences(of: "_", with: " ").prefix(1)).uppercased())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    // Small dot indicator that artwork is missing
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
    }
}

