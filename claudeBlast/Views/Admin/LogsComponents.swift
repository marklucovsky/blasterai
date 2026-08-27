// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LogsComponents.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

// MARK: - Promoted Tiles Detail

// MARK: - Cache Detail

struct CacheDetailView: View {
    let entries: [SentenceCache]
    let onDelete: (IndexSet) -> Void
    let onFlush: () -> Void

    var body: some View {
        List {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.cacheKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.sentence)
                        .font(.subheadline)
                    Text("Hits: \(entry.hitCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .onDelete(perform: onDelete)
        }
        .navigationTitle("Sentence Cache (\(entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Flush All", role: .destructive) {
                    onFlush()
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Cache Stats Box

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
