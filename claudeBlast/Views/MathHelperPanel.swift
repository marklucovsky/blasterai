// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MathHelperPanel.swift
//  claudeBlast
//
//  The numbers page's top row: the math helper's working, in one card that
//  changes in place. The sum shrinks a pair at a time — the pair being worked
//  out marked yellow, the number it made marked green — each step said as it
//  happens, then the answer with a star (Mark, 2026-11-20). The solving is
//  `MathHelper`; this paces it and draws it.
//

import SwiftUI

@Observable
@MainActor
final class MathWalkthrough {
    enum Display: Equatable {
        /// A step: the sum as it stands (`MathHelper.Frame`).
        case working(MathHelper.Frame)
        /// The answer, or the verdict on one.
        case answer(String, correct: Bool)
        /// Something the helper can't do, or a nudge.
        case note(String)
    }

    /// What the row shows; nil shows the hint.
    private(set) var display: Display?
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    /// Stop, and clear the row back to its hint.
    func cancel() {
        task?.cancel()
        task = nil
        display = nil
    }

    /// The `?` key, or Speak on a line with a `?` in it. `typing` is true
    /// for the key: its `?` goes on the line first.
    func ask(engine: SentenceEngine, typing: Bool) {
        cancel()
        let line = typing ? engine.typingQuestion + "?" : engine.typingQuestion
        if line.trimmingCharacters(in: .whitespaces) == "?" {
            show(note: "Type a sum, then ?", engine: engine)
            return
        }
        switch MathHelper.solve(line) {
        case .incomplete:
            // `3+?` on its way to `3+?=7`: the `?` is the number to find.
            if typing { engine.typeKey("?") }
        case .cannot(let reason):
            if typing { engine.typeKey("?", speaking: false) }
            show(note: reason.message, engine: engine)
        case .solved(let solution):
            if typing { engine.typeKey("?", speaking: false) }
            walk(solution, engine: engine)
        }
    }

    /// A said sum tapped in the message box: its working again, as when it
    /// was first worked out, without touching the line. A sum that adds up
    /// replays as worked out (`1+2+3=6` → `1 + 2 + 3`, …, ⭐ `= 6`); one that
    /// doesn't replays as checked ("Not quite: 2 + 2 = 4"). Anything the
    /// helper can't work is just said.
    func replay(_ sum: String, engine: SentenceEngine) {
        cancel()
        var solution: MathHelper.Solution?
        if let mark = sum.firstIndex(of: MathHelper.correction) {
            // An answer that was put right replays its whole check: the
            // working, then "Not quite".
            if case .solved(let checked) = MathHelper.solve(String(sum[..<mark]) + "?") {
                solution = checked
            }
        } else if let eq = sum.firstIndex(of: "="),
           case .solved(let worked) = MathHelper.solve(String(sum[..<eq]) + "?"),
           Self.sameSum(worked.summary, sum) {
            solution = worked
        } else if case .solved(let checked) = MathHelper.solve(sum + "?") {
            solution = checked
        }
        guard let solution else { engine.speakMath(sum); return }
        walk(solution, engine: engine, filling: false)
    }

    private func show(note: String, engine: SentenceEngine) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { display = .note(note) }
        engine.speakMath(note)
    }

    /// Each step in place, said before the next; then the answer goes in the
    /// line and the whole sum is said.
    private func walk(_ solution: MathHelper.Solution, engine: SentenceEngine, filling: Bool = true) {
        // A one-step sum (`3×4=?`) has no working to show: its one step is
        // its answer, and showing both said it twice (Mark, 2026-11-20).
        let oneStep = solution.steps.count == 1 && Self.sameSum(solution.steps[0], solution.summary)
        // An experiment setting: the answer alone, no working.
        let showWorking = UserDefaults.standard.object(forKey: AppSettingsKey.keyboardShowWorking) as? Bool ?? true
        let steps = oneStep || !showWorking ? [] : Array(zip(solution.frames, solution.steps))
        task = Task { [weak self] in
            for (frame, line) in steps {
                guard let self, !Task.isCancelled else { return }
                // First the sum shrinks, the number just made in green; then
                // the next pair lights up.
                if frame.result != nil {
                    let collapsed = MathHelper.Frame(tokens: frame.tokens, highlight: nil, result: frame.result)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { display = .working(collapsed) }
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { display = .working(frame) }
                engine.speakMath(line)
                await Self.waitForSpeech(engine)
            }
            guard let self, !Task.isCancelled else { return }
            let correct = if case .check(correct: false) = solution.kind { false } else { true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                display = .answer(solution.summary, correct: correct)
            }
            if filling { engine.fillTypedQuestions(solution.edits) }
            engine.speakMath(solution.summary)
            // With sums as cards, the answer then goes up into the message
            // box, where it is the newest card, and the row is free again.
            if SumStyle.current == .cards {
                await Self.waitForSpeech(engine)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { display = nil }
            }
            task = nil
        }
    }

    /// The same sum, spacing aside: `3 × 4 = 12` and `3 × 4 = 12`.
    private static func sameSum(_ a: String, _ b: String) -> Bool {
        a.filter { !$0.isWhitespace } == b.filter { !$0.isWhitespace }
    }

    /// Long enough to hear a step: until the voice is done, and at least a
    /// beat with the sound off.
    private static func waitForSpeech(_ engine: SentenceEngine) async {
        try? await Task.sleep(for: .milliseconds(400))
        var waited = 0
        while engine.isSpeaking, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(waited == 0 ? 900 : 350))
    }
}

