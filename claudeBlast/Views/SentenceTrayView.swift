// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceTrayView.swift
//  claudeBlast
//
//  Two-row tray (iPad horizontal layout per Kurt's mockup):
//
//    Top row: the active group rendered as full-size tile cards, a prominent play/replay button,
//             and a yellow sentence bubble showing the AI sentence (or a spelled-out preview
//             while the child is still building).
//    Bottom row: a compact horizontal strip of closed history groups (tap to reopen, long-press
//                for Delete). A trailing "+" affordance unlocks a locked active group for further
//                additions when there's room under the cap.
//
//  Phone/portrait responsive layout (bubble → liquid-glass overlay) is a follow-up.
//

import Combine
import SwiftUI
import UIKit

/// Shared height for the three top-row elements (active tile card, play+Done column, sentence
/// bubble). Each gets the same explicit frame height and a matching inner vertical padding so
/// they read as a single horizontal row.
private let kCardHeight: CGFloat = 88
private let kCardVerticalPadding: CGFloat = 6
private let kActiveRowHeight: CGFloat = kCardHeight
private let kActiveImageSize: CGFloat = 56
private let kPlayButtonWidth: CGFloat = 82
private let kPlayButtonHeight: CGFloat = 54
private let kDoneButtonHeight: CGFloat = 28
private let kPlayDoneSpacing: CGFloat = 6
private let kHistoryTileSize: CGFloat = 22

struct SentenceTrayView: View {
    @Environment(SentenceEngine.self) private var engine

    let onTileTap: (Int) -> Void
    let onGo: () -> Void
    let onReplay: () -> Void
    let onReopenHistory: (UUID) -> Void
    let onDeleteHistory: (UUID) -> Void
    /// Tap the inline sentence bubble to pop out the full sentence overlay.
    /// On iPad this is rarely needed (the inline bubble has plenty of room)
    /// but the affordance stays for parity with the iPhone tray.
    let onExpandSentence: () -> Void
    /// Tap the Home card. Wired to navigate to the active scene's root page.
    let onHome: () -> Void
    /// Long-press Home to open the caregiver menu (mode toggle + gated Admin).
    let onOpenMenu: () -> Void
    /// Tap the Favorites card. Opens the GlassFavoritesOverlay.
    let onShowFavorites: () -> Void
    /// True when the user is at the home page — dims the Home card.
    let isAtHome: Bool
    /// Number of promoted SentenceCache entries — shown next to the star.
    let favoritesCount: Int
    /// True when the sentence popover is currently visible (so the inline
    /// bubble can mute its expand affordance).
    let isSentenceShown: Bool
    /// True when the favorites overlay is currently visible — dims the card.
    let isFavoritesShown: Bool
    /// Currently unused in iPad layout; reserved for the phone/responsive variant where the
    /// bubble becomes a dismissible overlay (the "×" → clearSelection).
    let onDismissActive: () -> Void
    /// Commit the active group to history and start fresh. Wired to the Done button below
    /// the play control, and triggered automatically by the engine's auto-Done idle timer.
    let onCommitActive: () -> Void
    /// Single-word path: cancel (clear) the lone selected tile. Wired to the primary
    /// button when exactly one tile is selected.
    let onCancelSingle: () -> Void
    /// Single-word path: say (and escalate on repeat) the lone selected tile. Wired to
    /// the Done-slot button when exactly one tile is selected.
    let onPlaySingle: () -> Void

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

