// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TransitionSheets.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

// MARK: - Patient transition sheet

/// Presented when an Admin user flips the device role to Patient. Captures
/// the handoff loose ends in one place: PIN (required), API key disposition,
/// device name. Without this, the therapist would have to set up the PIN on
/// the next Admin re-entry — which means the *next* person opening Admin
/// (the patient or their parent) sets it. Wrong owner.
struct PatientTransitionSheet: View {
    let device: DeviceProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Query(filter: #Predicate<ChildProfile> { !$0.isSystem },
           sort: \ChildProfile.displayName) private var realPatients: [ChildProfile]

    @State private var selectedPatientID: String = ""
    @State private var pinInput: String = ""
    @State private var pinConfirm: String = ""
    @State private var pinStage: PINStage = .enter
    @State private var keyChoice: KeyChoice = .keep
    @State private var newAPIKey: String = ""
    @State private var step: Step = .patient

    /// Three-page step machine — the keypad on `.pin` is too tall for an
    /// iPad form-sheet to render alongside everything else, so we give it
    /// its own page rather than stacking the whole flow into one Form.
    private enum Step: Int, CaseIterable {
        case patient   // pick patient + device name
        case pin       // PIN entry + confirm
        case apiKey    // API key disposition
    }

    private enum PINStage {
        case enter
        case confirm
    }

