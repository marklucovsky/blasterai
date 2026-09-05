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

    @Environment(TileImageResolver.self) private var resolver

    var body: some View {
        // Touch `revision` so adding/removing a photo override re-renders this
        // tile — NSCache mutations alone are not observable.
        let _ = resolver.revision
        if let uiImage = resolver.image(for: key) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
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