    // Caregiver editor sheets (refine / hand-type override of a generated sentence).
    @State private var editSheet: TrayEditSheet?
    @State private var handTypeDraft = ""
    @State private var refineDraft = ""
    @State private var showBubbleActions = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            activeRow
            navStrip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
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
        // Pause auto-advance whenever the action sheet or an edit sheet is up, and
        // resume the instant BOTH close. Derived from presentation state (not from
        // begin/end calls in each action closure) so it stays correct even when the
        // OS tears down a sheet on backgrounding without firing its dismiss handler.
        .onChange(of: showBubbleActions || editSheet != nil) { _, editing in
            editing ? engine.beginCaregiverEdit() : engine.endCaregiverEdit()
        }
    }

    // MARK: - Top row

    /// Active card on the left (chips + inline speech bubble bound as one
    /// surface, mirroring the iPhone tray's ActiveCard), and the Play/Done
    /// stack on the right.
    private var activeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ActiveTrayCard(
                tiles: engine.activeGroup.tiles,
                sentence: engine.activeGroup.sentence,
                isThinking: engine.isThinking,
                onTileTap: onTileTap,
                onExpandSentence: onExpandSentence,
                onBubbleLongPress: { showBubbleActions = true },
                isSuppressed: engine.activeIsSuppressed
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // Play and Done handle their own enabled/disabled rendering —
            // no outer opacity wrap so they stay visible even when the
            // active group is empty (matches the iPhone tray).
            playColumn
        }
        .frame(height: kActiveRowHeight)
    }

    // MARK: - Bottom nav strip (Home + History scroll + Favorites)

    /// Replaces the old plain history row + the standalone TileGridView
    /// navBar. Home and Favorites are the same-family cards from the
    /// iPhone tray, sized up for iPad. History stays as a horizontal
    /// scroll of TileGroupBubble chips — the existing iPad pattern that
    /// makes sense given the available width.
    private var navStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            IPadHomeCard(isEnabled: !isAtHome, action: onHome, onOpenMenu: onOpenMenu)

            historyScroll
                .frame(maxWidth: .infinity)

            IPadFavoritesCard(
                count: favoritesCount,
                isEnabled: favoritesCount > 0 && !isFavoritesShown,
                action: onShowFavorites
            )
        }
        .frame(height: kIPadNavCardHeight)
    }

    private var historyScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                if engine.groupHistory.isEmpty {
                    Text("No history yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                } else {
                    // Closed groups: oldest first (left), newest last (right).
                    ForEach(Array(engine.groupHistory.reversed()), id: \.id) { group in
                        HistoryGroupChip(
                            group: group,
                            onTap: { onReopenHistory(group.id) },
                            onDelete: { onDeleteHistory(group.id) }
                        )
                        .id(group.id)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Play button + Done (commit) button stacked vertically. Total height = kCardHeight.
    private var playColumn: some View {
        VStack(spacing: kPlayDoneSpacing) {
            PrimaryPlayButton(
                canFire: canFire,
                isPulsing: isPulsing,
                isReplay: canReplay,
                replayCount: engine.repetitionCount,
                isSingleWord: isSingleTile,
                action: primaryAction
            )
            .allowsHitTesting(canFire)
            .opacity(canFire ? 1 : 0.45)

            if isSingleTile {
                SingleWordPlayButton(
                    escalationCount: singleWordEscalation,
                    action: onPlaySingle
                )
            } else {
                DoneButton(
                    isEnabled: hasActiveContent,
                    isNudge: engine.isDoneNudge && hasActiveContent,
                    action: onCommitActive
                )
            }
        }
        .frame(height: kCardHeight)
    }

}

// MARK: - iPad bottom-row sizing

/// Height of the iPad nav strip cards (Home, History scroll, Favorites).
/// Sized to fit the existing TileGroupBubble history chips comfortably.
private let kIPadNavCardHeight: CGFloat = 38
private let kIPadNavCardWidth: CGFloat = 84
private let kIPadNavCornerRadius: CGFloat = 11

// MARK: - Active tray card (iPad: chips + inline speech bubble)

/// Mirrors the iPhone CompactTrayStrip's ActiveCard at iPad proportions.
/// Chips on the left (full ActiveTileCards with labels, since there's
/// room), then a left-tail speech bubble carrying the sentence when one
/// exists. The whole card is bound by one outer surface so chips and
/// sentence read as one unit. Tap the bubble to pop out the
/// GlassSentencePopover — rarely needed on iPad but kept for parity.
private struct ActiveTrayCard: View {
    let tiles: [TileSelection]
    let sentence: String?
    let isThinking: Bool
    let onTileTap: (Int) -> Void
    let onExpandSentence: () -> Void
    /// Long-press the sentence / muted bubble to open the caregiver action sheet
    /// (refine · hand-type · suppress / un-suppress). Fired as the press completes.
    let onBubbleLongPress: () -> Void
    /// True when this combination is suppressed (shows a muted bubble instead).
    let isSuppressed: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if tiles.isEmpty {
                Text("Tap tiles to build a sentence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Engine enforces max 4 tiles — a plain HStack with
                // fixedSize keeps the chips at their natural width so the
                // sentence bubble (with maxWidth: .infinity) can only
                // claim the remaining space, never push the chips out.
                HStack(spacing: 8) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        ActiveTileCard(tile: tile) { onTileTap(index) }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: true, vertical: false)
                .animation(.easeInOut(duration: 0.18), value: tiles.count)

                if isSuppressed {
                    IPadMutedBubble()
                        .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                } else if let sentence = sentence {
                    IPadSentenceBubble(text: sentence, onExpand: onExpandSentence)
                        .onLongPressGesture(minimumDuration: 0.4, perform: onBubbleLongPress)
                } else if isThinking {
                    IPadThinkingBubble()
                } else {
                    Color.clear
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: kCardHeight)
        .background(TrayCardBackground(cornerRadius: 14))
    }
}

/// Inline sentence bubble for the iPad active card. Same LeftTailBubble
/// shape as the iPhone tray, sized up for the iPad's larger real estate.
/// Still tappable to expand the full popover when the caregiver wants the
/// big-text presentation.
private struct IPadSentenceBubble: View {
    let text: String
    let onExpand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.title3.weight(.regular).italic())
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(
            LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16)
                .fill(Color(.tertiarySystemFill))
        )
        .overlay(
            LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .contentShape(LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16))
        // Plain view (not a Button) so the long-press gesture on the parent card
        // isn't swallowed; a tap still expands the sentence popover.
        .onTapGesture { onExpand() }
        .accessibilityLabel("Sentence")
        .accessibilityValue(text)
        .accessibilityHint("Expand sentence")
    }
}