/// The row itself: one card, changing in place; with nothing to show, a
/// faint example of what to type.
struct MathHelperPanel: View {
    let walkthrough: MathWalkthrough
    let height: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack {
            switch walkthrough.display {
            case nil:
                hint
            case .working(let frame):
                WorkingCard(frame: frame, height: height)
            case .answer(let text, let correct):
                AnswerCard(text: text, style: correct ? .answer : .wrong, height: height)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                        removal: .offset(y: -height * 1.5).combined(with: .scale(scale: 0.5))
                            .combined(with: .opacity)))
            case .note(let text):
                AnswerCard(text: text, style: .note, height: height)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
    }

    private var hint: some View {
        HStack(spacing: height * 0.15) {
            Text("2 + 3 = ?")
                .font(.system(size: height * 0.3, weight: .medium, design: .rounded))
            Text("then press ?")
                .font(.system(size: height * 0.18))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, height * 0.3)
        .frame(height: height)
        .overlay {
            RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .accessibilityLabel("Math helper. Type a sum, then press the question mark.")
    }
}

private let workingYellow = Color(red: 1.0, green: 0.84, blue: 0.4)

/// The sum as it stands: its pieces in a row, the pair being worked out on a
/// yellow plate, the number the last step made on a green one.
private struct WorkingCard: View {
    let frame: MathHelper.Frame
    let height: CGFloat

    var body: some View {
        HStack(spacing: height * 0.06) {
            ForEach(Array(frame.tokens.enumerated()), id: \.offset) { i, token in
                Text(token)
                    .font(.system(size: height * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(plate(i) == nil ? Color.primary : Color.black)
                    .lineLimit(1)
                    .padding(.horizontal, height * 0.07)
                    .frame(height: height * 0.72)
                    .background {
                        if let plate = plate(i) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(plate)
                        }
                    }
            }
        }
        .minimumScaleFactor(0.5)
        .padding(.horizontal, height * 0.18)
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                .fill(Color(.systemGray6))
                .overlay {
                    RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeechNormalizer.line(frame.tokens.joined(separator: " ")))
    }

    private func plate(_ i: Int) -> Color? {
        if frame.highlight?.contains(i) == true { return workingYellow }
        if frame.result == i { return Color.green.opacity(0.45) }
        return nil
    }
}

/// The last card: the answer with a star, a "not quite" in orange, or a note.
private struct AnswerCard: View {
    enum Style { case answer, wrong, note }
    let text: String
    let style: Style
    let height: CGFloat

    private var fill: Color {
        switch style {
        case .answer: Color.green.opacity(0.35)
        case .wrong: Color.orange.opacity(0.35)
        case .note: Color(.systemGray6)
        }
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        .font(.system(size: height * (style == .note ? 0.3 : 0.38),
                      weight: style == .note ? .medium : .bold, design: .rounded))
        .padding(.horizontal, height * 0.25)
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .overlay(alignment: .topLeading) {
            if style == .answer { StarAccent(size: height * 0.26) }
        }
        .accessibilityLabel(SpeechNormalizer.line(text))
    }
}

/// The right-answer star: a small accent on the card's corner, not a
/// second thing to read (Mark, 2026-11-20).
struct StarAccent: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size))
            .foregroundStyle(.yellow)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .offset(x: -size * 0.3, y: -size * 0.3)
            .accessibilityHidden(true)
    }
}

/// A typed sum in the message box. Two looks, an experiment setting (Mark,
/// 2026-11-20, `SumStyle`):
///
/// - **Cards:** one card per sum, as the helper's answer card is. The newest
///   sum said is green with a star; older ones are grey and, by default,
///   smaller, so the box stays calm while the action is on the keys.
/// - **Keys:** a plate per character, like the keys that typed it.
///
/// Either way a sum still being typed is red, and one typed but not yet said
/// is purple-edged, like the `?` key.
struct MathChipView: View {
    enum Style { case fresh, spoken, latest, draft }
    let text: String
    let height: CGFloat
    var style: Style = .fresh

    @AppStorage(AppSettingsKey.keyboardSumStyle) private var sumStyle = SumStyle.cards.rawValue
    @AppStorage(AppSettingsKey.keyboardShrinkOldSums) private var shrinkOld = true

