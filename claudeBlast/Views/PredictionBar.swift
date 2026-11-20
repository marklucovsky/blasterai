// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PredictionBar.swift
//  claudeBlast
//
//  The letter keyboards' top row (PR F): the words `WordPredictor` offers,
//  a picture chip for a word we have art for and a text chip for the rest,
//  as Avaz draws them. A tap types the word. More than fit, an arrow pages.
//

import SwiftUI

struct PredictionBar: View {
    let predictions: [WordPredictor.Prediction]
    let height: CGFloat
    let spacing: CGFloat
    let onChoose: (String) -> Void

    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            let arrow = height * 0.7
            let chip = height * 1.05
            let fit = max(1, Int((geo.size.width - arrow - spacing + spacing) / (chip + spacing)))
            let pages = max(1, Int(ceil(Double(predictions.count) / Double(fit))))
            let shown = Array(predictions.dropFirst((page % pages) * fit).prefix(fit))
            HStack(spacing: spacing) {
                ForEach(shown) { p in
                    PredictionChip(prediction: p, height: height) { onChoose(p.word) }
                        .frame(width: chip, height: height)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if pages > 1 {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { page = (page + 1) % pages } } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: height * 0.3, weight: .semibold))
                            .frame(width: arrow, height: height)
                            .background(RoundedRectangle(cornerRadius: TileLayout.cornerRadius,
                                                         style: .continuous).fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More words")
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        // New letters, new words: back to the first page.
        .onChange(of: predictions.map(\.id)) { _, _ in page = 0 }
    }
}

/// One word on offer: its picture and word, or its word alone.
private struct PredictionChip: View {
    let prediction: WordPredictor.Prediction
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let key = prediction.tileKey {
                    TileImageView(key: key, wordClass: prediction.wordClass ?? "")
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxHeight: height * 0.62)
                }
                Text(prediction.word)
                    .font(.system(size: height * (prediction.tileKey == nil ? 0.24 : 0.17),
                                  weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.primary)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prediction.word)
    }
}