/// Muted-state bubble for a suppressed combination: signals that this set is
/// intentionally blocked (not broken), and long-presses to un-suppress.
private struct IPadMutedBubble: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Muted — long-press to restore")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background(
            LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16)
                .fill(Color(.tertiarySystemFill))
        )
        .contentShape(LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16))
        .accessibilityLabel("Muted sentence")
        .accessibilityHint("Long-press to un-suppress")
    }
}

/// The caregiver action sheet raised by long-pressing the sentence bubble.
/// Presented as a `confirmationDialog` (not a `.contextMenu`, which misbehaves in
/// the tray hierarchy on iOS 26 and gave no reliable "opened" hook to pause the
/// auto-Done timer). A normal sentence offers refine / hand-type / suppress; a
/// suppressed (muted) combination offers un-suppress / hand-type. Shared by both
/// trays. Every action either opens a sheet (which resumes on dismiss) or resumes
/// the timer itself via its closure.
struct BubbleActionButtons: View {
    let isSuppressed: Bool
    let onRefine: () -> Void
    let onHandType: () -> Void
    let onSuppress: () -> Void
    let onUnsuppress: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if isSuppressed {
            Button("Un-suppress", action: onUnsuppress)
            Button("Hand-Type Sentence", action: onHandType)
        } else {
            Button("Refine / Try Again", action: onRefine)
            Button("Hand-Type Sentence", action: onHandType)
            Button("Suppress This", role: .destructive, action: onSuppress)
        }
        Button("Cancel", role: .cancel, action: onCancel)
    }
}

/// Which caregiver editor is presented over the tray. One enum-driven sheet
/// avoids two `.sheet(isPresented:)` modifiers racing on the same view.
enum TrayEditSheet: Identifiable {
    case refine, handType
    var id: Int { hashValue }
}

