// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PINSetupSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Choose the PIN at the moment the lock is switched on.
///
/// It used to be chosen at the gate: turning on "Lock Admin" with no PIN stored
/// left the *next* Admin entry demanding one be invented on the spot. That is
/// the worst possible moment — the caregiver is trying to get in, often with a
/// child waiting, and a credential picked under that pressure is a credential
/// picked badly or forgotten by morning.
///
/// Worse on a Mac, where there is no biometry to fall back on: the lock would go
/// on with no PIN behind it and nothing to say the device was one cancelled
/// sheet away from having no way in at all.
struct PINSetupSheet: View {
    let device: DeviceProfile
    /// Called only when a PIN was actually stored. The caller reverts the toggle
    /// otherwise — a lock with no credential behind it is worse than no lock.
    let onComplete: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var confirm = ""
    @State private var stage: Stage = .enter
    @State private var errorMessage: String?

    private enum Stage { case enter, confirm }

    private var canSubmit: Bool {
        PINAuth.isValidPINShape(pin) && pin == confirm
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text(stage == .enter ? "Choose a PIN" : "Enter it again")
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if stage == .enter {
                    NumericKeypad(pin: $pin, maxLength: 6) {
                        if PINAuth.isValidPINShape(pin) { stage = .confirm }
                    }
                    Button("Next") { stage = .confirm }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!PINAuth.isValidPINShape(pin))
                } else {
                    NumericKeypad(pin: $confirm, maxLength: pin.count) {
                        if canSubmit { commit() }
                    }
                    if !confirm.isEmpty && !pin.hasPrefix(confirm) {
                        Text("Doesn't match — try again")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Back") { confirm = ""; stage = .enter }
                            .buttonStyle(.borderless)
                        Button("Set PIN", action: commit)
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSubmit)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .navigationTitle("Admin PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(false); dismiss() }
                }
            }
            // Half-finished is the same as cancelled here, and leaving the lock
            // on with nothing behind it is the failure this sheet exists to
            // prevent — so a swipe-away reverts rather than being ignored.
            .presentationDetents([.large])
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            if device.adminPINHash == nil { onComplete(false) }
        }
    }

    private var subtitle: String {
        switch stage {
        case .enter:
            return "4 to 6 digits. You'll need it to open Admin — and on a device with no Face ID or Touch ID, it is the only way in."
        case .confirm:
            return "Enter the same PIN again to confirm."
        }
    }

    private func commit() {
        guard canSubmit else {
            errorMessage = "PINs must match and be 4–6 digits."
            return
        }
        let salt = PINAuth.newSalt()
        guard let hash = PINAuth.hash(pin: pin, salt: salt) else {
            errorMessage = "Could not save PIN."
            return
        }
        device.adminPINSalt = salt
        device.adminPINHash = hash
        // A fresh PIN clears any throttle the old one earned.
        device.adminPINFailedAttempts = 0
        device.adminPINLockedUntil = nil
        device.modifiedAt = .now
        try? modelContext.save()
        onComplete(true)
        dismiss()
    }
}
