// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileFace.swift
//  claudeBlast
//
//  What a tile looks like, wherever it is drawn: the board, the preview, the
//  page editor, the scene builder and coverage all draw this one face, so a
//  caregiver arranging a page sees the tile the child will see.
//

import SwiftUI

/// Where a tile's link sits on the path to the page showing.
///
/// A folder page keeps its own tile in the cell its parent shows it in, and that
/// tile is "here": a child who cannot read sees the tile they just pressed,
/// where they pressed it. The row-1 folder the path started from is "on the
/// way". Both carry a near-black bar along the bottom edge, the indicator under
/// a selected tab. "Here" also veils its picture and drops its folder badge: it
/// is a label, not a button, and it should look it next to the live folders.
///
/// The bar replaced a black-and-yellow hazard ring (Mark 2026-10-27, from six
/// mocks): the ring was legible and read as a warning on a board a child spends
/// all day on. The bar is the label's own ink, so it survives High Contrast and
/// colour blindness without adding a colour that means nothing else.
enum WayMark {
    case here, onTheWay

    static let bar: CGFloat = 5
    /// The label's near-black on a light board; near-white in dark mode, where
    /// a dark bar at the tile's foot merged with the dark gap under it and read
    /// as a tile cut short.
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.1, alpha: 1)
    })
    static let veil: Double = 0.45
}

struct TileFace: View {
    /// The picture's key (`TileModel.bundleImage`).
    let imageKey: String
    let label: String
    let wordClass: String
    /// Its part of speech, or its link's colour. See `init(tile:…)`.
    let accent: Color
    var isLink: Bool = false
    var labelFontSize: CGFloat = 11
    var wayMark: WayMark? = nil
    /// A picture not yet in the store: a generated scene's preview art.
    var imageData: Data? = nil
    /// This look rather than the setting. Previews and tests only.
    var look: TileLook? = nil

    @AppStorage(AppSettingsKey.tileLook) private var lookRaw: String = TileLook.square.rawValue
    @Environment(TileImageResolver.self) private var resolver
    @Environment(\.tileAspect) private var tileAspect

    /// A tile as a page holds it, coloured the way the board colours it: part
    /// of speech for a word, the link's own slot for a folder.
    init(tile: TileModel?, key: String, link: String = "", linkColor: String? = nil,
         isAudible: Bool = true, labelFontSize: CGFloat = 11, wayMark: WayMark? = nil) {
        self.imageKey = tile?.bundleImage ?? key
        self.label = tile?.displayName ?? key
        self.wordClass = tile?.wordClass ?? ""
        self.isLink = !link.isEmpty
        self.accent = link.isEmpty
            ? TileColorResolver.color(for: tile)
            : TileColorResolver.linkColor(slotRawValue: linkColor, isAudible: isAudible)
        self.labelFontSize = labelFontSize
        self.wayMark = wayMark
    }

    init(imageKey: String, label: String, wordClass: String, accent: Color, isLink: Bool = false,
         labelFontSize: CGFloat = 11, wayMark: WayMark? = nil, imageData: Data? = nil, look: TileLook? = nil) {
        self.imageKey = imageKey
        self.label = label
        self.wordClass = wordClass
        self.accent = accent
        self.isLink = isLink
        self.labelFontSize = labelFontSize
        self.wayMark = wayMark
        self.imageData = imageData
        self.look = look
    }

    var resolvedLook: TileLook { look ?? TileLook(rawValue: lookRaw) ?? .square }

    /// The corner every overlay on a tile has to follow.
    static func radius(_ look: TileLook) -> CGFloat {
        look == .square ? TileLayout.cornerRadius : 10
    }

    private var radius: CGFloat { Self.radius(resolvedLook) }
    private var showsBadge: Bool { isLink && wayMark != .here }
    private var pictureOpacity: Double { wayMark == .here ? WayMark.veil : 1 }