    private static let purple = Color(red: 0.62, green: 0.55, blue: 0.98)

    /// The sum with room round its signs: `1+2=3` reads `1 + 2 = 3`.
    static func spaced(_ text: String) -> String {
        var out = ""
        for ch in text {
            if "+-\u{2212}×÷*=<>→".contains(ch) { out += " \(ch) " } else { out.append(ch) }
        }
        return out.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// How wide it draws, for a tray measuring its room.
    static func width(of text: String, height: CGFloat) -> CGFloat {
        if SumStyle.current == .cards {
            let font = UIFont.systemFont(ofSize: height * 0.4, weight: .bold)
            let measured = (spaced(text) as NSString).size(withAttributes: [.font: font]).width
            return ceil(measured) + height * 0.44 + height * 0.1   // padding + the star's overhang
        }
        let n = CGFloat(text.count)
        return n * glyphWidth(height) + max(0, n - 1) * 2
    }

    private static func glyphWidth(_ height: CGFloat) -> CGFloat { height * 0.5 }

    var body: some View {
        Group {
            if sumStyle == SumStyle.cards.rawValue { card } else { keys }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeechNormalizer.line(text))
    }

    // MARK: Cards

    private var card: some View {
        let older = style == .spoken
        let scale: CGFloat = older && shrinkOld ? 0.78 : 1
        return cardText
            .lineLimit(1)
            .fixedSize()
        .font(.system(size: height * 0.4 * scale, weight: style == .latest ? .bold : .semibold,
                      design: .rounded))
        .foregroundStyle(style == .draft ? Color.red : older ? Color.secondary : Color.primary)
        .padding(.horizontal, height * 0.22 * scale)
        .frame(height: height * 0.75 * scale)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(cardEdge, lineWidth: style == .spoken ? 1 : 1.5)
                }
        }
        .overlay(alignment: .topLeading) {
            if style == .latest, !isCorrected { StarAccent(size: height * 0.24) }
        }
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    /// An answer the helper put right (`5+5=9→10`, `MathHelper.correction`).
    private var isCorrected: Bool { text.contains(MathHelper.correction) }

    /// The card's words. A corrected answer shows what was typed with the
    /// wrong part struck through in red, then the right answer in green:
    /// `5 + 5 = 9̶ 10`, or `3 > 5̶` `3 < 5` for a sum put right whole.
    private var cardText: Text { Self.sumText(text) }

    /// A sum as text, with a correction drawn: shared by the card and the
    /// calculator's display.
    static func sumText(_ text: String) -> Text {
        guard let mark = text.firstIndex(of: MathHelper.correction) else {
            return Text(spaced(text))
        }
        let typed = String(text[..<mark])
        let fix = String(text[text.index(after: mark)...])
        let right = Text("  " + spaced(fix)).foregroundStyle(Color.green).bold()
        let fixIsNumber = !fix.contains { "=<>".contains($0) }
        if fixIsNumber, let eq = typed.lastIndex(of: "=") {
            let before = Text(spaced(String(typed[...eq])) + " ")
            let wrong = Text(String(typed[typed.index(after: eq)...]))
                .foregroundStyle(Color.red).strikethrough(true, color: .red)
            return before + wrong + right
        }
        return Text(spaced(typed)).foregroundStyle(Color.red).strikethrough(true, color: .red) + right
    }

    private var cardFill: Color {
        if isCorrected, style == .latest { return Color.orange.opacity(0.2) }
        return switch style {
        case .latest: Color.green.opacity(0.35)
        case .spoken: Color(.systemGray5)
        case .fresh, .draft: Color(.systemGray6)
        }
    }

    private var cardEdge: Color {
        if isCorrected, style == .latest { return Color.orange.opacity(0.7) }
        return switch style {
        case .latest: Color.green.opacity(0.6)
        case .spoken: Color.primary.opacity(0.1)
        case .fresh: Self.purple
        case .draft: Color.red
        }
    }

    // MARK: Keys

    private var keyEdge: Color {
        switch style {
        case .fresh: Self.purple
        case .spoken, .latest: Color.primary.opacity(0.2)
        case .draft: Color.red
        }
    }

    private var keys: some View {
        HStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: height * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(style == .draft ? Color.red : Color.primary)
                    .frame(width: Self.glyphWidth(height), height: height * 0.78)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemGray6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(keyEdge, lineWidth: style == .fresh || style == .draft ? 1.5 : 1)
                            }
                    }
            }
        }
        .opacity(style == .spoken || style == .latest ? 0.75 : 1)
    }
}

extension SpokenSums {
    /// How the sum word at `index` draws: the newest said sum, an older
    /// one, or one not yet said.
    func chipStyle(at index: Int) -> MathChipView.Style {
        index >= count ? .fresh : starts.last == index ? .latest : .spoken
    }
}
