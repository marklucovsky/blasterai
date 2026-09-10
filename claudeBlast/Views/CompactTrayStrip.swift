// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CompactTrayStrip.swift
//  claudeBlast
//
//  iPhone-class replacement for SentenceTrayView. The tray has two rows:
//
//    Top row (the active group):
//      • ActiveCard — chips + inline speech bubble (when a sentence
//        has been generated). Tap the bubble to expand into the
//        full-text GlassSentencePopover.
//      • Play / Done — two stacked glass cards on the right driving the
//        active group only.
//
//    Bottom row (persistent nav strip): three glass cards.
//      • Home — left. Tap returns to the active scene's home page.
//        Dims when already at home.
//        committed group's inline pills plus a chevron at the right
//        edge — the whole card is tappable to open the dense
//        GlassHistoryOverlay. Dims when there's no history yet.
//        listing promoted SentenceCache entries. Dims when empty.
//

import Combine
import SwiftUI

struct CompactTrayStrip: View {
    @Environment(SentenceEngine.self) private var engine

    let onTileTap: (Int) -> Void
    let onGo: () -> Void
    let onReplay: () -> Void
    let onCancelSingle: () -> Void
    let onPlaySingle: () -> Void
    let onCommitActive: () -> Void
    let onShowSentence: () -> Void
    /// Long-press Home to open the caregiver menu (mode toggle + gated Admin).
    let isSentenceShown: Bool

    // Caregiver editor sheets (refine / hand-type override of a generated sentence).
    @State private var editSheet: TrayEditSheet?
    @State private var handTypeDraft = ""
    @State private var refineDraft = ""
    @State private var showBubbleActions = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                ActiveCard(
                    tiles: engine.activeGroup.tiles,
                    sentence: engine.activeGroup.sentence,
                    isThinking: engine.isThinking,
                    onTileTap: onTileTap,
                    onExpandSentence: onShowSentence,
                    onBubbleLongPress: { showBubbleActions = true },
                    isSuppressed: engine.activeIsSuppressed
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    PrimaryPlayButton(
                        canFire: canFire,
                        isPulsing: isPulsing,
                        isReplay: canReplay,
                        replayCount: engine.repetitionCount,
                        isSingleWord: isSingleTile,
                        compact: true,
                        action: primaryAction
                    )
                    .allowsHitTesting(canFire)
                    .opacity(canFire ? 1 : 0.45)

                    if isSingleTile {
                        SingleWordPlayButton(
                            escalationCount: singleWordEscalation,
                            compact: true,
                            action: onPlaySingle
                        )
                    } else {
                        DoneButton(
                            isEnabled: hasActiveContent,
                            isNudge: engine.isDoneNudge && hasActiveContent,
                            compact: true,
                            action: onCommitActive
                        )
                    }
                }
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .sheet(item: $editSheet) { sheet in
            switch sheet {
            case .refine:
                RefineSheet(originalSentence: engine.activeGroup.sentence ?? "",
                            instruction: $refineDraft) { engine.refineActive(instruction: $0) }
            case .handType:
                HandTypeSheet(text: $handTypeDraft) { engine.handTypeActive($0) }
            }
        }
        .confirmationDialog("Sentence", isPresented: $showBubbleActions, titleVisibility: .visible) {
            BubbleActionButtons(
                isSuppressed: engine.activeIsSuppressed,
                onRefine: { refineDraft = ""; editSheet = .refine },
                onHandType: { handTypeDraft = engine.activeGroup.sentence ?? ""; editSheet = .handType },
                onSuppress: { engine.suppressActive() },
                onUnsuppress: { engine.unsuppressActive() },
                onCancel: {}
            )
        }
        // Pause auto-advance while the action/edit sheet is up; resume when both
        // close. Derived from presentation state so it self-corrects even when the
        // OS tears down a sheet on backgrounding without a dismiss callback.
        .onChange(of: showBubbleActions || editSheet != nil) { _, editing in
            editing ? engine.beginCaregiverEdit() : engine.endCaregiverEdit()
        }
        .animation(.easeInOut(duration: 0.22), value: engine.activeGroup.sentence)
    }

    // MARK: - Derived state

    private var canReplay: Bool {
        engine.canReplay && !engine.isThinking
    }

    private var canGo: Bool {
        !canReplay && engine.activeGroup.tiles.count >= 2 && !engine.isThinking
    }

    /// Exactly one tile selected: the single-word path (cancel-✕ primary + a
    /// say-it/escalate secondary). canReplay is already false for one tile, and
    /// the layout shouldn't flip mid-generation, so this ignores both.
    private var isSingleTile: Bool {
        engine.activeGroup.tiles.count == 1
    }

    /// Escalation depth shown on the single-word play button — only meaningful
    /// once the tile has been played (locked); a freshly selected tile shows 0
    /// rather than a stale count carried over from a prior tile.
    private var singleWordEscalation: Int {
        engine.activeGroup.state == .locked ? engine.repetitionCount : 0
    }

    private var canFire: Bool { canReplay || canGo || isSingleTile }

    /// The primary button's action, resolved by current state: replay an
    /// already-spoken group, cancel a single tile, or generate from 2+ tiles.
    private var primaryAction: () -> Void {
        if canReplay { return onReplay }
        if isSingleTile { return onCancelSingle }
        return onGo
    }

    private var isPulsing: Bool {
        // Pulses the play button (2+ tiles) or the cancel-✕ (single tile) once
        // the engine raises the idle nudge at the pulse-after interval.
        engine.isIdleNudge && canFire && !engine.isThinking
    }

    private var hasActiveContent: Bool {
        !engine.activeGroup.tiles.isEmpty
    }
}

