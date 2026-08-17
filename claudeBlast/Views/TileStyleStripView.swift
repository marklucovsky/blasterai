// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileStyleStripView.swift
//  claudeBlast
//
//  A horizontal strip showing one tile's art across every selectable image set,
//  side by side, so a caregiver/therapist can compare how the word renders in
//  each style. Pure review: it reads `resolver.image(for:in:)` per set and never
//  changes the device's active set. A zoom button (or tapping a thumbnail) opens
//  a larger side-by-side comparison, and from there a single style can be blown
//  up full screen. Missing art shows a dashed placeholder.
//

import SwiftUI

struct TileStyleStripView: View {
    let tileKey: String
    let displayName: String
    let wordClass: String

    @Environment(TileImageResolver.self) private var resolver
    @State private var showComparison = false

    private var styles: [ImageSetID] { ImageSetCatalog.selectable.map(\.id) }

    var body: some View {
        let _ = resolver.revision   // re-render after art is (re)generated
        HStack(alignment: .top, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(styles) { set in
                        StyleThumb(tileKey: tileKey, set: set,
                                   isActive: set == resolver.activeSet, size: 56)
                            .onTapGesture { showComparison = true }
                    }
                }
                .padding(.vertical, 2)
            }

            Button { showComparison = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compare styles larger")
        }
        .sheet(isPresented: $showComparison) {
            TileArtComparisonView(tileKey: tileKey, displayName: displayName, wordClass: wordClass)
        }
    }
}

/// One thumbnail in the strip: the tile's art for `set`, or a dashed placeholder,
/// with the style name and an "active" accent.
private struct StyleThumb: View {
    let tileKey: String
    let set: ImageSetID
    var isActive: Bool
    var size: CGFloat

    @Environment(TileImageResolver.self) private var resolver

    var body: some View {
        let _ = resolver.revision
        VStack(spacing: 3) {
            Group {
                if let ui = resolver.image(for: tileKey, in: set) {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(width: size, height: size)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.tertiary)
                        .frame(width: size, height: size)
                        .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.tertiary))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
            )
            Text(set.shortName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .frame(width: max(size, 64))
    }
}

/// Full side-by-side comparison of a tile's art across all selectable styles,
/// larger than the strip. Tapping a style blows it up full screen.
struct TileArtComparisonView: View {
    let tileKey: String
    let displayName: String
    let wordClass: String

    @Environment(TileImageResolver.self) private var resolver
    @Environment(\.dismiss) private var dismiss
    @State private var zoomed: ImageSetID?

    private var styles: [ImageSetID] { ImageSetCatalog.selectable.map(\.id) }
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)]

    var body: some View {
        let _ = resolver.revision
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(styles) { set in
                        VStack(spacing: 6) {
                            styleCell(set)
                            HStack(spacing: 4) {
                                Text(set.displayName).font(.subheadline.weight(.medium))
                                if set == resolver.activeSet {
                                    Text("· active").font(.caption).foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .fullScreenCover(item: $zoomed) { set in
                ZoomedArtView(tileKey: tileKey, displayName: displayName, set: set)
            }
        }
    }

    @ViewBuilder
    private func styleCell(_ set: ImageSetID) -> some View {
        Group {
            if let ui = resolver.image(for: tileKey, in: set) {
                Image(uiImage: ui).resizable().scaledToFit()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { zoomed = set }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.tertiary)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text("No art").font(.caption)
                        }.foregroundStyle(.tertiary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(set == resolver.activeSet ? Color.accentColor : .clear, lineWidth: 3)
        )
    }
}

/// A single style blown up full screen, pinch-to-zoom, tap the ✕ to close.
private struct ZoomedArtView: View {
    let tileKey: String
    let displayName: String
    let set: ImageSetID

    @Environment(TileImageResolver.self) private var resolver
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let ui = resolver.image(for: tileKey, in: set) {
                Image(uiImage: ui).resizable().scaledToFit()
                    .padding()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = max(1, $0) }
                            .onEnded { _ in withAnimation { scale = min(max(scale, 1), 4) } }
                    )
                    .onTapGesture(count: 2) { withAnimation { scale = 1 } }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("No art in \(set.displayName)")
                }.foregroundStyle(.white.opacity(0.7))
            }

            VStack {
                HStack {
                    Text("\(displayName) · \(set.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}
