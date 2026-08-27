// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SingleWordTrayView.swift
//  claudeBlast
//
//  The tray for single-word (classic AAC) mode. Instead of building a sentence,
//  it shows a running FIFO strip of the words the child has tapped — oldest on
//  the left, newest auto-scrolled into view on the right, older words rolling
//  off as new ones arrive (the engine caps the buffer). Words speak on grid tap;
//  this strip is the visible record. Tap a word to remove it; the ✕ clears all.
//
//  One adaptive view for iPhone and iPad — the strip just gets more room on the
//  larger screen.

import SwiftUI

struct SingleWordTrayView: View {
    @Environment(SentenceEngine.self) private var engine

    /// Remove one word from the strip (its chip was tapped).
    let onRemove: (Int) -> Void
    /// Clear the whole strip.
    let onClear: () -> Void
    /// Return to the active scene's home page.

    private var strip: [TileSelection] { engine.spokenStrip }

    /// Fixed strip height — sized to fit a word chip (image + label) so the
    /// tray's height is identical whether the strip is empty or full.
    ///
    /// **Home and Clear share it.** They were 64pt against an 84pt strip, which
    /// left them visibly short of the tray they sit in and gave two frequently
    /// used controls a smaller target than they needed. Deriving both from one
    /// constant is what stops them drifting apart again.
    static let stripHeight: CGFloat = 84

    var body: some View {
        HStack(spacing: 8) {
            stripCard
                .frame(maxWidth: .infinity)

            ClearButton(isEnabled: !strip.isEmpty, action: onClear)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: strip.count)
    }

    // MARK: - Strip

    private var stripCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if strip.isEmpty {
                        Text("Tap tiles to speak words")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(Array(strip.enumerated()), id: \.offset) { idx, tile in
                            WordChip(tile: tile) { onRemove(idx) }
                                .overlay(alignment: .topTrailing) {
                                    if idx == strip.count - 1 && engine.repetitionCount > 0 {
                                        ReplayBadge(count: engine.repetitionCount, compact: true)
                                            .offset(x: 6, y: -4)
                                    }
                                }
                                .id(idx)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                // Fixed height so the tray doesn't grow when the first word
                // lands (empty-hint and filled states must be the same height).
                .frame(height: Self.stripHeight)
            }
            .frame(height: Self.stripHeight)
            .onChange(of: strip.count) { _, _ in
                // Keep the newest word in view on the right.
                if let last = strip.indices.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .trailing)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Word chip

/// One spoken word: image over its label, tinted by word class. Tapping removes
/// it from the strip.
private struct WordChip: View {
    let tile: TileSelection
    let onTap: () -> Void

    private let size: CGFloat = 56

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    wordClassColor(tile.wordClass).opacity(0.14)
                    TileImageView(key: tile.key, wordClass: tile.wordClass)
                        .padding(3)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(wordClassColor(tile.wordClass).opacity(0.45), lineWidth: 1)
                )

                Text(tile.value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: size + 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tile.value)")
    }
}

// MARK: - End buttons

private struct ClearButton: View {
    /// Matches `SingleWordTrayView.stripHeight` so the row reads as one band.
    var height: CGFloat = SingleWordTrayView.stripHeight
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                Text("Clear").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? .red : .secondary)
            .frame(width: 60, height: height)
            .background(TrayCardBackground(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Clear all words")
    }
}
