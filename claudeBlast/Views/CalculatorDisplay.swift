// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CalculatorDisplay.swift
//  claudeBlast
//
//  The calculator keyboard's display (Mark, 2026-11-20): dark, as a
//  calculator's is, taking all the height its keys leave — most of a phone in
//  portrait. It shows the sum being typed, large; the math helper's working
//  in place as `=` works it out (the pair being worked yellow, the number it
//  made green); then the answer. With nothing typed, the last sum, dimmed.
//

import SwiftUI

struct CalculatorDisplay: View {
    @Environment(SentenceEngine.self) private var engine
    let walkthrough: MathWalkthrough

    private static let lcd = Color(white: 0.11)
    private static let ink = Color.white
    private static let yellow = Color(red: 1.0, green: 0.84, blue: 0.4)

    var body: some View {
        GeometryReader { geo in
            let big = min(geo.size.height * 0.34, 72)
            VStack(alignment: .trailing, spacing: big * 0.15) {
                Spacer(minLength: 0)
                Text(context)
                    .font(.system(size: big * 0.4, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.ink.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                main(size: big)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
            .padding(.horizontal, big * 0.35)
            .padding(.vertical, big * 0.25)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
            .background {
                RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                    .fill(Self.lcd)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: walkthrough.display)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeechNormalizer.line(spoken))
    }

    /// The small line above: the sum being worked out, or the last one.
    private var context: String {
        switch walkthrough.display {
        case .working, .answer: return MathChipView.spaced(engine.typingQuestion)
        case .note: return MathChipView.spaced(engine.typingQuestion)
        case nil: return typed.isEmpty ? "" : (engine.lastSaidSum.map(MathChipView.spaced) ?? "")
        }
    }

    private var typed: String {
        engine.typingQuestion.trimmingCharacters(in: .whitespaces)
    }

    private var spoken: String {
        switch walkthrough.display {
        case .working(let frame): frame.tokens.joined(separator: " ")
        case .answer(let text, _), .note(let text): text
        case nil: typed.isEmpty ? (engine.lastSaidSum ?? "0") : typed
        }
    }

    @ViewBuilder
    private func main(size: CGFloat) -> some View {
        switch walkthrough.display {
        case .working(let frame):
            HStack(spacing: size * 0.08) {
                ForEach(Array(frame.tokens.enumerated()), id: \.offset) { i, token in
                    let plate: Color? = frame.highlight?.contains(i) == true ? Self.yellow
                        : frame.result == i ? Color.green.opacity(0.75) : nil
                    Text(token)
                        .font(.system(size: size * 0.8, weight: .semibold, design: .rounded))
                        .foregroundStyle(plate == nil ? Self.ink : Color.black)
                        .padding(.horizontal, size * 0.08)
                        .background {
                            if let plate { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(plate) }
                        }
                }
            }
        case .answer(let text, let correct):
            HStack(alignment: .top, spacing: size * 0.08) {
                // The star as an accent, not a second thing to read.
                if correct {
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.yellow)
                }
                Text(text).font(.system(size: size, weight: .bold, design: .rounded))
            }
            .foregroundStyle(correct ? Color.green : Color.orange)
        case .note(let text):
            Text(text)
                .font(.system(size: size * 0.55, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
        case nil:
            if typed.isEmpty {
                // The last sum, dimmed, or a calculator's 0.
                (engine.lastSaidSum.map(MathChipView.sumText) ?? Text("0"))
                    .font(.system(size: size, weight: .light, design: .rounded))
                    .foregroundStyle(Self.ink.opacity(engine.lastSaidSum == nil ? 0.9 : 0.55))
            } else {
                Text(MathChipView.spaced(typed))
                    .font(.system(size: size, weight: .light, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .monospacedDigit()
            }
        }
    }
}