    init(device: DeviceProfile,
         onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.device = device
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    enum KeyChoice: String, CaseIterable, Identifiable {
        case keep
        case clear
        case replace
        var id: String { rawValue }
    }

    private var hasExistingKey: Bool {
        OpenAIKeyVault.currentKey() != nil
    }

    private var availableChoices: [KeyChoice] {
        hasExistingKey ? [.keep, .clear, .replace] : [.clear, .replace]
    }

    private func keyChoiceLabel(_ c: KeyChoice) -> String {
        switch c {
        case .keep:    return "Keep the key currently on this device"
        case .clear:   return "No key — use Mock responses"
        case .replace: return "Use a different key for the patient"
        }
    }

    /// True when the device already has a PIN we can preserve. Skipping
    /// the PIN setup step in that case is the difference between a clean
    /// caregiver → patient flip and an annoying forced re-entry.
    private var hasExistingPIN: Bool {
        device.adminPINHash != nil && device.adminPINSalt != nil
    }

    private var canCommit: Bool {
        guard !realPatients.isEmpty, !selectedPatientID.isEmpty else { return false }
        // PIN only needs to be valid+matching when we're actually setting
        // one. With an existing PIN the .pin step is skipped entirely.
        if !hasExistingPIN {
            guard PINAuth.isValidPINShape(pinInput), pinInput == pinConfirm else {
                return false
            }
        }
        if keyChoice == .replace {
            return !newAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgress
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                content
                Divider()
                stepNav
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Switch to Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                keyChoice = availableChoices.first ?? .clear
                if selectedPatientID.isEmpty {
                    if let activeReal = realPatients.first(where: { $0.isActive }) {
                        selectedPatientID = activeReal.id
                    } else if let first = realPatients.first {
                        selectedPatientID = first.id
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Step machinery

    private var stepProgress: some View {
        // Collapse the 3-step bar to a 2-step bar when the .pin step is
        // going to be skipped (existing PIN preserved).
        let total: Double = hasExistingPIN
            ? Double(Step.allCases.count - 2)
            : Double(Step.allCases.count - 1)
        let value: Double = {
            if hasExistingPIN && step == .apiKey { return 1 }
            return Double(step.rawValue)
        }()
        return ProgressView(value: value, total: max(total, 1))
            .progressViewStyle(.linear)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .patient: patientPage
        case .pin:     pinPage
        case .apiKey:  apiKeyPage
        }
    }

    private var stepNav: some View {
        HStack {
            if step != .patient {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step == .apiKey {
                Button("Switch", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            } else {
                Button("Continue") { goNext() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
        }
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        // Skip the PIN setup step when the device already has one — we'd
        // just be making the user re-enter a PIN we're going to keep.
        if next == .pin && hasExistingPIN {
            step = .apiKey
        } else {
            step = next
        }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        if prev == .pin && hasExistingPIN {
            // Step skipped on the way forward; skip it on the way back too.
            step = .patient
            return
        }
        step = prev
        if step == .pin {
            // Returning to the PIN page should let the user re-do entry
            // rather than dropping them in a partial confirm state.
            pinConfirm = ""
            pinStage = .enter
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .patient:
            return !realPatients.isEmpty
                && !selectedPatientID.isEmpty
        case .pin:
            return PINAuth.isValidPINShape(pinInput) && pinInput == pinConfirm
        case .apiKey:
            return true
        }
    }

    // MARK: - Per-step pages

    @ViewBuilder
    private var patientPage: some View {
        Form {
            Section {
                if realPatients.isEmpty {
                    Label {
                        Text("No patient profiles yet. Open the Profiles tab and add one before switching modes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Picker("Patient", selection: $selectedPatientID) {
                        ForEach(realPatients) { p in
                            Text("\(p.displayName) · age \(p.age)").tag(p.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } header: {
                Text("Whose Device Is This?")
            } footer: {
                Text("Pick the child this device will belong to. Their profile drives the voice and AI prompts after the switch.")
            }
        }
    }

    @ViewBuilder
    private var pinPage: some View {
        VStack(spacing: 16) {
            Text("Admin PIN")
                .font(.headline)
            Text(pinStage == .enter
                 ? "Enter a 4–6 digit PIN. Used to unlock Admin when Face ID isn't available."
                 : "Enter the same PIN again to confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if pinStage == .enter {
                NumericKeypad(pin: $pinInput, maxLength: 6) {
                    if PINAuth.isValidPINShape(pinInput) {
                        pinStage = .confirm
                    }
                }
                Button("Next") { pinStage = .confirm }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!PINAuth.isValidPINShape(pinInput))
            } else {
                NumericKeypad(pin: $pinConfirm,
                              maxLength: pinInput.count)
                if !pinConfirm.isEmpty && !pinInput.hasPrefix(pinConfirm) {
                    Text("Doesn't match — try again")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Restart PIN") {
                    pinInput = ""
                    pinConfirm = ""
                    pinStage = .enter
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var apiKeyPage: some View {
        Form {
            Section {
                Picker("API Key", selection: $keyChoice) {
                    ForEach(availableChoices) { c in
                        Text(keyChoiceLabel(c)).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if keyChoice == .replace {
                    SecureField("sk-…", text: $newAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text(keyFooter)
            }
        }
    }

    private var keyFooter: String {
        switch keyChoice {
        case .keep:
            return "The patient (or their family) will use the API key already on this device. Token usage bills to whoever owns that key."
        case .clear:
            return "Generation falls back to Mock. The patient can add a key later from Admin → Sentence Provider."
        case .replace:
            return "Stored in this device's Keychain. Never synced via iCloud."
        }
    }

    private func commit() {
        // PIN — only set a new one if the .pin step actually ran. When the
        // device already had a PIN we preserved it and skipped that step,
        // so the existing hash/salt stay in place.
        if !hasExistingPIN {
            let salt = PINAuth.newSalt()
            guard let hash = PINAuth.hash(pin: pinInput, salt: salt) else { return }
            device.adminPINSalt = salt
            device.adminPINHash = hash
        }

        // Role + Face ID
        device.role = .patient
        device.requireFaceIDForAdmin = true
        device.modifiedAt = .now

        // Activate the selected real patient and deactivate everyone else
        // (including Sandbox). Without this, the engine would keep talking
        // through whichever profile was active before the switch.
        let all = (try? modelContext.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for p in all {
            if p.id == selectedPatientID {
                if !p.isActive { p.isActive = true }
                p.modifiedAt = now
            } else if p.isActive {
                p.isActive = false
                p.modifiedAt = now
            }
        }
        try? modelContext.save()
        profileResolver.refresh()

        // API key
        switch keyChoice {
        case .keep:
            break
        case .clear:
            OpenAIKeyVault.clearKey()
        case .replace:
            OpenAIKeyVault.setKey(newAPIKey)
        }

        onConfirm()
    }
}

// MARK: - Caregiver transition sheet

/// Presented when an Admin user flips the device role from Patient back to
/// Caregiver. Confirms current-PIN to prove they're the responsible adult
/// (not the child who knows the PIN), then activates the Sandbox profile.
/// "Keep admin protected" defaults ON — the therapist retains the PIN gate
/// even after handing the device back to caregiver mode unless they
/// explicitly turn it off. The PIN stays around so flipping back to Patient
/// later doesn't require re-setup.
struct CaregiverTransitionSheet: View {
    let device: DeviceProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var pinInput = ""
    @State private var pinError: String?
    @State private var keepGate = true
    @State private var keyChoice: KeyChoice = .keep
    @State private var newAPIKey: String = ""
    @State private var step: Step = .pin

    /// Two pages — PIN unlock (with keypad room) followed by gate +
    /// API key options. Matches the PatientTransitionSheet pattern so the
    /// keypad never has to share a single Form with other controls on
    /// iPad mini.
    private enum Step: Int, CaseIterable {
        case pin
        case options
    }

    enum KeyChoice: String, CaseIterable, Identifiable {
        case keep, clear, replace
        var id: String { rawValue }
    }

    private var hasExistingKey: Bool {
        OpenAIKeyVault.currentKey() != nil
    }

    private var availableChoices: [KeyChoice] {
        hasExistingKey ? [.keep, .clear, .replace] : [.clear, .replace]
    }

    private func keyChoiceLabel(_ c: KeyChoice) -> String {
        switch c {
        case .keep:    return "Keep the API key already on this device"
        case .clear:   return "Clear the API key (use Mock responses)"
        case .replace: return "Replace with a different key"
        }
    }

    private var canCommit: Bool {
        guard let salt = device.adminPINSalt,
              let hash = device.adminPINHash else {
            // No PIN was ever set — patient mode somehow without gate.
            // Allow commit and just clear any residual state.
            return true
        }
        guard PINAuth.isValidPINShape(pinInput) else { return false }
        return PINAuth.verify(pin: pinInput, hash: hash, salt: salt)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if device.adminPINHash != nil {
                    stepProgress
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }
                content
                Divider()
                stepNav
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Switch to Caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                keyChoice = availableChoices.first ?? .clear
                // Skip PIN page when there's no PIN to verify.
                if device.adminPINHash == nil { step = .options }
            }
        }
        .interactiveDismissDisabled()
    }

    private var stepProgress: some View {
        ProgressView(value: Double(step.rawValue),
                     total: Double(Step.allCases.count - 1))
            .progressViewStyle(.linear)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pin:     pinPage
        case .options: optionsPage
        }
    }

    private var stepNav: some View {
        HStack {
            if step != .pin && device.adminPINHash != nil {
                Button("Back") { step = .pin }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step == .options {
                Button("Switch", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            } else {
                Button("Continue") {
                    if canAdvanceFromPIN { step = .options }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvanceFromPIN)
            }
        }
    }

    private var canAdvanceFromPIN: Bool {
        guard let salt = device.adminPINSalt,
              let hash = device.adminPINHash else { return true }
        return PINAuth.isValidPINShape(pinInput)
            && PINAuth.verify(pin: pinInput, hash: hash, salt: salt)
    }

    @ViewBuilder
    private var pinPage: some View {
        VStack(spacing: 16) {
            Text("Confirm Current PIN")
                .font(.headline)
            Text("Re-entering the PIN prevents anyone with grid access — including the child — from quietly returning the device to caregiver mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            NumericKeypad(pin: $pinInput, maxLength: 6,
                          dotStyle: .typedOnly)
            if let pinError {
                Text(pinError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var optionsPage: some View {
        Form {
            Section {
                Text("This swaps the active patient profile for the Sandbox profile and removes the patient handoff. Nothing is deleted — you can return to Patient mode anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Return to Caregiver Mode")
            }

            Section {
                Toggle("Keep admin protected", isOn: $keepGate)
            } header: {
                Text("Admin Gate")
            } footer: {
                Text(keepGate
                     ? "Face ID + PIN gate stays on. Recommended — your tuning work stays private even while the patient isn't using the device."
                     : "Gate removed. Anyone can open Admin without authentication. The PIN is cleared.")
            }

            Section {
                Picker("API Key", selection: $keyChoice) {
                    ForEach(availableChoices) { c in
                        Text(keyChoiceLabel(c)).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if keyChoice == .replace {
                    SecureField("sk-…", text: $newAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("OpenAI API Key")
            }
        }
    }

    private func commit() {
        // Re-verify before any mutation. canCommit already guards but be
        // explicit so a malformed state never silently switches roles.
        if let salt = device.adminPINSalt,
           let hash = device.adminPINHash,
           !PINAuth.verify(pin: pinInput, hash: hash, salt: salt) {
            pinError = "Incorrect PIN."
            pinInput = ""
            return
        }

        // Activate Sandbox; deactivate any real active profile.
        let all = (try? modelContext.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for p in all {
            if p.isSystem {
                if !p.isActive { p.isActive = true; p.modifiedAt = now }
            } else if p.isActive {
                p.isActive = false
                p.modifiedAt = now
            }
        }

        // Device flip.
        device.role = .caregiver
        if !keepGate {
            device.requireFaceIDForAdmin = false
            device.adminPINHash = nil
            device.adminPINSalt = nil
        }
        device.modifiedAt = now

        // API key.
        switch keyChoice {
        case .keep:    break
        case .clear:   OpenAIKeyVault.clearKey()
        case .replace: OpenAIKeyVault.setKey(newAPIKey)
        }

        try? modelContext.save()
        onConfirm()
    }
}
