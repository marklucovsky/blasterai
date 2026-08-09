// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingView.swift
//  claudeBlast
//
//  First-launch wizard. Gated in ContentView on
//  `DeviceProfile.onboardingCompleted == false`. Mode-branched: a Patient
//  device must create a child profile, a Therapist device may skip it, a
//  Personal device skips it outright.
//

import SwiftUI
import SwiftData
import AVFoundation

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Environment(SentenceEngine.self) private var sentenceEngine

    // Step machine -----------------------------------------------------------

    private enum Step: Int, CaseIterable {
        case welcome, role, authorName, childProfile, apiKey, icloud, pinSetup, done
    }

    @State private var step: Step = .welcome

    // Collected answers ------------------------------------------------------

    @State private var role: DeviceRole = .patient
    @State private var authorName: String = ""

    @State private var childName: String = ""
    @State private var childAgeYears: Int = 5
    @State private var childBirthday: Date = ChildProfile.synthesizeBirthday(age: 5)
    @State private var editingExactBirthday: Bool = false
    @State private var childVoiceID: String = ""
    @State private var childMaxTiles: Int = 4
    @State private var skipChildProfile: Bool = false
    /// Presents the OpenAI key setup guide from the welcome screen's prerequisite callout.
    @State private var showKeyGuide: Bool = false

    @State private var apiKey: String = ""
    /// Seeded from the registered default (RELEASE: ON, DEBUG: OFF — see
    /// claudeBlastApp.init) so onboarding reflects the build's sync posture
    /// rather than forcing ON. The iCloud step is hidden in release builds —
    /// the user gets sync without being asked; DEBUG exposes the toggle so the
    /// local-only path can be tested.
    @State private var icloudEnabled: Bool =
        UserDefaults.standard.bool(forKey: AppSettingsKey.icloudEnabled)

    @State private var pinInput: String = ""
    @State private var pinConfirm: String = ""
    @State private var pinSetupStage: PINSetupStage = .enter

    private enum PINSetupStage {
        case enter
        case confirm
    }

    // Derived ----------------------------------------------------------------

    /// True when the env var path is consumed silently — the API key step is
    /// auto-skipped (developer path, not surfaced in the consumer UI).
    private var hasEnvKey: Bool {
        if let v = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespaces), !v.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                Group {
                    switch step {
                    case .welcome:       welcomeStep
                    case .role:          roleStep
                    case .authorName:    authorNameStep
                    case .childProfile:  childProfileStep
                    case .apiKey:        apiKeyStep
                    case .icloud:        icloudStep
                    case .pinSetup:      pinSetupStep
                    case .done:          doneStep
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }

            navBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.bar)
        }
        .onAppear(perform: prefillFromExistingProfileIfAny)
        .onChange(of: step) { _, newStep in
            // Author name is optional/deferrable — no auto-fill; an empty field
            // is fine (Continue stays enabled).
            _ = newStep
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let visibleSteps = Step.allCases.filter { isStepVisible($0) }
        let idx = visibleSteps.firstIndex(of: step) ?? 0
        return ProgressView(value: Double(idx),
                            total: Double(max(1, visibleSteps.count - 1)))
            .progressViewStyle(.linear)
    }

    private func isStepVisible(_ s: Step) -> Bool {
        switch s {
        case .authorName:
            // Attribution only matters for sharing — unlikely on a patient-only
            // device — so we ask only in caregiver setup. Patient-device
            // caregivers can still set it later in Admin → Scenes.
            return role == .caregiver
        case .childProfile:
            // Only Patient mode needs a real child profile up front.
            // Caregiver mode uses the Sandbox profile until the user adds
            // a real patient from Admin → Profiles.
            return role == .patient
        case .apiKey:       return !hasEnvKey
        case .icloud:
            // iCloud is on by default; we don't ask in release. DEBUG
            // builds keep the step so we can flip the toggle off during
            // local-only testing.
            #if DEBUG
            return true
            #else
            return false
            #endif
        case .pinSetup:
            // Patient devices are always Face-ID gated; capture the PIN
            // here so AdminGate doesn't pop a setup sheet the first time
            // someone taps Admin. Caregivers stay PIN-less unless they
            // opt in from Admin → Device.
            return role == .patient
        default:            return true
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Blaster")
                .font(.largeTitle.bold())
            Text("A voice for non-verbal children. Pick tiles, hear sentences.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 8)
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private by default").font(.headline)
                    Text("Your child's data lives on this device. AI calls send the selected words and nothing else.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.title)
            }
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open source").font(.headline)
                    Text("Apache-licensed. Built so the community can adapt it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.title)
            }

            // Surface the one prerequisite early, in the welcome screen's
            // whitespace, so a parent can get a funded OpenAI Platform account
            // going before the key step (it's set up on OpenAI's site, not here).
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bring your own AI key").font(.headline)
                    Text("AI sentences use OpenAI. You'll want a funded OpenAI Platform account (separate from ChatGPT) — about $5 of credit lasts a long time. Set it up now or skip and add it later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showKeyGuide = true
                    } label: {
                        Label("See setup guide", systemImage: "questionmark.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            } icon: {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                    .font(.title)
            }
        }
        .sheet(isPresented: $showKeyGuide) { OpenAIKeySetupSheet() }
    }

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How will this device be used?")
                .font(.title.bold())
            Text("Tap one. The two modes are designed to be switched between — nothing here is permanent.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(DeviceRole.allCases, id: \.self) { option in
                    roleCard(option)
                }
            }
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(DeviceRole.reversibilityNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                }
                Label {
                    Text("Caregiver mode includes a built-in Sandbox profile so the app works out of the box. Add real patient profiles whenever you're ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func roleCard(_ option: DeviceRole) -> some View {
        Button {
            role = option
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: role == option
                      ? "largecircle.fill.circle"
                      : "circle")
                    .font(.title2)
                    .foregroundStyle(role == option ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.displayName).font(.headline)
                    Text(option.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(role == option ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: role == option ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var authorNameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your name")
                .font(.title.bold())
            Text("Credited when you share boards, pages, or vocabulary packs you make — e.g. \u{201C}by Dr. Yalcin.\u{201D}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Dr. Yalcin", text: $authorName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Text("Optional — skip for now and set it anytime in Admin → Boards, before you first share.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var childProfileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Only Patient mode reaches this step now; copy is tuned for
            // that single audience. Caregiver mode skips it entirely and
            // adds patients later from Admin → Profiles.
            Text("About the child")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.headline)
                TextField("Aubrey", text: $childName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Age").font(.headline)
                    Spacer()
                    Text("\(childAgeYears) years old")
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $childAgeYears, in: 1...21) {
                    EmptyView()
                }
                .labelsHidden()
                .onChange(of: childAgeYears) { _, newValue in
                    if !editingExactBirthday {
                        childBirthday = ChildProfile.synthesizeBirthday(age: newValue)
                    }
                }
                Text("Birthday: \(birthdayDisplay) — age auto-updates from this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Edit exact birthday", isExpanded: $editingExactBirthday) {
                    DatePicker("Birthday", selection: $childBirthday,
                               in: ...Date.now,
                               displayedComponents: .date)
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tiles per group").font(.headline)
                    Spacer()
                    Text("\(childMaxTiles)").foregroundStyle(.secondary)
                }
                Stepper(value: $childMaxTiles, in: 2...8) { EmptyView() }
                    .labelsHidden()
                Text("Maximum tiles selectable before the sentence is generated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice").font(.headline)
                voicePicker
            }
        }
    }

    private var birthdayDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: childBirthday)
    }

    private var voicePicker: some View {
        // Use the shared picker so onboarding, Admin → Now, and the child
        // profile form behave the same way: premium / enhanced voices
        // first, auto-preview on selection.
        VoicePickerSection(
            voiceIdentifier: $childVoiceID,
            previewPhrase: childName.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Hi, I'll be your voice."
                : "Hi \(childName.trimmingCharacters(in: .whitespaces)), I'll be your voice."
        )
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenAI API Key")
                .font(.title.bold())
            OpenAIKeyEntrySection(apiKey: $apiKey)
            Label {
                Text("Stored in this device's Keychain only. Never synced via iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "key.fill").foregroundStyle(.orange)
            }
            Text("Skip to use Mock responses instead (no API calls). You can add a key later from Admin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icloudStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync via iCloud?")
                .font(.title.bold())
            Toggle(isOn: $icloudEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable iCloud sync").font(.headline)
                    Text("Sync child profiles, boards, and history across your own Apple devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if icloudEnabled {
                Label {
                    Text("Sync activates after the next app launch.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                }
            }
            Label {
                Text("The OpenAI API key never syncs — it stays in this device's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.green)
            }
        }
    }

    private var pinSetupStep: some View {
        VStack(spacing: 20) {
            Text("Set an Admin PIN")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Used to unlock Admin when Face ID isn't available. Pick a number you'll remember — recovering a forgotten PIN means reinstalling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch pinSetupStage {
            case .enter:
                Text("Enter a 4–6 digit PIN")
                    .font(.headline)
                NumericKeypad(pin: $pinInput, maxLength: 6) {
                    // Auto-advance when the user reaches the cap; for 4
                    // and 5 digit PINs they tap Next manually.
                    if PINAuth.isValidPINShape(pinInput) {
                        pinSetupStage = .confirm
                    }
                }
                Button("Next") {
                    pinSetupStage = .confirm
                }
                // .borderedProminent makes the affordance obvious the
                // moment the PIN reaches a valid 4–6 digit shape, so the
                // user doesn't keep typing past the digit they intended.
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!PINAuth.isValidPINShape(pinInput))

            case .confirm:
                Text("Enter the same PIN again")
                    .font(.headline)
                NumericKeypad(pin: $pinConfirm, maxLength: pinInput.count) {
                    // Auto-confirm on full match is handled by canAdvance —
                    // no extra action needed here.
                }
                if !pinConfirm.isEmpty && !pinInput.hasPrefix(pinConfirm) {
                    Text("Doesn't match — try again")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Back") {
                    pinConfirm = ""
                    pinSetupStage = .enter
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var canAdvancePINSetup: Bool {
        pinSetupStage == .confirm
            && PINAuth.isValidPINShape(pinInput)
            && pinInput == pinConfirm
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Ready").font(.largeTitle.bold())
            Text(doneSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var doneSummary: String {
        switch role {
        case .patient:
            return childName.isEmpty
                ? "Your patient device is set up. Tap Open Blaster to start."
                : "\(childName)'s device is ready. Tap Open Blaster to start."
        case .caregiver:
            return "Caregiver mode is on. The Sandbox profile is active; add real patient profiles anytime from Admin → Profiles."
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            if canGoBack {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if canSkip {
                Button("Skip") { skipAndAdvance() }
                    .buttonStyle(.borderless)
            }
            Button(primaryActionLabel) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvance)
        }
    }

    private var canGoBack: Bool {
        step != .welcome && step != .done
    }

    private var canSkip: Bool {
        switch step {
        // Patient mode requires a child profile, and Caregiver mode hides
        // the step entirely — so there's nothing to skip from this card now.
        case .apiKey:       return true
        default:            return false
        }
    }

    private var primaryActionLabel: String {
        switch step {
        case .welcome: return "Get Started"
        case .done:    return "Open Blaster"
        default:       return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome:      return true
        case .role:         return true
        case .authorName:   return true   // optional / deferrable
        case .childProfile: return !childName.trimmingCharacters(in: .whitespaces).isEmpty
        case .apiKey:       return true
        case .icloud:       return true
        case .pinSetup:     return canAdvancePINSetup
        case .done:         return true
        }
    }

    // MARK: - Step transitions

    private func primaryAction() {
        if step == .done {
            commitAndFinish()
        } else {
            advance()
        }
    }

    private func advance() {
        skipChildProfile = false
        moveStep(forward: true)
    }

    private func skipAndAdvance() {
        if step == .childProfile { skipChildProfile = true }
        if step == .apiKey { apiKey = "" }
        moveStep(forward: true)
    }

    private func goBack() {
        moveStep(forward: false)
    }

    private func moveStep(forward: Bool) {
        let all = Step.allCases
        let currentIdx = all.firstIndex(of: step) ?? 0
        if forward {
            for i in (currentIdx + 1)..<all.count where isStepVisible(all[i]) {
                withAnimation(.easeInOut(duration: 0.2)) { step = all[i] }
                return
            }
        } else {
            for i in stride(from: currentIdx - 1, through: 0, by: -1) where isStepVisible(all[i]) {
                withAnimation(.easeInOut(duration: 0.2)) { step = all[i] }
                return
            }
        }
    }

    // MARK: - Pre-fill from Legacy seed

    private func prefillFromExistingProfileIfAny() {
        // Only pre-fill from a *real* profile. The Sandbox always exists
        // post-migration, but treating it as "the user's prior input"
        // would seed the patient form with "Sandbox" as the child's name.
        let realProfiles = (try? modelContext.fetch(
            FetchDescriptor<ChildProfile>(predicate: #Predicate { !$0.isSystem })
        )) ?? []
        guard let legacy = realProfiles.first else { return }
        childName = legacy.displayName == "Legacy" ? "" : legacy.displayName
        childBirthday = legacy.birthday
        childAgeYears = ChildProfile.age(from: legacy.birthday, asOf: .now)
        childVoiceID = legacy.voiceIdentifier
        childMaxTiles = legacy.maxSelectedTiles
        editingExactBirthday = legacy.displayName != "Legacy"

        // Pre-fill the device display name too if we can recover it.
        if let device = DeviceProfileStore.current(context: modelContext) {
            if !device.authorName.isEmpty { authorName = device.authorName }
        }
    }

    // MARK: - Final commit

    private func commitAndFinish() {
        let inputs = OnboardingInputs(
            role: role,
            authorName: authorName,
            createChild: role == .patient && !skipChildProfile,
            childName: childName,
            childBirthday: childBirthday,
            childVoiceID: childVoiceID,
            childMaxTiles: childMaxTiles,
            apiKey: hasEnvKey ? nil : apiKey, // env-var path keeps its launch-persisted key
            icloudEnabled: icloudEnabled,
            adminPIN: role == .patient ? pinInput : nil
        )
        OnboardingCommit.apply(inputs, context: modelContext)
        profileResolver.refresh()
        // Switch the running engine to OpenAI when the user just supplied a key.
        if let key = OpenAIKeyVault.currentKey() {
            sentenceEngine.switchProvider(OpenAISentenceProvider(apiKey: key))
        }
    }
}
