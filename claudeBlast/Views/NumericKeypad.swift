// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NumericKeypad.swift
//  claudeBlast
//
//  Custom 0–9 keypad for PIN entry. Bypasses the system keyboard
//  entirely so iPad users can't accidentally tab over to letters (the
//  iPad's `.keyboardType(.numberPad)` shows the *full* keyboard with the
//  numbers pane pre-selected, which is the bug we keep hitting).
//

import SwiftUI

/// Self-contained digit grid + dot indicator for entering a numeric PIN.
/// Caller owns `pin: Binding<String>`; this view only appends digits and
/// backspaces. `maxLength` caps the input; tapping a digit at the cap is
/// a no-op. `onComplete` fires when `pin.count == maxLength` after an
/// append — callers use it to auto-advance to the next step.
struct NumericKeypad: View {
    @Binding var pin: String
    var maxLength: Int = 6
    /// How to render the row of dots above the keypad.
    var dotStyle: DotStyle = .lengthHint
    /// Use a tighter button + spacing layout for embedded contexts
    /// (Form sections on iPad mini, the PatientTransitionSheet) where the
    /// full-size grid pushes other controls offscreen. Standalone gates
    /// keep the larger default.
    var sizing: Sizing = .standard
    var onComplete: (() -> Void)? = nil

    /// Setup screens know the target length (`maxLength`), so they preview
    /// the full row with filled / hollow dots. Verification screens
    /// don't know the user's PIN length, so we just append one filled dot
    /// per typed digit — typing feedback without lying about how many
    /// digits are left.
    enum DotStyle {
        case lengthHint
        case typedOnly
        case hidden
    }

    enum Sizing {
        case standard
        case compact

        var buttonSize: CGFloat {
            switch self {
            case .standard: return 72
            case .compact:  return 52
            }
        }
        var buttonFont: Font {
            switch self {
            case .standard: return .title.weight(.medium)
            case .compact:  return .title3.weight(.medium)
            }
        }
        var gridSpacing: CGFloat {
            switch self {
            case .standard: return 14
            case .compact:  return 10
            }
        }
        var sectionSpacing: CGFloat {
            switch self {
            case .standard: return 28
            case .compact:  return 16
            }
        }
    }

    var body: some View {
        VStack(spacing: sizing.sectionSpacing) {
            dotIndicator
            keypadGrid
        }
        // A hardware keyboard must work. The on-screen grid exists to keep the
        // iPad's full keyboard out of the way, not to forbid typing — and on a
        // Mac (Designed for iPad) the caregiver's first instinct is to type
        // their PIN. Without this, nothing happens and the device reads as
        // broken. Digits append, delete backspaces, and the buttons keep
        // working exactly as before.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = press.characters.first, digit.isNumber else { return .ignored }
            append(String(digit))
            return .handled
        }
        .onKeyPress(.delete) {
            backspace()
            return .handled
        }
    }

    // MARK: - Input

    /// Single entry point for adding a digit, shared by the on-screen buttons
    /// and the hardware keyboard so the two can never drift.
    private func append(_ digit: String) {
        guard pin.count < maxLength else { return }
        pin += digit
        if pin.count == maxLength { onComplete?() }
    }

    private func backspace() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    // MARK: - Dot indicator

    @ViewBuilder
    private var dotIndicator: some View {
        switch dotStyle {
        case .lengthHint:
            HStack(spacing: 16) {
                ForEach(0..<maxLength, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 14, height: 14)
                }
            }
        case .typedOnly:
            // Fixed-height row so the keypad doesn't bounce up/down as the
            // user types. Empty until the first digit, then one filled dot
            // per typed character.
            HStack(spacing: 16) {
                ForEach(0..<pin.count, id: \.self) { _ in
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(height: 14)
        case .hidden:
            EmptyView()
        }
    }

    // MARK: - Keypad

    private var keypadGrid: some View {
        VStack(spacing: sizing.gridSpacing) {
            HStack(spacing: sizing.gridSpacing) {
                digitButton("1"); digitButton("2"); digitButton("3")
            }
            HStack(spacing: sizing.gridSpacing) {
                digitButton("4"); digitButton("5"); digitButton("6")
            }
            HStack(spacing: sizing.gridSpacing) {
                digitButton("7"); digitButton("8"); digitButton("9")
            }
            HStack(spacing: sizing.gridSpacing) {
                spacerCell()
                digitButton("0")
                backspaceButton
            }
        }
    }

    private func digitButton(_ digit: String) -> some View {
        let size = sizing.buttonSize
        return Button {
            append(digit)
        } label: {
            Text(digit)
                .font(sizing.buttonFont)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var backspaceButton: some View {
        let size = sizing.buttonSize
        return Button {
            backspace()
        } label: {
            Image(systemName: "delete.left")
                .font(.title3)
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(pin.isEmpty)
    }

    private func spacerCell() -> some View {
        let size = sizing.buttonSize
        return Color.clear.frame(width: size, height: size)
    }
}
