// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileView: View {
    let tile: TileModel
    var link: String = ""
    var isAudible: Bool = true
    var isSelected: Bool = false
    var labelFontSize: CGFloat = 11
    /// TileScript playback pulse: when `scriptPulseCount` changes and
    /// `scriptPulseKey` matches this tile, the tile bounces — so viewers can see
    /// each scripted tap, including repeated taps in repetition demos.
    var scriptPulseKey: String? = nil
    var scriptPulseCount: Int = 0
    let onTap: () -> Void

    private var isNavigation: Bool { !link.isEmpty }
    @State private var pulseScale: CGFloat = 1.0
    @State private var glow: CGFloat = 0.0
    /// True while a finger is down on this tile.
    ///
    /// Tracked from the touch rather than fired from the tap, which is what
    /// `HomeGridCell` does and why its press feels better than anything driven
    /// off the button action. A tap-driven animation cannot start until the
    /// finger lifts — by which time the page is already changing, so the press
    /// and the transition compete and the press loses. A touch-driven one has
    /// already played by the time the tap completes, and holding the tile holds
    /// the press, which is the part that reads as a real button.
    @State private var isPressed = false

    var body: some View {
        Button {
            // A nav tile and a word tile answer different questions, so they
            // do not answer them the same way. A word tile pops outward and
            // glows on release: "this is now in your sentence." A nav tile is
            // not being added to anything — it is taking the board somewhere —
            // so it depresses under the finger and the board then slides in the
            // direction of travel.
            if !isNavigation { triggerPulse() }
            onTap()
        } label: {
            VStack(spacing: 0) {
                // Full-bleed square image card
                tileCard

                // Small label below — the images already carry the word,
                // so this is a subtle hint rather than the primary label
                Text(tile.displayName)
                    .font(.system(size: labelFontSize, weight: .medium))
                    .lineLimit(1)
                    // A whole word slightly smaller beats "hamb..." at the size
                    // asked for. The label identifies the picture, and half a
                    // word identifies nothing — least of all for a child who
                    // cannot yet read and is matching shapes.
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        // Press state comes from the button style, not from a raw
        // `DragGesture(minimumDistance: 0)`.
        //
        // The drag version worked and broke grid scrolling: a zero-distance
        // drag on every cell claims the touch the instant a finger lands, so
        // the scroll view never got its pan and the board would not scroll.
        // (`HomeGridCell` gets away with the same gesture only because it is a
        // single cell.) A ButtonStyle reports the same state through the
        // press-vs-scroll arbitration the system already does — and as a bonus
        // it cancels the press when a scroll begins, which a raw drag does not.
        .buttonStyle(PressReportingButtonStyle(isPressed: $isPressed))
        .scaleEffect(pulseScale)
        // Deliberately the same spring and the same depth as `HomeGridCell`,
        // which is the press in this app that feels right: shallow, slow enough
        // to see, and damped loosely enough to overshoot on the way back.
        // Earlier attempts went deeper and faster on the theory that a bigger
        // move is a more visible one — it is not, when it is over in 110ms.
        .scaleEffect(isPressed && isNavigation ? 0.94 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        // Leaving the screen mid-animation must not park a half-finished
        // animation in state.
        //
        // This is the original bug: the word-tile bounce sets its peak
        // immediately and returns to rest in a second `withAnimation`
        // `.delay(0.16)` later. Navigate in between and that delayed half never
        // runs — the tile is off-screen — so it sits waiting, and coming back
        // to the page plays it. Tapping Describe and then Home produced a
        // bounce on Describe at the moment you arrived home.
        .onDisappear {
            pulseScale = 1.0
            glow = 0.0
            isPressed = false
        }
        .onChange(of: scriptPulseCount) { _, _ in
            // Scripted taps don't press the Button, so drive the same bounce from
            // the runner's pulse. The count changes every tap, so mashing the same
            // tile re-fires the animation.
            guard scriptPulseKey == tile.key else { return }
            triggerPulse()
        }
    }

    // Quick press-bounce so every tap — live or scripted — has visible feedback.
    private func triggerPulse() {
      // Pop big and briefly HOLD the peak so it registers in motion / on camera,
      // then ease back slowly so the glow lingers long enough to read.
      withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pulseScale = 1.24; glow = 1.0 }
      withAnimation(.easeOut(duration: 0.45).delay(0.16)) { pulseScale = 1.0; glow = 0.0 }
    }

    @ViewBuilder
    private var tileCard: some View {
        ZStack(alignment: .bottomTrailing) {
            colorForWordClass(tile.wordClass).opacity(0.12)
                .aspectRatio(1, contentMode: .fit)

            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .aspectRatio(1, contentMode: .fit)
                .padding(6)

            if isNavigation {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .blue)
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // Resting border: thick + saturated when selected so the tile clearly
        // stands out from the grid; thin wordClass tint otherwise.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.orange
                        // The border deepens under the finger. A scale change is
                        // read against the border as a reference edge, so a
                        // static border is part of what made a small scale hard
                        // to see. Opacity only — changing its width made the
                        // edge shimmer.
                        : (isNavigation ? Color.blue.opacity(isPressed ? 1.0 : 0.6)
                        : colorForWordClass(tile.wordClass).opacity(0.6)),
                    lineWidth: isSelected ? 6 : 3
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        // Persistent glow lifts the selected tile off the grid so it reads as
        // clearly different, not just "an orange border like any other tile."
        .shadow(color: Color.orange.opacity(isSelected ? 0.75 : 0.0), radius: 10)
        // Press "pop + glow": a thick bright ring + strong colored halo flashes
        // on every tap (glow springs 0→1→0 with the bounce), so a press is
        // unmistakable in motion and on camera.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(glow), lineWidth: 6)
        )
        .shadow(color: Color.cyan.opacity(0.9 * glow), radius: 20)
        .shadow(color: Color.cyan.opacity(0.6 * glow), radius: 9)
    }

    // colorForWordClass is now a shared function in TileImageView.swift
}

/// Plain button that reports its pressed state outward.
///
/// `.buttonStyle(.plain)` renders the label untouched but keeps
/// `configuration.isPressed` to itself, and the state is needed further up the
/// view — the border reacts to it too, and the border is not inside the label.
private struct PressReportingButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

#Preview("Audible tile") {
    let tile = TileModel(key: "eat", wordClass: "actions")
    TileView(tile: tile, link: "", isAudible: true, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Nav tile") {
    let tile = TileModel(key: "food", wordClass: "navigation")
    TileView(tile: tile, link: "food", isAudible: false, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Selected tile") {
    let tile = TileModel(key: "happy", wordClass: "feeling")
    TileView(tile: tile, link: "", isAudible: true, isSelected: true) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}
