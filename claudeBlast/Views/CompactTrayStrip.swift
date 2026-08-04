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
//      • History card — middle, flex-width. Holds the most recent
//        committed group's inline pills plus a chevron at the right
//        edge — the whole card is tappable to open the dense
//        GlassHistoryOverlay. Dims when there's no history yet.
//      • Favorites — right. Tap opens the GlassFavoritesOverlay
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
    let onShowHistory: () -> Void
    let onShowFavorites: () -> Void
    let onHome: () -> Void
    /// Long-press Home to open the caregiver menu (mode toggle + gated Admin).
    let onOpenMenu: () -> Void
    let isAtHome: Bool
    let favoritesCount: Int
    let isSentenceShown: Bool
    let isHistoryShown: Bool
    let isFavoritesShown: Bool

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

            NavStrip(
                isAtHome: isAtHome,
                onHome: onHome,
                onOpenMenu: onOpenMenu,
                latestGroup: engine.groupHistory.first,
                historyCount: engine.groupHistory.count,
                isHistoryShown: isHistoryShown,
                onShowHistory: onShowHistory,
                favoritesCount: favoritesCount,
                isFavoritesShown: isFavoritesShown,
                onShowFavorites: onShowFavorites
            )
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
        .animation(.easeInOut(duration: 0.22), value: engine.groupHistory.first?.id)
        .animation(.easeInOut(duration: 0.22), value: engine.activeGroup.sentence)
        .animation(.easeInOut(duration: 0.22), value: isHistoryShown)
        .animation(.easeInOut(duration: 0.22), value: isFavoritesShown)
        .animation(.easeInOut(duration: 0.22), value: isAtHome)
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
private struct ActiveCard: View {
    let tiles: [TileSelection]
    let sentence: String?
    let isThinking: Bool
    let onTileTap: (Int) -> Void
    let onExpandSentence: () -> Void
    /// Long-press the sentence / muted bubble to open the caregiver action sheet.
    let onBubbleLongPress: () -> Void
    /// True when this combination is suppressed (shows a muted bubble instead).
    let isSuppressed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if tiles.isEmpty {
                Text("Tap tiles below to start")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                ChipsRow(tiles: tiles, onTap: onTileTap)
                if isSuppressed {
                    CompactMutedBubble()
                        .layoutPriority(1)
                        .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                } else if let sentence = sentence {
                    SentenceBubble(text: sentence, onExpand: onExpandSentence)
                        .layoutPriority(1)
                        .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                } else if isThinking {
                    ThinkingBubble()
                        .layoutPriority(1)
                }
            }
        }
        .frame(minHeight: 56)
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
}

// MARK: - Chip strip (active)

private struct ChipsRow: View {
    let tiles: [TileSelection]
    let onTap: (Int) -> Void

    private let chipSize: CGFloat = 50
    private let cornerRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { idx, tile in
                Button(action: { onTap(idx) }) {
                    ZStack {
                        wordClassColor(tile.wordClass).opacity(0.14)
                        TileImageView(key: tile.key, wordClass: tile.wordClass)
                            .padding(2)
                    }
                    .frame(width: chipSize, height: chipSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(wordClassColor(tile.wordClass).opacity(0.45), lineWidth: 1)
                    )
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

private struct SentenceBubble: View {
    let text: String
    let onExpand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(text)
                .font(.system(size: 12, weight: .regular).italic())
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
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
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Muted")
                .font(.system(size: 12).italic())
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

private struct NavStrip: View {
    let isAtHome: Bool
    let onHome: () -> Void
    let onOpenMenu: () -> Void

    let latestGroup: TileGroup?
    let historyCount: Int
    let isHistoryShown: Bool
    let onShowHistory: () -> Void

    let favoritesCount: Int
    let isFavoritesShown: Bool
    let onShowFavorites: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HomeCard(isEnabled: !isAtHome, action: onHome, onOpenMenu: onOpenMenu)

            HistoryCard(
                group: latestGroup,
                count: historyCount,
                isEnabled: historyCount > 0 && !isHistoryShown,
                action: onShowHistory
            )
            .frame(maxWidth: .infinity)

            FavoritesCard(
                count: favoritesCount,
                isEnabled: favoritesCount > 0 && !isFavoritesShown,
                action: onShowFavorites
            )
        }
    }
}

// MARK: - Home / Favorites end cards

private struct HomeCard: View {
    let isEnabled: Bool
    let action: () -> Void
    let onOpenMenu: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Home")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .frame(width: kNavCardWidth, height: kNavCardHeight)
            .background(navCardBackground)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        // Not `.disabled` — long-press while at home toggles interaction mode.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                onOpenMenu()
            }
        )
        .accessibilityLabel("Go home")
        .accessibilityHint(isEnabled ? "Returns to home page" : "Already at home. Press and hold for caregiver options.")
    }
}

private struct FavoritesCard: View {
    let count: Int
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isEnabled ? .orange : Color.orange.opacity(0.5))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)
            }
            .frame(width: kNavCardWidth, height: kNavCardHeight)
            .background(navCardBackground)
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Favorites")
        .accessibilityValue("\(count)")
        .accessibilityHint(isEnabled ? "Opens favorites" : "No favorites yet")
    }
}

// MARK: - History card (pills + inline chevron)

/// One glass card spanning the middle of the nav strip. Inside: a row of
/// inline TilePills previewing the most recent committed group, followed
/// by a chevron-down at the right edge. The whole card is one tappable
/// surface that opens the dense GlassHistoryOverlay.
private struct HistoryCard: View {
    let group: TileGroup?
    /// Total number of groups in history. Surfaced as a 3-digit counter
    /// (capped at "999+") next to the chevron so the caregiver can see
    /// how much is queued up without opening the full overlay.
    let count: Int
    let isEnabled: Bool
    let action: () -> Void

    private let maxPreview: Int = 4

    private var countLabel: String {
        count > 999 ? "999+" : "\(count)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let group = group {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Array(group.tiles.prefix(maxPreview).enumerated()), id: \.offset) { _, tile in
                                TilePill(tile: tile)
                            }
                            if group.tiles.count > maxPreview {
                                Text("+\(group.tiles.count - maxPreview)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                } else {
                    Text("No history yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 3) {
                    if count > 0 {
                        Text(countLabel)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isEnabled ? .secondary : .tertiary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: kNavCardHeight, alignment: .leading)
            .background(navCardBackground)
            .opacity(isEnabled ? 1.0 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("History — \(count) \(count == 1 ? "row" : "rows")")
        .accessibilityHint(isEnabled ? "Opens history" : "No history yet")
    }
}

/// Inline pill — small circular tile thumbnail + label, color-tinted to
/// match its wordClass. Glass capsule background with tile-colored tint.
private struct TilePill: View {
    let tile: TileSelection

    private let iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                wordClassColor(tile.wordClass).opacity(0.22)
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .padding(1)
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(wordClassColor(tile.wordClass).opacity(0.55), lineWidth: 0.5)
            )

            Text(tile.value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(wordClassColor(tile.wordClass).opacity(0.16))
        )
        .overlay(
            Capsule()
                .strokeBorder(wordClassColor(tile.wordClass).opacity(0.3), lineWidth: 0.5)
        )
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
