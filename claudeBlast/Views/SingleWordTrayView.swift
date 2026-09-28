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

            // Speak the whole line.
            //
            // The strip had no Play at all: every tap already spoke its own
            // word, so there was never a collection to hear. At Stage IV+ the
            // strip *is* the utterance being built, and a child who has put
            // five words in a row should be able to say the row — whether or
            // not it parses. Mark: *"in word mode, we TTS the collection of
            // words which may or may not make sense."*
            if !engine.trayShowsPictures {
                StripPlayButton(isEnabled: !strip.isEmpty) {
                    engine.speakStrip()
                }
            }

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
                // Tiles get tile spacing; words get word spacing.
                HStack(spacing: engine.trayShowsPictures ? 6 : 5) {
                    if strip.isEmpty {
                        Text("Tap tiles to speak words")
                            .font(.system(size: promptSize))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(Array(strip.enumerated()), id: \.offset) { idx, tile in
                            WordChip(tile: tile,
                                     showsPicture: engine.trayShowsPictures) {
                                onRemove(idx)
                            }
                                .overlay(alignment: .topTrailing) {
                                    if idx == strip.count - 1 && engine.repetitionCount > 0 {
                                        ReplayBadge(count: engine.repetitionCount, compact: true)
                                            .offset(x: 6, y: -4)
                                    }
                                }
                                .id(idx)
                        }

                        // At the end of the words, where a caret would be.
                        if !engine.trayShowsPictures {
                            BackspaceButton(isEnabled: !strip.isEmpty, compact: true) {
                                engine.removeStripWord(at: strip.count - 1)
                            }
                            .padding(.leading, 2)
                            .id("backspace")
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
    /// False at Stage IV+, where the strip is a line of words rather than a row
    /// of tiles — see `BrownsStage.showsPicturesInTray`.
    ///
    /// **This surface was missed the first time**, and the symptom was worth
    /// recording: switching a Stage IV+ child to single-word mode in Admin sent
    /// the tray back to pictures. The two trays are separate views over two
    /// separate pieces of engine state — `activeGroup` here, `spokenStrip`
    /// there — so honouring the stage in one of them honours it in neither
    /// mode the child might actually be in.
    var showsPicture: Bool = true
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
            if showsPicture { card } else { word }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tile.value)")
    }

    /// The word alone, sized to itself — the strip as a line of text. Matches
    /// `ActiveTileCard.word`; see there for why the colour goes with the card.
    private var word: some View {
        Text(tile.value)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .frame(height: size)
            .contentShape(Rectangle())
    }

    private var card: some View {
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
}

// MARK: - End buttons

/// Speak the whole strip.
///
/// Deliberately the twin of `ClearButton` rather than of the sentence tray's
/// `PrimaryPlayButton`: it stands in the same band, beside Clear, and the two
/// read as one pair of controls over the line of words.
///
/// Only shown where the strip is text. With pictures, every tap has already
/// spoken its own word and there is no collection anyone asked to hear.
private struct StripPlayButton: View {
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10

    var height: CGFloat = SingleWordTrayView.stripHeight
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: glyphSize, weight: .bold))
                Text("Play")
                    .font(.system(size: labelSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
            .frame(width: 60, height: height)
            .background(TrayCardBackground(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Speak all the words")
    }
}

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