/// Instruction-guided refine, mirroring the tile-art refine flow: the caregiver
/// sees the sentence they're reacting to and tells the AI how to change it. An
/// empty instruction is a plain try-again.
struct RefineSheet: View {
    let originalSentence: String
    @Binding var instruction: String
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current sentence")
                    .font(.caption).foregroundStyle(.secondary)
                Text("“\(originalSentence)”")
                    .font(.title3.italic())
                    .foregroundStyle(.primary)
                Text("Tell the AI how to improve it — e.g. “make it shorter”, “she's asking, not telling”. Leave blank to just try again.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 4)
                TextField("How should it change?", text: $instruction, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($focused)
                Spacer()
            }
            .padding()
            .navigationTitle("Refine Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Refine") { onSubmit(instruction); dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Caregiver editor for hand-typing the exact sentence a tile combination should
/// speak. Prefilled with the current AI sentence so it reads as an edit, not a
/// blank slate. Saving stores a durable, authoritative override that outlives
/// model/prompt changes.
struct HandTypeSheet: View {
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("This exact sentence will be spoken whenever these tiles are selected, replacing the AI sentence. It stays even if the app's model or prompts change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.title3)
                    .focused($focused)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
                Spacer()
            }
            .padding()
            .navigationTitle("Hand-Type Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }
                        .disabled(isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Animated "thinking" placeholder for the iPad bubble, sized to match
/// the IPadSentenceBubble's footprint so the active card doesn't reflow
/// mid-generation.
private struct IPadThinkingBubble: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(phase == i ? 0.8 : 0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 22)
        .background(
            LeftTailBubble(cornerRadius: 14, tailWidth: 10, tailHeight: 16)
                .fill(Color(.tertiarySystemFill))
        )
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - iPad nav cards (Home / Favorites)

private struct IPadHomeCard: View {
    let isEnabled: Bool
    let action: () -> Void
    let onOpenMenu: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Home")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .frame(width: kIPadNavCardWidth, height: kIPadNavCardHeight)
            .background(TrayCardBackground(cornerRadius: kIPadNavCornerRadius))
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

private struct IPadFavoritesCard: View {
    let count: Int
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnabled ? .orange : Color.orange.opacity(0.5))
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)
            }
            .frame(width: kIPadNavCardWidth, height: kIPadNavCardHeight)
            .background(TrayCardBackground(cornerRadius: kIPadNavCornerRadius))
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Favorites")
        .accessibilityValue("\(count)")
        .accessibilityHint(isEnabled ? "Opens favorites" : "No favorites yet")
    }
}

// MARK: - Active tile card

private struct ActiveTileCard: View {
    let tile: TileSelection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: kActiveImageSize, height: kActiveImageSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(tile.value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, kCardVerticalPadding)
            .frame(height: kCardHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            )
            // Retain the grid's wordClass color-coding in the tray so a chip
            // reads as the same category it does on the board.
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(colorForWordClass(tile.wordClass).opacity(0.6), lineWidth: 2.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tile.value)")
    }
}

// MARK: - Primary play button

struct PrimaryPlayButton: View {
    let canFire: Bool
    let isPulsing: Bool
    /// True when the active group is locked and tapping triggers an escalation-replay rather
    /// than first-time generation. The icon stays the play triangle either way; we add a small
    /// recycle badge in the top-right corner to mark replay mode.
    let isReplay: Bool
    /// Number of replays already performed on the current active group. When > 0 the badge
    /// turns into a small pill carrying the count, so the caregiver can see escalation depth
    /// without watching the prompt logs.
    var replayCount: Int = 0
    /// True when exactly one tile is selected. A single word needs no sentence
    /// generation, so the button becomes a cancel control: the icon switches to
    /// an ✕ and tapping clears the tile (the word is already spoken on tap).
    /// Mutually exclusive with `isReplay`.
    var isSingleWord: Bool = false
    /// Tighter sizing for the compact (iPhone) tray. iPad uses the default.
    var compact: Bool = false
    let action: () -> Void

    private var buttonWidth: CGFloat { compact ? 60 : kPlayButtonWidth }
    private var buttonHeight: CGFloat { compact ? 44 : kPlayButtonHeight }
    private var iconSize: CGFloat { compact ? 22 : 30 }
    private var cornerRadius: CGFloat { compact ? 10 : 14 }

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulsePhase: Int = 0
    @State private var hueRotation: Double = 0

    /// Full ROYGBIV halo cycle. The shadow color steps through these in sequence so the halo
    /// reads as a slow rainbow sweep around the button. The icon itself uses a continuous
    /// hue-rotation on top of a blue base so its color drifts smoothly through every hue —
    /// the discrete halo + smooth icon combine for the rainbow effect.
    private static let pulseColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .indigo, .purple,
    ]
    /// How long each halo color holds before stepping to the next. With 7 colors and a 0.4s
    /// step the halo completes a full rainbow loop in ~2.8s.
    private static let phaseStepInterval: Duration = .milliseconds(400)
    /// Hue-rotation tick rate for the icon. ~30 Hz produces a visually smooth sweep.
    private static let hueTickInterval: Duration = .milliseconds(33)
    /// Degrees per tick. 4.5° × ~30 Hz ≈ 135°/s → full revolution in ~2.7s, roughly matching
    /// the halo cycle so the two stay in phase.
    private static let hueDegreesPerTick: Double = 4.5

    private var haloColor: Color {
        guard isPulsing else { return .black.opacity(0.06) }
        return Self.pulseColors[pulsePhase % Self.pulseColors.count].opacity(0.55)
    }

    private var haloRadius: CGFloat {
        isPulsing ? 18 : 2
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: haloColor, radius: haloRadius, y: 1)

                Image(systemName: isSingleWord ? "xmark" : "play.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .hueRotation(.degrees(hueRotation))
            }
            .overlay(alignment: .topTrailing) {
                if isReplay {
                    ReplayBadge(count: replayCount, compact: compact)
                        .padding(compact ? 1 : 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .scaleEffect(pulseScale)
        }
        .buttonStyle(.plain)
        .disabled(!canFire)
        .onAppear { applyScalePulse(isPulsing) }
        .onChange(of: isPulsing) { _, newValue in
            applyScalePulse(newValue)
            if !newValue {
                pulsePhase = 0
                withAnimation(.easeOut(duration: 0.3)) {
                    hueRotation = 0
                }
            }
        }
        .task(id: isPulsing) {
            guard isPulsing else { return }
            var phaseAccumulator: Duration = .seconds(0)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hueTickInterval)
                if Task.isCancelled { return }
                hueRotation = (hueRotation + Self.hueDegreesPerTick)
                    .truncatingRemainder(dividingBy: 360)
                phaseAccumulator += Self.hueTickInterval
                if phaseAccumulator >= Self.phaseStepInterval {
                    phaseAccumulator = .seconds(0)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        pulsePhase = (pulsePhase + 1) % Self.pulseColors.count
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isReplay)
        .animation(.easeInOut(duration: 0.3), value: isPulsing)
        .animation(.linear(duration: 0.04), value: hueRotation)
        .accessibilityLabel(isSingleWord ? "Clear word" : (isReplay ? "Replay sentence" : "Play sentence"))
    }

    private func applyScalePulse(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Replay escalation badge

/// Small badge attached to the play button's top-right corner when in
/// replay mode. Starts as a circular recycle icon. Once the caregiver has
/// hit replay at least once, the badge expands to a capsule carrying the
/// escalation count next to the recycle glyph (e.g. `↺ 2`). Same visual
/// language for iPad and iPhone — only the icon/text sizes differ.
struct ReplayBadge: View {
    let count: Int
    let compact: Bool

    private var iconSize: CGFloat { compact ? 8 : 12 }
    private var textSize: CGFloat { compact ? 9 : 12 }
    private var innerPadding: CGFloat { compact ? 2 : 4 }

    var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.orange)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: textSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, count > 0 ? innerPadding + 1 : innerPadding)
        .padding(.vertical, innerPadding)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: count)
    }
}

