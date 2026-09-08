// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminGate.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import LocalAuthentication

/// Wraps Admin content with a biometric / PIN challenge when the active
/// `DeviceProfile.requireFaceIDForAdmin` flag is set.
///
/// The biometry is whatever the device actually has — Face ID, Touch ID, or
/// none at all on a Mac running this as Designed-for-iPad. All user-facing copy
/// comes from `Biometry`; nothing here says "Face ID" unconditionally, because
/// on the devices where that is false it is exactly the copy a locked-out
/// caregiver has to rely on.
///
/// Flow on first appearance:
/// 1. If gating isn't required (Personal device, or Therapist that didn't
///    opt in), pass through to content immediately.
/// 2. Otherwise, attempt `LAContext` biometric evaluation. Success → content.
/// 3. On biometric failure / cancel / unavailable, switch to PIN entry.
/// 4. If no PIN has been set up yet, switch to PIN setup mode (enter twice).
///
/// The gate's `didAuth` state is local to one Admin presentation — if the
/// user dismisses Admin and re-enters, they re-authenticate. This is the
/// "cold-launch" posture; a soft re-entry timeout could relax that later.
struct AdminGate<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var deviceProfiles: [DeviceProfile]

    @State private var didAuth = false
    @State private var biometricsAttempted = false
    @State private var biometry = Biometry.Capability(type: .none, isAvailable: false)
    @State private var showingPIN = false
    @State private var pinInput = ""
    @State private var pinConfirm = ""
    @State private var errorMessage: String?
    @State private var pinSetupStage: PINSetupStage = .enter
    @FocusState private var pinFieldFocused: Bool
    /// Ticks while a throttle is in force, so the "try again in…" line counts
    /// down instead of going stale behind a caregiver staring at it.
    @State private var now = Date.now
    /// True once the device owner has proven themselves for a *reset* — see
    /// `recoverWithDeviceOwner`. Drives straight into PIN setup.
    @State private var isResettingPIN = false

    private enum PINSetupStage {
        case enter
        case confirm
    }

    @ViewBuilder let content: () -> Content

    private var device: DeviceProfile? { deviceProfiles.first }
    private var needsAuth: Bool { device?.requireFaceIDForAdmin == true }

    private var isThrottled: Bool {
        PINThrottle.isLocked(until: device?.adminPINLockedUntil, now: now)
    }
    private var hasPIN: Bool {
        device?.adminPINHash != nil && device?.adminPINSalt != nil
    }

    var body: some View {
        Group {
            if didAuth || !needsAuth {
                content()
                    .onAppear {
                        // Lock in "access granted" for the lifetime of this
                        // Admin presentation. Without this, the gate
                        // re-evaluates needsAuth on every parent re-render —
                        // and if the user flips the device role to Patient
                        // from inside Admin, requireFaceIDForAdmin turns on
                        // mid-session and forces them back through the
                        // challenge they already cleared.
                        if !didAuth { didAuth = true }
                    }
            } else {
                challengeView
            }
        }
    }

    // MARK: - Challenge UI

    private var challengeView: some View {
        ZStack(alignment: .topLeading) {
            // Opaque backdrop so the underlying tile grid doesn't bleed
            // through the fullScreenCover. systemBackground adapts to light
            // and dark mode.
            Color(uiColor: .systemBackground).ignoresSafeArea()

            // Cancel — lets the user back out of the gate without
            // authenticating. Tapped Admin by mistake? Hit Cancel and
            // return to the grid. Sits in the top-leading corner like a
            // sheet's cancellation action.
            Button("Cancel") { dismiss() }
                .padding()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Admin is locked")
                    .font(.title.bold())
                Text(challengeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if showingPIN {
                    pinSection
                } else {
                    Button("Try \(biometry.displayName)") {
                        Task { await tryBiometrics() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Use PIN") { showingPIN = true; pinFieldFocused = true }
                        .buttonStyle(.borderless)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()

                if showingPIN && hasPIN && !isResettingPIN {
                    forgotPINHint
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if !biometricsAttempted {
                biometricsAttempted = true
                await tryBiometrics()
            }
        }
        // Only while it matters. A timer that runs behind an unlocked Admin is
        // a view invalidation every second for nothing.
        .task(id: isThrottled) {
            guard isThrottled else { return }
            while !Task.isCancelled, isThrottled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    /// Recovery: prove you own the device, then choose a new PIN.
    ///
    /// This replaces "delete the app and reinstall", which was never an
    /// acceptable instruction to give a family whose child's voice lives in the
    /// app — however much of it iCloud would have restored.
    ///
    /// **`deviceOwnerAuthentication`, not `…WithBiometrics`.** The wider policy
    /// accepts the device passcode when biometry fails or does not exist, which
    /// is the whole point: it is a credential the caregiver already set, needs
    /// no backend, no phone number and no second device, and works on a Mac with
    /// no Touch ID.
    ///
    /// **Admin cannot honestly be more secure than the device it runs on.**
    /// Anyone with the iPad's passcode can already delete this app, wipe it, or
    /// read the family's messages; a lock claiming to hold out against them is
    /// claiming something it cannot deliver. Inheriting the device's own
    /// boundary is the truthful position rather than a weakening of one.
    private var forgotPINHint: some View {
        VStack(spacing: 6) {
            Button("Forgot your PIN?") {
                Task { await recoverWithDeviceOwner() }
            }
            .font(.footnote.weight(.semibold))
            Text("You'll be asked for this \(RuntimePlatform.isMac ? "Mac's" : "device's") passcode, then you can choose a new one. Nothing is deleted.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// The reset path. Deliberately available while throttled: a caregiver
    /// locked out by their own failed guesses is exactly who needs it, and the
    /// throttle is there to slow guessing at the PIN, not to punish someone who
    /// can satisfy a stronger credential than the PIN.
    private func recoverWithDeviceOwner() async {
        let ctx = LAContext()
        var policyError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // No passcode set on the device at all. Nothing here can be stronger
            // than that, so say so rather than pretending to offer a way in.
            errorMessage = "This device has no passcode set, so there is no way to confirm you own it. Set a device passcode in Settings, then try again."
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Reset the Blaster Admin PIN")
            guard ok else { return }
            // Clear the old credential and the throttle it earned, then hand
            // straight to setup — a reset that leaves no PIN behind would turn
            // the lock off silently.
            device?.adminPINHash = nil
            device?.adminPINSalt = nil
            device?.adminPINFailedAttempts = 0
            device?.adminPINLockedUntil = nil
            device?.adminPINResetAt = .now
            device?.modifiedAt = .now
            try? modelContext.save()
            pinInput = ""
            pinConfirm = ""
            pinSetupStage = .enter
            errorMessage = nil
            isResettingPIN = true
        } catch {
            // Cancelled or failed. Silent: the system already told them.
        }
    }

    private var challengeSubtitle: String {
        let name = biometry.displayName
        if hasPIN {
            return biometry.isAvailable
                ? "Use \(name), or enter your PIN."
                : "Enter your PIN."
        }
        if biometry.isAvailable {
            return "Use \(name). Set up a PIN now as a backup for when \(name) isn't available."
        }
        // Distinguish "you have the hardware but haven't enrolled" from "this
        // device has no biometry" — telling a Mac owner to enrol Touch ID they
        // do not have is how a caregiver concludes they are locked out.
        return biometry.hasHardware
            ? "\(name) isn't enrolled on this device. Set up a PIN to unlock Admin."
            : "This device has no biometric unlock. Set up a PIN to unlock Admin."
    }

    @ViewBuilder
    private var pinSection: some View {
        if hasPIN && !isResettingPIN {
            pinEntryView
        } else {
            pinSetupView
        }
    }

    @ViewBuilder
    private var pinEntryView: some View {
        if isThrottled, let until = device?.adminPINLockedUntil {
            VStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Too many attempts")
                    .font(.headline)
                Text("Try again in \(PINThrottle.waitDescription(until: until, now: now)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Named here rather than only in Settings: someone locked out is
                // the one person who needs to know the way back exists.
                Text("Nothing is lost while you wait, and the app keeps working for the child.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else {
            VStack(spacing: 16) {
                // Custom keypad — see NumericKeypad.swift for the iPad rationale
                // (system .keyboardType(.numberPad) doesn't actually give a
                // digits-only keyboard on iPad). `.typedOnly` shows one filled
                // dot per typed digit so the user gets feedback, without
                // pre-showing 6 hollow dots that would lie about how many
                // digits their stored PIN has.
                NumericKeypad(pin: $pinInput, maxLength: 6, dotStyle: .typedOnly) {
                    if PINAuth.isValidPINShape(pinInput) { submitPINEntry() }
                }
                Button("Unlock", action: submitPINEntry)
                    .buttonStyle(.borderedProminent)
                    .disabled(!PINAuth.isValidPINShape(pinInput))
            }
            // Unlock the moment the digits are right, without waiting for the
            // button.
            //
            // The keypad's completion closure only fires at `maxLength`, so a
            // stored 4-digit PIN never triggered it — every caregiver with a
            // short PIN had to type four digits and then reach for Unlock. And
            // because PINs here are 4 *to* 6 digits, nothing else can tell when
            // the entry is finished.
            //
            // A wrong guess is NOT counted here: only reaching six digits or
            // pressing Unlock spends an attempt. Otherwise passing through "123"
            // on the way to "1234" would burn the throttle on a correct entry.
            .onChange(of: pinInput) { _, entry in
                guard entry.count >= 4, matchesStoredPIN(entry) else {
                    if entry.count >= 6 { submitPINEntry() }
                    return
                }
                acceptPIN()
            }
        }
    }

    private func matchesStoredPIN(_ entry: String) -> Bool {
        guard let device, let hash = device.adminPINHash, let salt = device.adminPINSalt
        else { return false }
        return PINAuth.verify(pin: entry, hash: hash, salt: salt)
    }

    /// Shared success path for both the auto-unlock and the button.
    private func acceptPIN() {
        device?.adminPINFailedAttempts = 0
        device?.adminPINLockedUntil = nil
        device?.modifiedAt = .now
        try? modelContext.save()
        pinInput = ""
        errorMessage = nil
        didAuth = true
    }

    private var pinSetupView: some View {
        VStack(spacing: 16) {
            Text(pinSetupCopy)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if pinSetupStage == .enter {
                NumericKeypad(pin: $pinInput, maxLength: 6) {
                    if PINAuth.isValidPINShape(pinInput) {
                        pinSetupStage = .confirm
                    }
                }
                Button("Next") { pinSetupStage = .confirm }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!PINAuth.isValidPINShape(pinInput))
            } else {
                NumericKeypad(pin: $pinConfirm, maxLength: pinInput.count) {
                    if canSubmitPINSetup { submitPINSetup() }
                }
                if !pinConfirm.isEmpty && !pinInput.hasPrefix(pinConfirm) {
                    Text("Doesn't match — try again")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Back") {
                        pinConfirm = ""
                        pinSetupStage = .enter
                    }
                    .buttonStyle(.borderless)
                    Button("Set PIN", action: submitPINSetup)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmitPINSetup)
                }
            }
        }
    }

    private var pinSetupCopy: String {
        switch pinSetupStage {
        case .enter:
            return biometry.hasHardware
                ? "Choose a 4–6 digit PIN. Use it when \(biometry.displayName) isn't available."
                : "Choose a 4–6 digit PIN. It is how you unlock Admin on this device."
        case .confirm: return "Enter the same PIN again to confirm."
        }
    }

    private var canSubmitPINSetup: Bool {
        PINAuth.isValidPINShape(pinInput) && pinInput == pinConfirm
    }

    // MARK: - Actions

    private func tryBiometrics() async {
        let ctx = LAContext()
        var policyError: NSError?
        let canEval = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &policyError)
        // biometryType is only populated after canEvaluatePolicy — see Biometry.
        biometry = Biometry.Capability(type: ctx.biometryType, isAvailable: canEval)
        guard canEval else {
            // No biometric hardware enrolled — go straight to PIN.
            showingPIN = true
            pinFieldFocused = true
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Admin")
            if ok {
                // Biometry proves the owner is present, so a throttle earned by
                // wrong PINs has done its job and should not outlive it.
                acceptPIN()
            } else {
                showingPIN = true
                pinFieldFocused = true
            }
        } catch {
            // User canceled, failed, or the system blocked — fall back to PIN.
            showingPIN = true
            pinFieldFocused = true
        }
    }

    private func submitPINEntry() {
        guard let device,
              device.adminPINHash != nil,
              device.adminPINSalt != nil else {
            errorMessage = "PIN not set up yet — restart and re-enter Admin."
            return
        }
        guard !isThrottled else { return }

        if matchesStoredPIN(pinInput) {
            acceptPIN()
            return
        }

        device.adminPINFailedAttempts += 1
        device.adminPINLockedUntil = PINThrottle.lockedUntil(
            afterFailedAttempts: device.adminPINFailedAttempts)
        device.modifiedAt = .now
        try? modelContext.save()
        pinInput = ""
        // The remaining-attempts count is deliberately not shown. It tells
        // someone guessing exactly how much room they have left, and tells a
        // caregiver who mistyped nothing they can act on.
        errorMessage = isThrottled ? nil : "Incorrect PIN."
    }

    private func submitPINSetup() {
        guard let device else { return }
        guard canSubmitPINSetup else {
            errorMessage = "PINs must match and be 4–6 digits."
            return
        }
        let salt = PINAuth.newSalt()
        guard let hash = PINAuth.hash(pin: pinInput, salt: salt) else {
            errorMessage = "Could not save PIN."
            return
        }
        device.adminPINSalt = salt
        device.adminPINHash = hash
        // A fresh credential clears whatever the old one earned. Without this a
        // caregiver who recovered *because* they were throttled would set a new
        // PIN and still be shut out by the old counter.
        device.adminPINFailedAttempts = 0
        device.adminPINLockedUntil = nil
        device.modifiedAt = .now
        try? modelContext.save()
        isResettingPIN = false
        didAuth = true
        pinInput = ""
        pinConfirm = ""
        errorMessage = nil
    }
}
