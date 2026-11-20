// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  KeyboardSurfaceView.swift
//  claudeBlast
//
//  A keyboard page's grid area: its keys, drawn to their own geometry
//  (`KeyboardLayout`), under the navigation bar and beside the rail like any
//  page. Keys type into the message box through the engine's Typing
//  extension; each is spoken as it is pressed.
//

import SwiftUI
import SwiftData

struct KeyboardSurfaceView: View {
    @Environment(SentenceEngine.self) private var engine
    @AppStorage(AppSettingsKey.keyboardHighlightVowels) private var highlightVowels = true
    @AppStorage(AppSettingsKey.keyboardHighlightSigns) private var highlightSigns = true
    @AppStorage(AppSettingsKey.keyboardMathHelper) private var mathHelperOn = true
    @AppStorage(AppSettingsKey.keyboardPrediction) private var predictionOn = true
    @AppStorage(AppSettingsKey.keyboardPredictionOrder) private var predictionOrder =
        WordPredictor.Order.alphabetical.rawValue
    @Environment(\.modelContext) private var modelContext
    /// The letter keyboards' predictions, built from the vocabulary and the
    /// utterance log when a letter keyboard opens.
    @State private var predictor = WordPredictor()

    let layout: KeyboardLayout
    /// The grid area this draws in, and the board's gaps.
    let size: CGSize
    let spacing: CGFloat
    /// Open another keyboard page, by its BlasterAI 60 page key.
    let onSwitch: (String) -> Void

    enum Shift { case off, once, locked }
    @State private var shift: Shift = .off
    @State private var lastShiftTap: Date = .distantPast
    /// The numbers page's math helper, in the top row.
    @State private var math = MathWalkthrough()
    /// This view, as the owner of the engine's `mathReplayHandler`.
    @State private var replayOwner = UUID()

    /// A grid this narrow (a phone in portrait) takes the compact layouts.
    private static let compactWidth: CGFloat = 500
    /// A key no taller than this many of its widths: past it, keys read as
    /// thin slats (Mark, 2026-11-20, phone portrait).
    private static let maxAspect: CGFloat = 1.45