// MARK: - Active card

/// Tile chips + inline sentence speech bubble, bound together inside one
/// soft-glass card. When tiles are empty the card collapses to a hint;
/// when a sentence exists, the bubble appears to the right of the chips
/// with a tail pointing at the last chip. Whole bubble is tappable to
/// expand into the GlassSentencePopover.
/// Height of the compact tray's active card — matched to the Play/Clear
/// column so the two sit as one band. Exposed here rather than derived inside
/// the view so `ChipsRow` can size its chips from the same number.
let kCompactTrayCardHeight: CGFloat = 92

private struct ActiveCard: View {
    @ScaledMetric(relativeTo: .caption) private var promptSize: CGFloat = 12

    let tiles: [TileSelection]
    let sentence: String?
    let isThinking: Bool
    let onTileTap: (Int) -> Void
    let onExpandSentence: () -> Void
    /// Long-press the sentence / muted bubble to open the caregiver action sheet.
    let onBubbleLongPress: () -> Void
    /// True when this combination is suppressed (shows a muted bubble instead).
    let isSuppressed: Bool

    /// Both floors below are `@ScaledMetric`, and that is not decoration.
    ///
    /// They were measured against 12pt text. Letting the sentence scale while
    /// the width it must fit into stayed fixed would reproduce the "I / s / e"
    /// column exactly — at a large accessibility setting the caption more than
    /// doubles, so 110pt holds about four characters a line. Scaling the floor
    /// with the text means the tray hands over to the button *sooner* as text
    /// grows, and the popover — which is `.title3` and has the room — becomes
    /// the reading surface. The tray is a glance; the popover is the read.
    ///
    /// Width the sentence needs before it is worth rendering as text.
    ///
    /// Below this the bubble degrades into a column of single letters, which
    /// looks broken rather than merely small. Above it, three lines of 12pt
    /// italic hold roughly forty characters — enough for what one or two tiles
    /// produce.
    ///
    /// The number is measured, not chosen. A 402pt phone gives this card 299pt
    /// of content (the GeometryReader sits inside the card's own 5pt
    /// horizontal padding), so two 80pt chips leave exactly 129 — which a
    /// floor of 132 rejected by three points, dropping an iPhone 17 Pro to the
    /// button at two tiles while a Pro Max kept the sentence. The band that
    /// holds "bubble at one or two, button at three or four" on every current
    /// phone is roughly 100...129; 110 sits in the middle of it.
    @ScaledMetric(relativeTo: .caption) private var minimumSentenceWidth: CGFloat = 110

    /// What the fallback button needs. Smaller than the bubble's floor by a
    /// long way — that is the point of having it — but not zero: squeezed
    /// below this it renders as "Sen / tenc / e", which is the exact failure
    /// the button existed to avoid, reproduced one control later.
    @ScaledMetric(relativeTo: .caption) private var minimumSentenceButtonWidth: CGFloat = 68

