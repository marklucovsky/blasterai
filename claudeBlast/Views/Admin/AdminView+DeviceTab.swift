// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+DeviceTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {

    /// What this device calls its biometric unlock, if it has one. Recomputed
    /// per render — `LAContext.canEvaluatePolicy` is a cheap local call, and
    /// caching it would go stale the moment a caregiver enrols Touch ID.
    var biometry: Biometry.Capability { Biometry.capability() }

    /// True when removing the PIN would lock the caregiver out entirely: Admin
    /// is locked, and this device has no biometry to fall back on. A Mac
    /// running as Designed-for-iPad is the case this exists for.
    var pinIsOnlyWayIn: Bool {
        guard let device = deviceProfiles.first else { return false }
        return device.requireFaceIDForAdmin && !biometry.hasHardware
    }

    /// Pull a pending `admin/device/...` request off the coordinator.
    func consumePendingDeviceDetail() {
        guard let detail = adminRoute.consumeDetail(for: .device) else { return }
        deviceDetail = detail
    }

    var deviceTab: some View {
        NavigationStack {
            List {
                deviceSection
                sentenceProviderSection
                sentenceTraySection
                aboutSection
                #if DEBUG
                storageSection
                #endif
            }
            .navigationTitle("Device")
            .navigationDestination(item: $deviceDetail) { detail in
                switch detail {
                case .about:      AboutStatsView()
                case .tileScript: TileScriptView()
                case .vocabulary: EmptyView()   // not a Device destination
                }
            }
            .onAppear { consumePendingDeviceDetail() }
            .onChange(of: adminRoute.pendingDetail) { _, _ in consumePendingDeviceDetail() }
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Device", systemImage: "gear") }
        .sheet(isPresented: $pendingPatientTransition) {
            if let device = deviceProfiles.first {
                PatientTransitionSheet(
                    device: device,
                    onConfirm: {
                        pendingPatientTransition = false
                        displayedRole = device.role
                        // Tearing down the admin cover immediately would
                        // leave a stale dimming overlay. The short sleep
                        // lets the sheet animate out first.
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            dismiss()
                        }
                    },
                    onCancel: {
                        pendingPatientTransition = false
                        displayedRole = device.role
                    }
                )
            }
        }
        .sheet(isPresented: $pendingCaregiverTransition) {
            if let device = deviceProfiles.first {
                CaregiverTransitionSheet(
                    device: device,
                    onConfirm: {
                        pendingCaregiverTransition = false
                        displayedRole = device.role
                        // Resolver picks up the Sandbox profile that the
                        // sheet activated; refresh so subsequent reads see it.
                        profileResolver.refresh()
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            dismiss()
                        }
                    },
                    onCancel: {
                        pendingCaregiverTransition = false
                        displayedRole = device.role
                    }
                )
            }
        }
    }

    // MARK: - Device section (role, gating, PIN)

    @ViewBuilder
    var deviceSection: some View {
        if let device = deviceProfiles.first {
            Section("Device") {
                Picker("Role", selection: $displayedRole) {
                    ForEach(DeviceRole.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .onAppear { displayedRole = device.role }
                .onChange(of: displayedRole) { _, newRole in
                    switch (device.role, newRole) {
                    case (.patient, .patient), (.caregiver, .caregiver):
                        return // no-op
                    case (_, .patient):
                        // Caregiver → Patient: capture PIN + key disposition.
                        pendingPatientTransition = true
                    case (.patient, .caregiver):
                        // Patient → Caregiver: confirm gate retention + key.
                        pendingCaregiverTransition = true
                    default:
                        device.role = newRole
                    }
                }
                Toggle("Lock Admin\(biometry.hasHardware ? " (\(biometry.displayName) or PIN)" : " with a PIN")",
                       isOn: Binding(
                        get: { device.requireFaceIDForAdmin },
                        set: { device.requireFaceIDForAdmin = $0 }
                       ))
                .disabled(device.role == .patient) // patient always on
                if device.adminPINHash != nil {
                    // On a device with no biometry the PIN is the ONLY credential,
                    // so removing it while Admin is locked has no fallback to fall
                    // back to — it locks the caregiver out of their own device.
                    // A Mac running this as Designed-for-iPad is exactly that case.
                    Button("Remove PIN", role: .destructive) {
                        device.adminPINHash = nil
                        device.adminPINSalt = nil
                        device.modifiedAt = .now
                    }
                    .disabled(pinIsOnlyWayIn)
                    if pinIsOnlyWayIn {
                        Text("This device has no biometric unlock, so the PIN is the only way into Admin. Turn off the Admin lock first if you want to remove it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Removing the PIN means \(biometry.displayName) is the only way in. You'll be prompted to set a new one on next Admin entry if \(biometry.displayName) fails.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if device.requireFaceIDForAdmin {
                    Text(biometry.hasHardware
                         ? "PIN not set — you'll be asked to create one next time \(biometry.displayName) fails."
                         : "PIN not set — you'll be asked to create one next time you open Admin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var sentenceProviderSection: some View {
        Section("Sentence Provider") {
            if envKeyOverride {
                LabeledContent("Provider", value: "OpenAI (env override)")
                LabeledContent("API Key") {
                    Text("Set via environment")
                        .foregroundStyle(.green)
                }
            } else {
                Picker("Provider", selection: $providerChoice) {
                    Text("OpenAI").tag("openai")
                    // Apple Intelligence hidden — on-device safety guardrails
                    // block innocuous AAC content (see PRD discussion log).
                    Text("Mock").tag("mock")
                }
                if providerChoice == "openai" {
                    OpenAIKeyEntrySection(apiKey: $apiKey, showCostEstimate: false)
                    if apiKey.isEmpty {
                        Text("Enter your OpenAI API key to enable AI sentence generation.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            LabeledContent("Active Provider", value: sentenceEngine.provider.displayName)
            Toggle("Audio", isOn: $audioEnabled)
            Toggle("Tile Speech Preview", isOn: $tileSpeechEnabled)
            Stepper(
                "Tile Density: \(tileDensityLabel(tileSizeStep))",
                value: $tileSizeStep,
                in: -3...3,
                step: 1
            )
            Picker("Image Set", selection: $imageSetRaw) {
                ForEach(ImageSetCatalog.selectable) { set in
                    Text(set.isShippable ? set.displayName : "\(set.displayName) (incomplete)")
                        .tag(set.id.rawValue)
                }
            }
        }
        .onChange(of: imageSetRaw) {
            // Resolved, not raw: a stored id this build cannot resolve must fall
            // back rather than leave the resolver pointing at a set with no art.
            imageResolver.activeSet = ImageSetID.resolved(imageSetRaw)
        }
        .onAppear {
            // Self-heal a stored id that no longer resolves — including the empty
            // string an earlier build could persist. Without this the Picker has
            // no matching tag and simply shows nothing selected.
            let resolved = ImageSetID.resolved(imageSetRaw)
            if resolved.rawValue != imageSetRaw { imageSetRaw = resolved.rawValue }
        }
        .onChange(of: providerChoice) { applyProvider() }
        .onChange(of: apiKey) {
            OpenAIKeyVault.setKey(apiKey)
            applyProvider()
        }
        .onChange(of: audioEnabled) { sentenceEngine.audioEnabled = audioEnabled }
        .onAppear {
            sentenceEngine.audioEnabled = audioEnabled
            // Voice is per-child now — set in the Now tab's Active Profile
            // section. Leaving engine.voiceIdentifier empty lets the
            // resolver pick the active child's voice.
        }
    }

    @ViewBuilder
    var sentenceTraySection: some View {
        Section {
            // Tiles per group is per-profile (active ChildProfile.maxSelectedTiles)
            // and lives on the Now tab. Don't expose a device-wide stepper
            // here — it'd shadow the per-profile value and confuse users
            // wondering which one wins.
            Stepper(
                "Pulse after: \(idleDebounceMs) ms",
                value: $idleDebounceMs,
                in: 500...5000,
                step: 250
            )
            Stepper(
                autoDoneMs == 0
                    ? "Auto-Done: off"
                    : "Auto-Done: \(autoDoneMs / 1000) s",
                value: $autoDoneMs,
                in: 0...120000,
                step: 5000
            )
            Stepper(
                "Tray buffer: \(trayBufferSize) groups",
                value: $trayBufferSize,
                in: 50...500,
                step: 50
            )
            Button(role: .destructive) {
                sentenceEngine.resetSession()
            } label: {
                Label("Reset Session", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Sentence Tray")
        } footer: {
            Text("Engine timings shared across profiles. Tiles-per-group is per-child — set it on the Now tab.")
                .font(.caption)
        }
    }

    @ViewBuilder
    var aboutSection: some View {
        Section {
            NavigationLink {
                AboutStatsView()
            } label: {
                Label("About & Stats", systemImage: "chart.bar.doc.horizontal")
            }
            // TileScript's only other entry point is the caregiver menu, which a
            // patient device deliberately trims to Admin alone — leaving scripts
            // unreachable on the very device you would demo on. Admin is the
            // gated door both paths should lead through anyway.
            NavigationLink {
                TileScriptView()
            } label: {
                Label("TileScript", systemImage: "play.rectangle.fill")
            }
        } footer: {
            Text("Vocabulary, board, and activity counts — plus CloudKit sync health. TileScript records and replays board sessions.")
        }
    }

    #if DEBUG
    @ViewBuilder
    var storageSection: some View {
        Section("Storage") {
            Toggle("iCloud Sync", isOn: $icloudEnabled)
            if icloudEnabled {
                Text("iCloud sync takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

    func applyProvider() {
        guard !envKeyOverride else { return }
        let newProvider: any SentenceProvider
        if providerChoice == "openai", !apiKey.isEmpty {
            newProvider = OpenAISentenceProvider(apiKey: apiKey)
        } else {
            newProvider = MockSentenceProvider()
        }
        sentenceEngine.switchProvider(newProvider)
    }
}
