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

struct KeyboardSurfaceView: View {
    @Environment(SentenceEngine.self) private var engine
    @AppStorage(AppSettingsKey.keyboardHighlightVowels) private var highlightVowels = true

    let layout: KeyboardLayout
    /// The grid area this draws in, and the board's gaps.
    let size: CGSize
    let spacing: CGFloat
    /// Open another keyboard page, by its BlasterAI 60 page key.
    let onSwitch: (String) -> Void

    enum Shift { case off, once, locked }
    @State private var shift: Shift = .off
    @State private var lastShiftTap: Date = .distantPast

    /// The prediction row (PR F) and four rows of keys.
    private static let rowCount = 5

    var body: some View {
        let rowHeight = (size.height - spacing * CGFloat(Self.rowCount - 1)) / CGFloat(Self.rowCount)
        let rows = layout.rows
        // A key-width plus its gap is one step, so a key `w` wide spans `w`
        // steps less one gap, and every row — however many keys — ends on the
        // grid's right edge.
        let unit = (size.width - spacing * CGFloat(KeyboardLayout.rowWidth - 1))
            / CGFloat(KeyboardLayout.rowWidth)
        VStack(spacing: spacing) {
            // Kept for word prediction, so the keys don't move when it lands.
            Color.clear.frame(height: rowHeight)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { key in
                        let width = unit * CGFloat(key.width) + spacing * CGFloat(key.width - 1)
                        KeyCap(key: key, label: label(for: key), tint: tint(for: key),
                               isOn: isOn(key), height: rowHeight) { press(key) }
                            .frame(width: width, height: rowHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    // MARK: - Keys

    private func press(_ key: KeyboardKey) {
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
            engine.typeSpeakLine()
        case .switchTo(let page, _):
            onSwitch(page)
        }
    }

    /// Key caps show what the key will type: capitals while Shift is on.
    private func label(for key: KeyboardKey) -> KeyCap.Label {
        switch key.action {
        case .character(let c): .text(shift == .off ? c : c.uppercased())
        case .shift: .symbol(shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
        case .backspace: .symbol("delete.left")
        case .deleteWord: .text("delete word")
        case .space: .text("space")
        case .speakLine: .symbol("speaker.wave.2.fill")
        case .switchTo(_, let label): .text(label)
        }
    }

    private func tint(for key: KeyboardKey) -> KeyCap.Tint {
        switch key.action {
        case .character: key.isVowel && highlightVowels ? .vowel : .letter
        case .speakLine: .speak
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
    enum Tint { case letter, vowel, function, speak }

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
        case .function: return Color(.systemGray4)
        case .speak: return Color.green.opacity(0.75)
        }
    }

    private var ink: Color {
        isOn ? .white : tint == .vowel ? .black : .primary
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
                            .font(.system(size: text.count == 1 ? height * 0.46 : height * 0.2,
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

    private var accessibilityName: String {
        switch key.action {
        case .character(let c): SpeechNormalizer.key(c)
        case .shift: "Shift"
        case .backspace: "Backspace"
        case .deleteWord: "Delete word"
        case .space: "Space"
        case .speakLine: "Speak"
        case .switchTo(_, let label): "\(label) keyboard"
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