// MARK: - Done / commit button

struct DoneButton: View {
    let isEnabled: Bool
    /// Single binary trigger from the engine. Once true, the button drives its own escalating
    /// animation independent of any other clock: stage 0 (blue) → stage 1 (green) → stage 2
    /// (red), each ~2s apart, with progressively heavier border, font weight, and shadow.
    let isNudge: Bool
    /// Tighter sizing for the compact (iPhone) tray. iPad uses the default.
    var compact: Bool = false
    let action: () -> Void

    private var buttonWidth: CGFloat { compact ? 60 : kPlayButtonWidth }
    private var buttonHeight: CGFloat { compact ? 22 : kDoneButtonHeight }
    private var cornerRadius: CGFloat { compact ? 10 : 8 }

    @State private var nudgeScale: CGFloat = 1.0
    @State private var nudgeStage: Int = 0
    @State private var stageTask: Task<Void, Never>?

    /// Per-stage hold time inside the button's internal ramp.
    private static let stageInterval: Duration = .seconds(2)

    private var borderColor: Color {
        guard isNudge else { return Color.primary.opacity(0.12) }
        switch nudgeStage {
        case 0:  return Color.blue.opacity(0.75)
        case 1:  return Color.green.opacity(0.85)
        default: return Color.red.opacity(0.95)
        }
    }

    private var borderWidth: CGFloat {
        guard isNudge else { return 1 }
        switch nudgeStage {
        case 0:  return 1.5
        case 1:  return 2.0
        default: return 2.5
        }
    }

    private var foreground: Color {
        guard isNudge else { return .secondary }
        switch nudgeStage {
        case 0:  return .blue
        case 1:  return .green
        default: return .red
        }
    }

    private var textWeight: Font.Weight {
        guard isNudge else { return .medium }
        switch nudgeStage {
        case 0:  return .semibold
        case 1:  return .bold
        default: return .heavy
        }
    }