    var body: some View {
        // Width-driven, not count-driven. An iPad has room for four full-size
        // chips *and* the sentence; a 16e does not have room for three. Sizing
        // off the tile count alone would shrink the iPad's chips to solve a
        // phone's problem.
        GeometryReader { geo in
            cardContent(width: geo.size.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        // The tray card and the Play/Clear column are one row and should read
        // as one band. The column is two 44pt targets plus their gap; a card
        // sized independently (it was minHeight 56) left the row visibly
        // ragged once the buttons grew to meet the touch-target minimum.
        .frame(height: kCompactTrayCardHeight)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Chips take what is left after the sentence is served, down to a floor.
    /// Past the floor they stop shrinking and the sentence gives way instead —
    /// a chip is the child's feedback that a tap landed, so it is the last
    /// thing that should become unreadable.
    private func chipSize(for width: CGFloat) -> CGFloat {
        let maximum = kCompactTrayCardHeight - 12
        guard !tiles.isEmpty else { return maximum }
        // Chips reserve room for the *button*, never for the bubble. The
        // sentence gets text only when it happens to fit above its floor after
        // the chips have taken their share.
        //
        // Reserving the bubble's larger floor at four tiles — the obvious
        // alternative — made a Pro Max read bubble, button, bubble as tiles
        // were added: raising the reservation squeezed the chips enough that
        // the bubble fitted again. A tray that reverts to an earlier state on
        // the way to being full is worse than one that simply degrades, so
        // there is one reservation and it is the small one.
        let spacing = CGFloat(tiles.count - 1) * 4 + 6
        let free = width - minimumSentenceButtonWidth - spacing
        return min(maximum, max(44, free / CGFloat(tiles.count)))
    }

    @ViewBuilder
    private func cardContent(width: CGFloat) -> some View {
        let chip = chipSize(for: width)
        let sentenceWidth = width - (chip * CGFloat(tiles.count))
            - CGFloat(max(0, tiles.count - 1)) * 4 - 6

        HStack(spacing: 6) {
            if tiles.isEmpty {
                Text("Tap tiles below to start")
                    .font(.system(size: promptSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                ChipsRow(tiles: tiles, chipSize: chip, onTap: onTileTap)
                if isSuppressed {
                    CompactMutedBubble()
                        .layoutPriority(1)
                        .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                } else if let sentence = sentence {
                    // With a full tray there is no width left for readable text.
                    // Show a control that says so, rather than a bubble squeezed
                    // past legibility.
                    //
                    // Deliberately NOT an automatic popover: that behaviour was
                    // removed because it covered the board and the Home cell,
                    // and bringing it back as a crowding fallback would restore
                    // the same problem at the worst moment. The sentence is the
                    // caregiver's read, so an explicit tap is the honest cost.
                    if sentenceWidth < minimumSentenceWidth {
                        SentenceButton(action: onExpandSentence)
                            .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                    } else {
                        SentenceBubble(text: sentence, onExpand: onExpandSentence)
                            .layoutPriority(1)
                            .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                    }
                } else if isThinking {
                    ThinkingBubble()
                        .layoutPriority(1)
                }
            }
        }
    }
}

// MARK: - Chip strip (active)

private struct ChipsRow: View {
    let tiles: [TileSelection]
    /// Measured by the card, which is the only view that knows how much width
    /// the sentence still needs.
    let chipSize: CGFloat
    let onTap: (Int) -> Void

    private let cornerRadius: CGFloat = 8

    /// How far the white plate sits inside the colored chip. Proportional
    /// rather than fixed, because `chipSize` is measured against whatever width
    /// the sentence has left — the same 8% `TileView` uses at board sizes, with
    /// a floor so a squeezed chip still has an edge of color.
    private func plateInset(_ chip: CGFloat) -> CGFloat { max(2, chip * 0.08) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { idx, tile in
                let accent = TileColorResolver.color(for: tile)
                Button(action: { onTap(idx) }) {
                    // Color as the card, picture on a white plate inside it —
                    // the board's structure, minus the label the compact tray
                    // has never had room for. It was a 0.14 tint behind the
                    // picture with a hairline border, which on a phone sat
                    // directly under a board of solid cards and read as a
                    // different kind of object.
                    TileImageView(key: tile.key, wordClass: tile.wordClass)
                        .padding(2)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 3))
                        .padding(plateInset(chipSize))
                        .frame(width: chipSize, height: chipSize)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(tile.value)")
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Inline sentence bubble

/// Stand-in for the sentence bubble when the tray is too full to show text.
///
/// Reads as a thing to press rather than a truncated sentence: a bubble showing
/// two characters looks broken, while a button that says "Sentence" is simply
/// compact.
private struct SentenceButton: View {
    @ScaledMetric(relativeTo: .caption2) private var glyphSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // At an accessibility size the word "Sentence" is wider than what
            // the chips have left, and a button that swells to fit it takes the
            // room the chips need to stay recognisable. The glyph alone is
            // enough: the control sits where the sentence always sits, and its
            // accessibility label still reads "Show sentence".
            ViewThatFits(in: .horizontal) {
                VStack(spacing: 2) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: glyphSize, weight: .semibold))
                    Text("Sentence")
                        .font(.system(size: labelSize, weight: .semibold))
                        .lineLimit(1)
                }
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: glyphSize, weight: .semibold))
            }
            // Deliberately NOT .fixedSize(). That was here to stop the label
            // being squeezed into "Sen / tenc / e", but it also denied
            // ViewThatFits the one thing it needs — a proposal narrower than
            // the ideal — so the button held its full width and the whole card
            // overflowed underneath the Play/Clear column instead. The glyph
            // fallback above is the better answer to the same problem.
            .frame(maxWidth: .infinity)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show sentence")
    }
}

private struct SentenceBubble: View {
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 10

