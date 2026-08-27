// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GlassSentencePopover.swift
//  claudeBlast
//
//  Caregiver-facing sentence overlay. Appears in compact-width layouts
//  when SentenceEngine surfaces a generated sentence, auto-dismisses after
//  a short window, and re-appears on replay through the engine's natural
//  canReplay false→true cycle. Big, legible text optimized for adult
//  reading at arm's length while a child holds the iPhone. Replay lives
//  on the tray's play button — the popover is read-only.
//
//  Visually: a glass card slides down from the top of the tile grid,
//  overlapping the top row of tiles so the Liquid Glass material has
//  colorful content to refract. A large circular glass dismiss button
//  sits in the top-right corner with a 44pt hit target.
//
//  Tapping anywhere on the popover dismisses it. It is read-only — there
//  is nothing under a tap to preserve — and it previously *swallowed*
//  every tap outside the × to stop them reaching the tiles below. On an
//  iPad that produced a full-width band of glass that ate input and had
//  exactly one 32pt exit, which reads as a stuck app rather than a
//  deliberate modal.
//

import SwiftUI

struct GlassSentencePopover: View {
    let sentence: String
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Text(sentence)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.leading, 20)
                    .padding(.trailing, 56)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))

                DismissButton(action: onDismiss)
                    .padding(6)
                    .accessibilityLabel("Dismiss")
            }
        }
        // Capped rather than edge-to-edge. The popover exists to make one
        // sentence big and legible; stretched across an iPad it becomes a
        // banner spanning the whole board for the sake of six words.
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 44pt-hit-target dismiss button. Visible chip is a 32pt circle with a
/// solid material fill + dark stroke so it reads as an obvious close
/// affordance against the glass card; tappable area extends to 44pt with
/// `contentShape(Rectangle())` so near-misses still register here
/// instead of leaking to the tile grid underneath.
private struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