    var body: some View {
        Group {
            if resolvedLook == .square { squareTile } else { classicTile }
        }
        .overlay(alignment: .bottom) {
            if wayMark != nil {
                WayMark.ink.frame(height: WayMark.bar).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    // MARK: - Square

    /// How this tile holds its picture: the active set's layout, except that a
    /// cut-out set falls back to the card for a picture that was not cut — a
    /// photo, an older variant, a tile the review left whole, a generated
    /// preview. An opaque picture straight on the tint would be a white square.
    private var layout: TileLayout {
        let declared = resolver.activeSet.tileLayout
        if declared == .cutOut && (imageData != nil || !resolver.drawsCutOut(imageKey)) { return .card }
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
            // A wide tile keeps a square picture, centred, as tall as fits.
            let art = max(1, min(side - band - m, geo.size.height - band - m))
            ZStack(alignment: .top) {
                squareGround
                squarePicture
                    .opacity(pictureOpacity)
                    .frame(width: art, height: art)
                    .overlay(alignment: .bottomTrailing) {
                        if !isWide { badge(on: squareGround, padding: 2) }
                    }
                    .padding(.top, m)
                // Lifted clear of the way bar; the picture's own margin takes
                // the overlap.
                let lift: CGFloat = wayMark == nil ? 0 : WayMark.bar - 1
                if Self.labelOverflows(label, fontSize: labelFontSize, width: side) {
                    // A phrase ("Wanna do something different?") that one
                    // line would shrink past reading: two lines on the tile's
                    // own ground, rising over the foot of the picture. A size down,
                    // so the plate covers as little of the picture as it can.
                    let small = (labelFontSize * 0.8).rounded()
                    let plate = 2 * GridLayoutCalculator.squareLabelHeight(forFont: small)
                    Text(label)
                        .font(.system(size: small, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(squareInk)
                        .padding(.horizontal, 3)
                        .frame(width: side, height: plate)
                        .background(squareGround)
                        .offset(y: m + art + band - plate - lift)
                } else {
                    Text(label)
                        .font(.system(size: labelFontSize, weight: layout == .plate ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(squareInk)
                        .padding(.horizontal, 3)
                        .frame(width: side, height: band)
                        .offset(y: m + art - lift)
                }
            }
            // A wide tile has room beside its picture: the marker goes in the
            // corner, off the picture, where it sat over the middle of it
            // (Mark 2026-10-29).
            .overlay(alignment: .topTrailing) {
                if isWide { badge(on: squareGround, padding: 3) }
            }
        }
        .aspectRatio(tileAspect, contentMode: .fit)
    }

    /// True when one line would clip `label` even at the band's smallest scale
    /// (0.6), so the square tile gives it two lines instead.
    static func labelOverflows(_ label: String, fontSize: CGFloat, width: CGFloat) -> Bool {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let natural = (label as NSString).size(withAttributes: [.font: font]).width
        return natural * 0.6 > width - 6
    }

    /// Wider than tall: a phone on its side (`tileAspect`).
    private var isWide: Bool { tileAspect > 1.05 }

    @ViewBuilder
    private var squarePicture: some View {
        switch layout {
        case .cutOut:
            TileImageView(key: imageKey, wordClass: wordClass, drawsOnTint: true)
        case .card:
            // A white card a point above the tint: no frame, only its shadow,
            // so a picture with white at its edges still has an edge.
            picture
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.2), radius: 3.5, y: 3)
                )
        case .plate:
            picture
                .padding(1.5)
                .background(Color.black)
                .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let imageData, let ui = UIImage(data: imageData) {
            Image(uiImage: ui).resizable().scaledToFit().background(Color.white)
        } else {
            TileImageView(key: imageKey, wordClass: wordClass)
        }
    }

    // MARK: - Classic

    /// The card is a colored card with the picture on a white plate inside it —
    /// the shape every published AAC board uses, and the shape our own printed
    /// sheets already used while the screen did not — and the word on the same
    /// colour underneath, so the tile is one object rather than a card with a
    /// caption under it.
    ///
    /// **The card does not follow dark mode, deliberately.** Fitzgerald colors
    /// are taught as constants — the green ones are doing words, wherever and
    /// whenever you look at the board. Everything here is therefore a literal
    /// color, never a semantic one.
    private var classicTile: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                accent.aspectRatio(1, contentMode: .fit)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(7)
                    .opacity(pictureOpacity)
                picture
                    .aspectRatio(1, contentMode: .fit)
                    .padding(9)
                    .opacity(pictureOpacity)
                // Drawn against the tile's own color rather than in a fixed
                // blue. See `TileColorResolver.marker(on:)`.
                badge(on: accent, padding: 4)
            }
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
                .lineLimit(1)
                // A whole word slightly smaller beats "hamb..." at the size
                // asked for: half a word identifies nothing, least of all for a
                // child matching shapes.
                .minimumScaleFactor(0.6)
                .foregroundStyle(TileColorResolver.label(on: accent))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 3)
                .padding(.vertical, GridLayoutCalculator.labelBandPadding)
                .offset(y: wayMark == nil ? 0 : -2)
                .background(accent)
        }
    }

    /// The folder mark, against whatever is behind it. On a square tile that
    /// is the tint, not the colour: a folder's light-blue badge on its own
    /// light-blue tint all but vanished on Classic's cut-out art.
    @ViewBuilder
    private func badge(on ground: Color, padding: CGFloat) -> some View {
        if showsBadge {
            let badge = TileColorResolver.marker(on: ground)
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(TileColorResolver.label(on: badge), badge)
                .padding(padding)
        }
    }
}

/// A tile in a generated scene's or page's preview: a word that may not be in
/// the store yet, with art that may not be either. Drawn with the board's own
/// face; `isNew` flags a proposed word, which shows its letter placeholder
/// until it has art.
struct GeneratedTileCell: View {
    let key: String
    let displayName: String
    let wordClass: String
    let link: String
    var linkColor: String? = nil
    var isAudible: Bool = false
    var isNew: Bool = false
    var imageData: Data? = nil

    var body: some View {
        TileFace(imageKey: key, label: displayName, wordClass: wordClass,
                 accent: link.isEmpty
                    ? TileColorResolver.color(forWordClass: wordClass)
                    : TileColorResolver.linkColor(slotRawValue: linkColor, isAudible: isAudible),
                 isLink: !link.isEmpty, labelFontSize: 9, imageData: imageData)
            .overlay(alignment: .topLeading) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.purple))
                        .padding(3)
                }
            }
    }
}

#Preview("Long phrases") {
    HStack(spacing: 2) {
        TileFace(imageKey: "different", label: "Wanna do something different?", wordClass: "social", accent: .pink)
        TileFace(imageKey: "then", label: "What's going to happen next?", wordClass: "social", accent: .pink)
        TileFace(imageKey: "big", label: "That's a big one!", wordClass: "social", accent: .pink)
        TileFace(imageKey: "i_love_it", label: "I love it", wordClass: "social", accent: .pink)
    }
    .frame(width: 400)
    .previewEnvironment()
}

#Preview("Way marks") {
    HStack(spacing: 2) {
        TileFace(imageKey: "places", label: "places", wordClass: "navigation",
                 accent: .orange, isLink: true, wayMark: .onTheWay)
        TileFace(imageKey: "folder_house", label: "House", wordClass: "navigation",
                 accent: .orange, isLink: true, wayMark: .here)
        TileFace(imageKey: "eat", label: "eat", wordClass: "actions", accent: .green)
    }
    .frame(width: 270)
    .previewEnvironment()
}
