// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Where a tile's link sits on the path to the page showing.
///
/// A folder page keeps its own tile in the cell its parent shows it in, and that
/// tile is "here": a child who cannot read sees the tile they just pressed,
/// where they pressed it. The row-1 folder the path started from is "on the
/// way". Both carry a two-tone striped ring that nothing else on the board uses.
/// "Here" adds a red dot and a veil over its picture: it is a label, not a
/// button, and it should look it next to the live folder above it.
///
/// Black and yellow, the hazard stripe: a pattern rather than a hue, because
/// every hue on the board already means a part of speech, and the strongest
/// light/dark pair there is, so it survives High Contrast and colour blindness.
/// (Blue/green read as too subtle on the iPad, Mark 2026-10-25.)
enum WayMark {
    case here, onTheWay

    static let stripes = (Color.black, Color(red: 1.0, green: 0.84, blue: 0.0))
    static let dot = Color(red: 0.90, green: 0.15, blue: 0.17)
    static let veil = Color.white.opacity(0.45)
}

/// The ring and dot, on the square picture card only: a frame in the card's
/// margin around the white plate, two tones in alternating segments. It stops
/// at the label band, so the word underneath keeps its colour and its room.
private struct WayMarkOverlay: ViewModifier {
    let mark: WayMark?
    /// The corner of what it frames: the picture on a classic tile, the whole
    /// tile on a square one.
    var radius: CGFloat = 8
    /// Inset from the edge. A square tile's frame is its own border.
    var inset: CGFloat = 1
    /// The stripe. Narrower round a whole square tile, where the word's band
    /// runs to the bottom edge and a 6pt stripe cut into it.
    var width: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .overlay {
                if mark != nil {
                    ZStack {
                        if mark == .here {
                            RoundedRectangle(cornerRadius: max(0, radius - 2)).fill(WayMark.veil).padding(width)
                        }
                        RoundedRectangle(cornerRadius: radius).strokeBorder(WayMark.stripes.0, lineWidth: width)
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(WayMark.stripes.1, style: StrokeStyle(lineWidth: width, dash: [7, 7]))
                    }
                    .padding(inset)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if mark == .here {
                    Circle()
                        .fill(WayMark.dot)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct TileView: View {
    let tile: TileModel
    var link: String = ""
    /// The `TileColorSlot.rawValue` this link is colored as. Nil on a word tile,
    /// and on a link authored before folders could carry a color.
    var linkColor: String? = nil
    var isAudible: Bool = true
    var labelFontSize: CGFloat = 11
    /// TileScript playback pulse: when `scriptPulseCount` changes and
    /// `scriptPulseKey` matches this tile, the tile bounces — so viewers can see
    /// each scripted tap, including repeated taps in repetition demos.
    var scriptPulseKey: String? = nil
    var scriptPulseCount: Int = 0
    /// Find Word's target: the tile breathes until the caregiver taps anywhere.
    var isHighlighted: Bool = false
    var wayMark: WayMark? = nil
    let onTap: () -> Void

    private var isNavigation: Bool { !link.isEmpty }
    @State private var pulseScale: CGFloat = 1.0
    @State private var glow: CGFloat = 0.0
    /// 0…1, cycling while `isHighlighted`.
    @State private var highlight: CGFloat = 0.0
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

    @Environment(\.tileLook) private var look
    @Environment(TileImageResolver.self) private var resolver

    private var radius: CGFloat { look == .square ? TileLayout.cornerRadius : 10 }

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
            tileFace
            // The card treatment wraps BOTH, so the color runs behind the word
            // and the tile is one object rather than a card with a caption under
            // it. Everything below used to sit on `tileCard`; moving it out is
            // most of this change.
            .clipShape(RoundedRectangle(cornerRadius: radius))
            // A nav tile deepens under the finger: a scale change is read against
            // the edge as a reference, so a static edge is part of what made a
            // small scale hard to see. Opacity only — changing its width made the
            // edge shimmer.
            //
            // **A tile in the tray no longer restyles itself.** It used to take an
            // orange border and an orange glow, from the days when tapping a grid
            // tile toggled it in and out of the tray, so the grid had to show
            // membership. It has not worked that way for a long time — the tray is
            // edited in the tray — and the cost is now much higher than the stale
            // affordance: orange is *nouns*. A tile that changes color on tap
            // contradicts the one thing the color is there to teach, and it does it
            // at the exact moment the child is looking at the tile. Single-word mode
            // never had this treatment; the grid now matches it.
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        isNavigation ? pressRing.opacity(isPressed ? 1.0 : 0.0) : .clear,
                        lineWidth: 3
                    )
            )
            // The square tiles are one sheet of colour 2pt apart; a shadow under
            // each would put a grey seam in every gap.
            .shadow(color: .black.opacity(look == .square ? 0 : 0.12), radius: 2, y: 1)
            // Press "pop + glow": a thick bright ring + strong colored halo flashes
            // on every tap (glow springs 0→1→0 with the bounce), so a press is
            // unmistakable in motion and on camera.
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.white.opacity(glow), lineWidth: 6)
            )
            .shadow(color: Color.cyan.opacity(0.9 * glow), radius: 20)
            .shadow(color: Color.cyan.opacity(0.6 * glow), radius: 9)
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
        // "Here" is a label, not a button: it leads to the page already showing.
        .allowsHitTesting(wayMark != .here)
        .accessibilityHint(wayMark == .here ? "You are here" : "")
        // Find Word: the press's own ring and glow, held and breathing, so the
        // found word reads as "this one" in the board's existing language.
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.white.opacity(highlight), lineWidth: 5)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.cyan.opacity(0.9 * highlight), radius: 18)
        .scaleEffect(1 + 0.08 * highlight)
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
            highlight = 0.0
            isPressed = false
        }
        .onAppear { if isHighlighted { setHighlighted(true) } }
        .onChange(of: isHighlighted) { _, on in setHighlighted(on) }
        .onChange(of: scriptPulseCount) { _, _ in
            // Scripted taps don't press the Button, so drive the same bounce from
            // the runner's pulse. The count changes every tap, so mashing the same
            // tile re-fires the animation.
            guard scriptPulseKey == tile.key else { return }
            triggerPulse()
        }
    }

    private func setHighlighted(_ on: Bool) {
        if on {
            highlight = 0
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { highlight = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { highlight = 0 }
        }
    }

    // Quick press-bounce so every tap — live or scripted — has visible feedback.
    private func triggerPulse() {
      // Pop big and briefly HOLD the peak so it registers in motion / on camera,
      // then ease back slowly so the glow lingers long enough to read.
      withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pulseScale = 1.24; glow = 1.0 }
      withAnimation(.easeOut(duration: 0.45).delay(0.16)) { pulseScale = 1.0; glow = 0.0 }
    }

    /// The word, on the tile's own color.
    ///
    /// It used to sit on the page background in `.secondary` grey, which made
    /// every tile on the board end in the same neutral strip — so the colored
    /// area was the square alone and the color had to compete with the artwork
    /// filling it. Carrying it under the label gives each tile a band of solid,
    /// unobstructed color at a fixed place in the cell, which is what makes a
    /// row of them scan as a color from across the room.
    ///
    /// The picture still carries the word; this is a caption, not the label a
    /// pre-reading child navigates by. So it stays small — only the ground it
    /// sits on changed.
    private var labelBand: some View {
        Text(tile.displayName)
            .font(.system(size: labelFontSize, weight: .semibold))
            .lineLimit(1)
            // A whole word slightly smaller beats "hamb..." at the size asked
            // for. The label identifies the picture, and half a word identifies
            // nothing — least of all for a child who cannot yet read and is
            // matching shapes.
            .minimumScaleFactor(0.6)
            .foregroundStyle(TileColorResolver.label(on: accent))
            .frame(maxWidth: .infinity)
            .padding(.vertical, GridLayoutCalculator.labelBandPadding)
            .background(accent)
    }

    @ViewBuilder
    private var tileFace: some View {
        if look == .square {
            squareTile
        } else {
            VStack(spacing: 0) {
                // Full-bleed square image card, then the word on the same color.
                tileCard
                labelBand
            }
        }
    }

    // MARK: - Square tile

    /// How this tile holds its picture: the active set's layout, except that a
    /// cut-out set falls back to the card for a picture that was not cut — a
    /// photo, an older variant, a tile the review left whole. An opaque picture
    /// straight on the tint would be a white square.
    private var layout: TileLayout {
        let declared = resolver.activeSet.tileLayout
        if declared == .cutOut && !resolver.drawsCutOut(tile.bundleImage) { return .card }
        return declared
    }

    /// The ground: a light tint of the tile's colour, or the full colour under
    /// High Contrast's black plate, whose white figures a tint would wash out.
    private var squareGround: Color {
        layout == .plate ? accent : TileColorResolver.tint(accent, mix: TileLayout.tintMix)
    }

    /// The word's colour on that ground. On a tint it is near-black whatever
    /// the colour, as on paper; on the full colour it is the usual contrast.
    private var squareInk: Color {
        layout == .plate ? TileColorResolver.label(on: accent) : Color(white: 0.1)
    }

    /// The ring a pressed folder shows. On the full colour of a plate tile the
    /// colour itself would not show, so it is white there.
    private var pressRing: Color {
        look == .square && layout == .plate ? .white : accent
    }

    /// One square: the picture, then the word in a band across the bottom.
    ///
    /// The three layouts differ only in what holds the picture (see
    /// `TileLayout`); the square, the band and the badge are the same for all
    /// of them, so a board mixing a cut-out and a fallback card still reads as
    /// one board.
    private var squareTile: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let band = GridLayoutCalculator.squareLabelHeight(forFont: labelFontSize)
            let m = TileLayout.margin
            let art = max(1, side - band - m)
            ZStack(alignment: .top) {
                squareGround
                squarePicture(size: art)
                    .frame(width: art, height: art)
                    .overlay(alignment: .bottomTrailing) { linkBadge }
                    .padding(.top, m)
                Text(tile.displayName)
                    .font(.system(size: labelFontSize, weight: layout == .plate ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(squareInk)
                    .padding(.horizontal, 3)
                    .frame(width: side, height: band)
                    .offset(y: m + art)
            }
            // The way here frames the whole tile, its border, rather than the
            // picture inside it (Mark 2026-10-27): on a 2pt-gap board of colour
            // a picture-sized frame read as part of the art.
            .modifier(WayMarkOverlay(mark: wayMark, radius: TileLayout.cornerRadius, inset: 0, width: 4))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func squarePicture(size: CGFloat) -> some View {
        switch layout {
        case .cutOut:
            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass, drawsOnTint: true)
        case .card:
            // A white card a point above the tint: no frame, only its shadow,
            // so a picture with white at its edges still has an edge.
            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.2), radius: 3.5, y: 3)
                )
        case .plate:
            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .padding(1.5)
                .background(Color.black)
                .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private var linkBadge: some View {
        if isNavigation && wayMark != .here {
            // Against what is behind it. On a square tile that is the tint, not
            // the colour: a folder's light-blue badge on its own light-blue tint
            // all but vanished on Classic's cut-out art, while the same badge on
            // Playful 3D's white card read fine.
            let badge = TileColorResolver.marker(on: look == .square ? squareGround : accent)
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(TileColorResolver.label(on: badge), badge)
                .padding(2)
        }
    }

    /// The color a tile carries: its part of speech, or blue for a nav tile,
    /// which is wayfinding rather than vocabulary.
    private var accent: Color {
        isNavigation
            ? TileColorResolver.linkColor(slotRawValue: linkColor, isAudible: isAudible)
            : TileColorResolver.color(for: tile)
    }

    /// The card is a colored card with the picture on a white plate inside it —
    /// the shape every published AAC board uses, and the shape our own printed
    /// sheets already used while the screen did not.
    ///
    /// **The color is the card, not its edge.** This used to be a 3pt border at
    /// 0.6 alpha over a 0.12 fill, and side by side with cboard on identical
    /// tiles the board read monochrome from three feet away: a hairline around a
    /// white card against a card that *is* the color. Color only teaches if it
    /// is legible at the distance a board is actually used from.
    ///
    /// **The card does not follow dark mode, deliberately.** Fitzgerald colors
    /// are taught as constants — the green ones are doing words, wherever and
    /// whenever you look at the board. A board is a physical object, and the
    /// chrome around it going dark while the board itself stays put is both
    /// truer and bolder than any appearance-aware tint could be at these sizes.
    /// Everything here is therefore a literal color, never a semantic one.
    @ViewBuilder
    private var tileCard: some View {
        ZStack(alignment: .bottomTrailing) {
            accent
                .aspectRatio(1, contentMode: .fit)

            // The plate. Art is drawn on white and ships without alpha, so this
            // is mostly belt-and-braces — but it keeps the corners clean and
            // gives caregiver photos and any future transparent art the same
            // ground as everything else.
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .aspectRatio(1, contentMode: .fit)
                .padding(7)

            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .aspectRatio(1, contentMode: .fit)
                .padding(9)

            if isNavigation && wayMark != .here {
                // Drawn against the tile's own color rather than in a fixed
                // blue. See `TileColorResolver.marker(on:)`: this badge stopped
                // being decoration the moment folders stopped all being blue.
                let badge = TileColorResolver.marker(on: accent)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(TileColorResolver.label(on: badge), badge)
                    .padding(4)
            }
        }
        .modifier(WayMarkOverlay(mark: wayMark))
        // No clip, no ring, no shadow here any more — the enclosing VStack owns
        // all of it, so the rounding and the glow follow the outside of the
        // whole tile instead of cutting between the picture and the word.
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
    TileView(tile: tile, link: "", isAudible: true) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Nav tile") {
    let tile = TileModel(key: "food", wordClass: "navigation")
    TileView(tile: tile, link: "food", isAudible: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Selected tile") {
    let tile = TileModel(key: "happy", wordClass: "feeling")
    TileView(tile: tile, link: "", isAudible: true) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}