    private var iconWeight: Font.Weight {
        guard isNudge else { return .bold }
        switch nudgeStage {
        case 0:  return .bold
        case 1:  return .heavy
        default: return .black
        }
    }

    private var shadowColor: Color {
        guard isNudge else { return Color.accentColor }
        switch nudgeStage {
        case 0:  return .blue
        case 1:  return .green
        default: return .red
        }
    }

    private var shadowOpacity: Double {
        guard isNudge else { return 0 }
        switch nudgeStage {
        case 0:  return 0.20
        case 1:  return 0.32
        default: return 0.50
        }
    }

    private var shadowRadius: CGFloat {
        guard isNudge else { return 4 }
        switch nudgeStage {
        case 0:  return 4
        case 1:  return 6
        default: return 8
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: iconWeight))
                Text("Done")
                    .font(.caption.weight(textWeight))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
                    .shadow(color: shadowColor.opacity(shadowOpacity), radius: shadowRadius, y: 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .frame(width: buttonWidth, height: buttonHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(nudgeScale)
        .onAppear { applyNudge(isNudge) }
        .onChange(of: isNudge) { _, newValue in
            applyNudge(newValue)
        }
        .animation(.easeInOut(duration: 0.35), value: isNudge)
        .animation(.easeInOut(duration: 0.4), value: nudgeStage)
        .accessibilityLabel("Save this sentence and start a new one")
    }

    private func applyNudge(_ active: Bool) {
        stageTask?.cancel()
        if active {
            nudgeStage = 0
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                nudgeScale = 1.07
            }
            stageTask = Task {
                for stage in 1...2 {
                    try? await Task.sleep(for: Self.stageInterval)
                    if Task.isCancelled { return }
                    nudgeStage = stage
                }
            }
        } else {
            nudgeStage = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                nudgeScale = 1.0
            }
        }
    }
}

// MARK: - Single-word play / escalation button

/// Replaces the Done button in the bottom button slot while exactly one tile
/// is selected. Done has no purpose for a single tile (the cancel-✕ clears it),
/// so this slot becomes a "say it" control that escalates on repeat — the
/// volume knob for a child mashing one tile. Shows the escalation depth as an
/// orange count once the word has been re-pressed, mirroring the play button's
/// replay badge. Same footprint as DoneButton so the column doesn't reflow.
struct SingleWordPlayButton: View {
    /// Current escalation depth for this tile (0 = baseline / not yet escalated).
    let escalationCount: Int
    /// Tighter sizing for the compact (iPhone) tray. iPad uses the default.
    var compact: Bool = false
    let action: () -> Void

    private var buttonWidth: CGFloat { compact ? 60 : kPlayButtonWidth }
    private var buttonHeight: CGFloat { compact ? 22 : kDoneButtonHeight }
    private var cornerRadius: CGFloat { compact ? 10 : 8 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                if escalationCount > 0 {
                    Text("\(escalationCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
            .foregroundStyle(escalationCount > 0 ? .orange : .blue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(escalationCount > 0 ? Color.orange.opacity(0.5) : Color.primary.opacity(0.12),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: buttonWidth, height: buttonHeight)
        .animation(.easeInOut(duration: 0.2), value: escalationCount)
        .accessibilityLabel("Say this word")
        .accessibilityValue(escalationCount > 0 ? "Repeated \(escalationCount)" : "")
    }
}

// MARK: - History group chip

private struct HistoryGroupChip: View {
    let group: TileGroup
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            TileGroupBubble(tiles: group.tiles)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - TileGroupBubble (shared)

/// The "bubble of tiles" used by both the in-app sentence tray history row and the AdminView
/// Activity Log. Each tile is a tinted capsule chip (image + label colored by wordClass),
/// wrapped in a rounded card with a soft shadow.
struct TileGroupBubble: View {
    let tiles: [TileSelection]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                HStack(spacing: 3) {
                    TileImageView(key: tile.key, wordClass: tile.wordClass)
                        .frame(width: kHistoryTileSize, height: kHistoryTileSize)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(tile.value)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(wordClassColor(tile.wordClass).opacity(0.20))
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Shared helpers

/// Thin shim over the canonical mapping so tray call sites stay unchanged.
/// See TileColorResolver / VocabularyClasses for the source of truth.
func wordClassColor(_ wordClass: String) -> Color {
    TileColorResolver.color(for: wordClass)
}