    var body: some View {
        let compact = size.width < Self.compactWidth
        let rows = layout.rows(compact: compact)
        let across = layout.rowWidth(compact: compact)
        // The top row (helper or prediction) and the rows of keys. The
        // calculator's display takes more than a row: it is what is read.
        let rowCount = CGFloat(rows.count) + (layout == .calculator ? 1.6 : 1)
        // A key-width plus its gap is one step, so a key `w` wide spans `w`
        // steps less one gap, and every row — however many keys — ends on the
        // grid's right edge.
        let unit = (size.width - spacing * CGFloat(across - 1)) / CGFloat(across)
        // The calculator's keys are square, as a calculator's are, leaving
        // its display the height.
        let rowHeight = min((size.height - spacing * (rowCount.rounded(.up) - 1)) / rowCount,
                            unit * (layout == .calculator ? 0.95 : Self.maxAspect))
        // Letters sized to the key's narrower side, so tall keys don't get
        // giant letters.
        let fontBase = min(rowHeight, unit * 1.3)
        VStack(spacing: spacing) {
            if layout == .calculator {
                // The calculator's display takes all the height the keys leave.
                CalculatorDisplay(walkthrough: math)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: .infinity)
            } else {
                // Keys sit at the bottom, by the rail; any height to spare is above.
                Spacer(minLength: 0)
            }
            if layout == .calculator {
                EmptyView()
            } else if layout == .numbers, mathHelperOn {
                MathHelperPanel(walkthrough: math, height: rowHeight, spacing: spacing)
            } else if predictionOn, layout == .qwerty || layout == .abc {
                PredictionBar(predictions: predictor.predict(
                                  prefix: engine.typingDraft, after: engine.lastTypedLineWord,
                                  order: WordPredictor.Order(rawValue: predictionOrder) ?? .alphabetical),
                              height: rowHeight, spacing: spacing) { word in
                    math.cancel()
                    engine.choosePrediction(word)
                }
            } else {
                Color.clear.frame(height: rowHeight)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { key in
                        let width = unit * CGFloat(key.width) + spacing * CGFloat(key.width - 1)
                        KeyCap(key: key, label: label(for: key), tint: tint(for: key),
                               isOn: isOn(key), height: fontBase) { press(key) }
                            .frame(width: width, height: rowHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .task(id: layout) {
            guard layout == .qwerty || layout == .abc else { return }
            predictor = Self.buildPredictor(modelContext)
        }
        // A tap on a said sum replays its working here (`mathReplayHandler`).
        .task(id: replays) {
            if replays {
                let math = math, engine = engine
                engine.mathReplayOwner = replayOwner
                engine.mathReplayHandler = { [weak engine] sum in
                    guard let engine else { return }
                    math.replay(sum, engine: engine)
                }
            } else if engine.mathReplayOwner == replayOwner {
                engine.mathReplayHandler = nil
                engine.mathReplayOwner = nil
            }
        }
        .onDisappear {
            guard engine.mathReplayOwner == replayOwner else { return }
            engine.mathReplayHandler = nil
            engine.mathReplayOwner = nil
        }
        // Clear or Done empties the line: the working goes with it.
        .onChange(of: engine.typingLine.isEmpty) { _, empty in
            if empty { math.cancel() }
        }
    }

    /// Whether a tap on a said sum replays its working here: the numbers
    /// page and the calculator, with the helper on.
    private var replays: Bool {
        (layout == .calculator || layout == .numbers) && mathHelperOn
    }

    /// The vocabulary and the last few thousand utterances: enough history
    /// to rank by, small enough to build as the keyboard opens.
    private static func buildPredictor(_ context: ModelContext) -> WordPredictor {
        let tiles = (try? context.fetch(FetchDescriptor<TileModel>())) ?? []
        var recent = FetchDescriptor<LoggedUtterance>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recent.fetchLimit = 3000
        let history = ((try? context.fetch(recent)) ?? []).reversed().map(\.tileKeys)
        return WordPredictor(tiles: tiles, history: history)
    }

    // MARK: - Keys

    private func press(_ key: KeyboardKey) {
        // Typing on moves past the working; Speak and Shift leave it up.
        switch key.action {
        case .character, .backspace, .deleteWord, .space: math.cancel()
        default: break
        }
        switch key.action {
        case .character(let c):
            engine.typeKey(shift == .off ? c : c.uppercased())
            if shift == .once { shift = .off }
        case .shift:
            // A second tap soon after the first locks it, as on every keyboard.
            let now = Date()
            if shift == .once, now.timeIntervalSince(lastShiftTap) < 0.4 {
                shift = .locked
            } else {
                shift = shift == .off ? .once : .off
            }
            lastShiftTap = now
        case .backspace:
            engine.typeBackspace()
        case .deleteWord:
            engine.typeDeleteWord()
        case .space:
            engine.typeSpace()
        case .speakLine:
            // On the numbers page a line with a `?` in it is a question.
            if replays, engine.typingQuestion.contains("?") {
                math.ask(engine: engine, typing: false)
            } else {
                engine.typeSpeakLine()
            }
        case .mathHelp:
            // Off in Settings, `?` is just a key.
            if mathHelperOn { math.ask(engine: engine, typing: true) } else { engine.typeKey("?") }
        case .switchTo(let page, _):
            onSwitch(page)
        }
    }

    /// Key caps show what the key will type: capitals while Shift is on.
    private func label(for key: KeyboardKey) -> KeyCap.Label {
        switch key.action {
        case .character(let c):
            // The calculator's power keys read as they do on a calculator.
            .text(c == "²" ? "x²" : c == "^" ? "xʸ" : shift == .off ? c : c.uppercased())
        case .shift: .symbol(shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
        case .backspace: .symbol("delete.left")
        case .deleteWord: .text(layout == .calculator ? "C" : "delete word")
        case .space: .text("space")
        case .speakLine: .symbol("speaker.wave.2.fill")
        case .switchTo(_, let label): .text(label)
        case .mathHelp: .text("?")
        }
    }

    private func tint(for key: KeyboardKey) -> KeyCap.Tint {
        switch key.action {
        case .character(let c):
            // The calculator's left column and brackets: its function keys.
            layout == .calculator && "()%²√^".contains(c) ? .function
                : key.isVowel && highlightVowels ? .vowel : key.isSign && highlightSigns ? .sign : .letter
        case .speakLine: .speak
        case .mathHelp: mathHelperOn ? .help : .letter
        default: .function
        }
    }

    private func isOn(_ key: KeyboardKey) -> Bool {
        key.action == .shift && shift != .off
    }
}

/// One key: a plate and its label, pressed with the touch.
private struct KeyCap: View {
    enum Label { case text(String), symbol(String) }
    enum Tint { case letter, vowel, sign, function, speak, help }

    let key: KeyboardKey
    let label: Label
    let tint: Tint
    let isOn: Bool
    let height: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    private var fill: Color {
        if isOn { return Color.accentColor }
        switch tint {
        // Off the page's own white, so a key reads as a key.
        case .letter: return Color(.systemGray6)
        case .vowel: return Color(red: 1.0, green: 0.88, blue: 0.55)
        // The vowels' counterpart on the numbers page: a pale blue.
        case .sign: return Color(red: 0.74, green: 0.86, blue: 1.0)
        case .function: return Color(.systemGray4)
        case .speak: return Color.green.opacity(0.75)
        case .help: return Color(red: 0.62, green: 0.55, blue: 0.98)
        }
    }

    private var ink: Color {
        isOn || tint == .help ? .white : tint == .vowel || tint == .sign ? .black : .primary
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 0, y: 1.5)
                .overlay {
                    switch label {
                    case .text(let text):
                        Text(text)
                            .font(.system(size: max(height * textScale(text), 13),
                                          weight: text.count == 1 ? .regular : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
                    case .symbol(let name):
                        Image(systemName: name)
                            .font(.system(size: height * 0.3, weight: .medium))
                    }
                }
                .foregroundStyle(ink)
                .scaleEffect(isPressed ? 0.94 : 1)
                .brightness(isPressed ? -0.08 : 0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(KeyPressStyle(isPressed: $isPressed))
        .accessibilityLabel(accessibilityName)
    }

    /// A glyph big, a clock key (`:15`) a step down, and a word key
    /// (space, delete word, ABC, QWERTY) smaller, all the same size so the
    /// switch keys read alike.
    private func textScale(_ text: String) -> CGFloat {
        if key.action == .mathHelp { return 0.5 }
        // A one-glyph label is a glyph, whatever the key: the calculator's
        // C and =.
        if text.count == 1 { return 0.46 }
        guard case .character = key.action else { return 0.2 }
        return text.count == 1 ? 0.46 : 0.32
    }

    private var accessibilityName: String {
        switch key.action {
        case .character(let c): SpeechNormalizer.key(c)
        case .shift: "Shift"
        case .backspace: "Backspace"
        case .deleteWord: "Delete word"
        case .space: "Space"
        case .speakLine: "Speak"
        case .switchTo(_, let label): "\(label) keyboard"
        case .mathHelp: "Math help"
        }
    }
}

/// Reports the press so the scale lives on the view (`TileView`'s reason).
private struct KeyPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
    }
}
