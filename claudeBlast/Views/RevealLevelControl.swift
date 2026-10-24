// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  RevealLevelControl.swift
//  claudeBlast
//
//  The board's level dial: − L3 + and how many words a child at that level
//  can press. One control everywhere a caregiver changes the level — the
//  Caregiver Menu, Admin › Now, the scene editor — so it reads the same in
//  each and there is one place to get it right.
//

import SwiftUI
import SwiftData

struct RevealLevelControl: View {
    let scene: BlasterScene
    var compact = false

    @Environment(\.modelContext) private var modelContext
    /// BlasterAI 60: a board that links into it steps its pages too.
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]

    private var levels: BoardLevels { BoardLevels(scene: scene, system: systemScenes.first) }

    var body: some View {
        let levels = levels
        if let level = levels.level {
            HStack(spacing: 12) {
                stepButton("minus", enabled: level > 1) { set(level - 1) }
                VStack(spacing: 1) {
                    Text("Level \(level) of \(levels.count)")
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .monospacedDigit()
                    let count = levels.visibleTileCount(atLevel: level)
                    Text("\(count) visible word\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(minWidth: 120)
                stepButton("plus", enabled: level < levels.count) { set(level + 1) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Board level \(level) of \(levels.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment where level < levels.count: set(level + 1)
                case .decrement where level > 1: set(level - 1)
                default: break
                }
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
    }

    /// Writes the synced dial. Every device on this account follows it.
    private func set(_ level: Int) {
        levels.setLevel(level)
        try? modelContext.save()
    }
}