    let text: String
    let onExpand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(text)
                .font(.system(size: textSize, weight: .regular).italic())
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        // A floor, so the bubble cannot be squeezed into a column of single
        // letters. If the row genuinely cannot spare this much, the caller
        // swaps in `SentenceButton` instead of rendering an unreadable sliver.
        .frame(minWidth: 96, alignment: .leading)
        .background(
            LeftTailBubble()
                .fill(Color(.tertiarySystemFill))
        )
        .overlay(
            LeftTailBubble()
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .contentShape(LeftTailBubble())
        // Plain view (not a Button) so the parent card's long-press isn't swallowed.
        .onTapGesture { onExpand() }
        .accessibilityLabel("Sentence")
        .accessibilityValue(text)
        .accessibilityHint("Expand sentence")
    }
}

/// Muted-state bubble for a suppressed combination — signals the set is
/// intentionally blocked (not broken) and long-presses to un-suppress.
private struct CompactMutedBubble: View {
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Muted")
                .font(.system(size: textSize).italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(LeftTailBubble().fill(Color(.tertiarySystemFill)))
        .contentShape(LeftTailBubble())
        .accessibilityLabel("Muted sentence")
        .accessibilityHint("Long-press to un-suppress")
    }
}

/// Thin placeholder bubble shown while the engine is generating but a
/// sentence hasn't arrived yet. Matches the SentenceBubble shape so it
/// doesn't change the active card's footprint mid-render.
private struct ThinkingBubble: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(phase == i ? 0.8 : 0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(LeftTailBubble().fill(Color(.tertiarySystemFill)))
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Speech-bubble shape (left-pointing tail)

/// Module-internal so the iPad SentenceTrayView can render its inline
/// sentence bubble with the same shape language as the iPhone tray.
struct LeftTailBubble: Shape {
    var cornerRadius: CGFloat = 10
    var tailWidth: CGFloat = 6
    var tailHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let bodyRect = CGRect(
            x: rect.minX + tailWidth,
            y: rect.minY,
            width: max(0, rect.width - tailWidth),
            height: rect.height
        )
        p.addRoundedRect(
            in: bodyRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addLine(to: CGPoint(x: rect.minX + tailWidth, y: midY - tailHeight / 2))
        p.addLine(to: CGPoint(x: rect.minX + tailWidth, y: midY + tailHeight / 2))
        p.closeSubpath()
        return p
    }
}

// MARK: - Nav strip (Home + History card + Favorites card)

// MARK: - Home / Favorites end cards

// MARK: - History card (pills + inline chevron)

/// One glass card spanning the middle of the nav strip. Inside: a row of
/// inline TilePills previewing the most recent committed group, followed
/// by a chevron-down at the right edge. The whole card is one tappable
/// surface that opens the dense GlassHistoryOverlay.
private struct TilePill: View {
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    let tile: TileSelection

    private let iconSize: CGFloat = 22

    private var accent: Color { TileColorResolver.color(for: tile) }

    var body: some View {
        HStack(spacing: 5) {
            // Same three parts as a tile, laid out along a capsule instead of
            // stacked: color as the ground, picture on a white plate, word on
            // the color. The tinted-fill version was the only place left where
            // a word carried its color at 16% instead of wearing it.
            TileImageView(key: tile.key, wordClass: tile.wordClass)
                .padding(1)
                .frame(width: iconSize, height: iconSize)
                .background(Color.white)
                .clipShape(Circle())

            Text(tile.value)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(TileColorResolver.label(on: accent))
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .padding(.vertical, 2)
        .background(Capsule().fill(accent))
    }
}

// MARK: - Shared nav-card dimensions + chrome

/// Uniform width across Home / Favorites — matches the Play/Done compact
/// button width so the four chrome surfaces read as one family.
private let kNavCardWidth: CGFloat = 60

/// Uniform height for ALL bottom-row cards (Home, History, Favorites)
/// so the row reads as one band. Sized to fit the inline TilePills inside
/// the history card.
private let kNavCardHeight: CGFloat = 28

private let kNavCornerRadius: CGFloat = 10

private var navCardBackground: some View {
    TrayCardBackground(cornerRadius: kNavCornerRadius)
}

// MARK: - Shared tray-card chrome

/// Solid-fill rounded card with a 1pt primary stroke. Shared across the
/// iPhone CompactTrayStrip and iPad SentenceTrayView so all chrome
/// surfaces (Play, Done, Home, History, Favorites) read as one family
/// regardless of form factor.
struct TrayCardBackground: View {
    var cornerRadius: CGFloat = 10
    var fill: Color = Color(.systemBackground)
    var strokeOpacity: Double = 0.12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
        }
    }
}
