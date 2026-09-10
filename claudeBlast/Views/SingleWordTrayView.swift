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

    @ScaledMetric(relativeTo: .caption) private var promptSize: CGFloat = 13

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
    ///
    /// **84 → 88 when the chip took the board's card treatment.** The arithmetic:
    /// a 56pt square picture area, then a label *band* of
    /// `labelBandPadding + ~13pt of 11pt text + labelBandPadding` = 19pt, where
    /// the old caption cost `2pt of stack spacing + 13pt` = 15pt. Plus the
    /// strip's own 6pt above and below: 56 + 19 + 12 = 87, rounded to 88.
    /// The picture did not shrink; only the label's ground grew.
    static let stripHeight: CGFloat = 88

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
                            .font(.system(size: promptSize))
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

/// One spoken word, drawn as the board tile it came from: the word's color as
/// the card, the picture on a white plate inside it, the word on the color
/// underneath. Tapping removes it from the strip.
///
/// It used to be a 0.14-opacity tint behind the picture with a hairline border
/// and the word in grey beneath, on the tray's own material. That was the
/// board's previous treatment, and once a tile *is* its color a tinted chip
/// stops reading as the same object the child just pressed — which is the one
/// thing this strip exists to say.
private struct WordChip: View {
    /// The strip is a fixed-height band, so the word shrinks to fit rather
    /// than clipping — see the `minimumScaleFactor` below.
    @ScaledMetric(relativeTo: .caption2) private var wordSize: CGFloat = 11

    let tile: TileSelection
    let onTap: () -> Void

    /// The card's square picture area — unchanged, so the strip did not have to
    /// give up picture size to gain the band.
    private let size: CGFloat = 56
    /// How far the white plate sits inside the colored card. 4 of 56 is the same
    /// proportion `TileView` uses at board sizes (7 of ~92).
    private let plateInset: CGFloat = 4

    private var accent: Color { TileColorResolver.color(for: tile) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .padding(2)
                    .frame(width: size - plateInset * 2, height: size - plateInset * 2)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(plateInset)

                Text(tile.value)
                    .font(.system(size: wordSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(TileColorResolver.label(on: accent))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
                    .padding(.vertical, GridLayoutCalculator.labelBandPadding)
            }
            .frame(width: size)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tile.value)")
    }
}

// MARK: - End buttons

private struct ClearButton: View {
    @ScaledMetric(relativeTo: .caption) private var clearGlyphSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var clearLabelSize: CGFloat = 10

    /// Matches `SingleWordTrayView.stripHeight` so the row reads as one band.
    var height: CGFloat = SingleWordTrayView.stripHeight
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: clearGlyphSize, weight: .bold))
                Text("Clear")
                    .font(.system(size: clearLabelSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
