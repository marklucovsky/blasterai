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
                        set: { isOn in
                            device.requireFaceIDForAdmin = isOn
                            // Choose the credential now, not at the next gate.
                            //
                            // Switching the lock on used to store a flag and
                            // nothing else, leaving the *next* Admin entry to
                            // demand a PIN be invented on the spot — the worst
                            // possible moment, and on a Mac with no biometry the
                            // only credential the device will ever have.
                            if isOn && device.adminPINHash == nil {
                                isEnrollingPIN = true
                            }
                        }
                       ))
                .disabled(device.role == .patient) // patient always on
                .sheet(isPresented: $isEnrollingPIN) {
                    PINSetupSheet(device: device) { stored in
                        // A lock with no credential behind it is worse than no
                        // lock, so backing out of the PIN backs out of the lock.
                        //
                        // Conditioned on the device ending up with no PIN, not on
                        // the sheet being cancelled: the same sheet is used to
                        // *change* an existing PIN, and cancelling that must
                        // leave both the old PIN and the lock exactly as they
                        // were rather than switching Admin's lock off.
                        if !stored && device.adminPINHash == nil {
                            device.requireFaceIDForAdmin = false
                        }
                    }
                }
                if device.adminPINHash != nil {
                    // Changing a PIN you still have is an ordinary errand, and it
                    // belongs here rather than at the gate.
                    //
                    // The gate's "Forgot your PIN?" is a *lockout* path: it only
                    // appears once biometry has failed or is absent. On a phone
                    // with Face ID that is almost never — entry succeeds before
                    // the PIN screen is ever drawn — so a caregiver who simply
                    // wants a different PIN had no way in but Remove, then Set,
                    // which leaves the lock briefly enabled with nothing behind
                    // it.
                    Button("Change PIN") { isEnrollingPIN = true }
                    // On a device with no biometry the PIN is the ONLY credential,
                    // so removing it while Admin is locked has no fallback to fall
                    // back to — it locks the caregiver out of their own device.
                    // A Mac running this as Designed-for-iPad is exactly that case.
                    Button("Remove PIN", role: .destructive) {
                        device.adminPINHash = nil
                        device.adminPINSalt = nil
                        // The throttle belonged to the credential that just went
                        // away. Left behind, it would greet the next PIN with a
                        // lockout earned by a PIN that no longer exists.
                        device.adminPINFailedAttempts = 0
                        device.adminPINLockedUntil = nil
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
                    // Reachable on a device whose lock was switched on before
                    // enrolment moved here. An actionable button rather than a
                    // note that says it will happen to you later.
                    Button("Set a PIN") { isEnrollingPIN = true }
                    Text(biometry.hasHardware
                         ? "No PIN set. Without one, \(biometry.displayName) is the only way into Admin."
                         : "No PIN set. This device has no biometric unlock, so Admin cannot be opened until you set one.")
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
                // The env path stores a key as well as using one.
                //
                // `ProviderSelection` writes `OPENAI_API_KEY` into the Keychain
                // on launch so a relaunch from the Home screen — outside the
                // scheme — keeps working. That is deliberate, and it means this
                // device holds a key that outlives the variable. With Remove
                // only in the branch below, there was no way to clear it without
                // first editing the scheme.
                //
                // Its own dialog rather than the one below: only one branch of
                // this `if` is ever built, so there is no second presenter to
                // race, and the copy has to say something different — this one
                // cannot promise the AI will stop.
                if !apiKey.isEmpty {
                    Button("Remove Stored Key", role: .destructive) {
                        isRemovingAPIKey = true
                    }
                    .confirmationDialog("Remove the key saved on this device?",
                                        isPresented: $isRemovingAPIKey,
                                        titleVisibility: .visible) {
                        Button("Remove Key", role: .destructive) { apiKey = "" }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        // Only an Xcode launch injects the variable. Tapping the
                        // app icon does not, because iOS launches it — so the key
                        // stays removed until you run from a scheme again. The
                        // first version of this said the next launch would
                        // restore it, which is wrong everywhere except Xcode.
                        Text("The key is deleted from this device. If you relaunch from Xcode with an API Key environment variable set, that launch restores it.")
                    }
                }
            } else {
                Picker("Provider", selection: $providerChoice) {
                    Text("OpenAI").tag("openai")
                    // Apple Intelligence hidden — on-device safety guardrails
                    // block innocuous AAC content (see PRD discussion log).
                    Text("Mock").tag("mock")
                }
                if providerChoice == "openai" {
                    // A rejected key is not a failed request, and must not read
                    // like one. Until this existed, a revoked key produced
                    // silence on every tap with nothing anywhere to explain it —
                    // the tester's report is "it stopped working".
                    if sentenceEngine.isKeyRejected {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("This key was rejected", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text("OpenAI refused it — it may have been revoked, expired, or the account may be out of credit. "
                                 + "Paste a new key below to start generating sentences again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // The reassurance is the point: a caregiver reading
                            // this needs to know the child is not stuck.
                            Text("Until then this device speaks each word as it is tapped, exactly as it would with no key at all. Nothing else is affected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    OpenAIKeyEntrySection(apiKey: $apiKey, showCostEstimate: false)
                    if apiKey.isEmpty {
                        Text("Enter your OpenAI API key to enable AI sentence generation.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        // There was no way to take a key back out.
                        //
                        // Clearing the masked field technically worked — the
                        // vault deletes on an empty write — but nothing said so,
                        // and a `SecureField` showing a stored secret is not an
                        // affordance anyone reads as "delete". The only reliable
                        // route was a factory reset.
                        //
                        // It matters for three ordinary situations, none of them
                        // edge cases: a family deciding they are not ready for
                        // AI after all; an iPad going back to the therapist who
                        // lent it, or on to another child; and an evaluator
                        // finishing with a key that was given to them.
                        //
                        // Switching Provider to Mock is not the same thing. That
                        // stops the calls and leaves the key in the Keychain.
                        Button("Remove API Key", role: .destructive) {
                            isRemovingAPIKey = true
                        }
                        .confirmationDialog("Remove the API key from this device?",
                                            isPresented: $isRemovingAPIKey,
                                            titleVisibility: .visible) {
                            Button("Remove Key", role: .destructive) {
                                // Through the same binding the field writes, so
                                // the vault delete and the provider swap both
                                // happen on the existing onChange.
                                apiKey = ""
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            // Says what keeps working, not just what stops. The
                            // keyless configuration is a supported way to run
                            // this app, not a broken one, and a caregiver
                            // deciding about AI deserves to hear that before
                            // they decide rather than after.
                            // Leads with what remains, because what remains is
                            // almost all of it. The AI features enhance a
                            // working AAC app; they are not the app. Copy that
                            // opens with a list of losses reads as a warning
                            // about breaking the device, and a caregiver
                            // weighing whether they are ready for AI deserves
                            // better than being frightened out of the decision.
                            Text("Blaster keeps working as it does now — boards, speech, packs, the editor, print and export are unchanged. "
                                 + "The AI assist features need a key: sentence generation, scene and page generation, "
                                 + "word moderation, and art for new words. You can add a key back any time.")
                        }
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
            // A different key has not been rejected — it has not been tried. The
            // flag is about one credential, so it must not outlive it, or a
            // caregiver who fixes the problem stays in single-word mode with no
            // way to tell why.
            sentenceEngine.clearKeyRejection()
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
            // Confirmed in BOTH directions, and deliberately not a plain Toggle.
            //
            // §10: a Mac install came back with `icloud_enabled = true` that
            // nobody meant to set. DEBUG registers it false and onboarding seeds
            // from that, so a stored true is an explicit write — and the likeliest
            // author is a tap that queued during one of the long unresponsive
            // stretches after a load run and landed on whatever was under the
            // finger when the run loop caught up.
            //
            // **The mechanism is the point, not the mishap.** A UI that stops
            // answering does not stop accepting: touches queue, and they are
            // delivered against the layout that exists when processing resumes.
            // Every control in reach becomes one that can fire on its own.
            //
            // This one matters because it is not a preference — it is a storage
            // decision. The ModelContainer is rebuilt at next launch against a
            // different configuration, which store is authoritative changes, and
            // turning it ON can pull a large sync onto a device that was
            // deliberately local. A confirmation defeats the queued-tap case
            // outright, because a stray tap cannot also confirm.
            Toggle("iCloud Sync", isOn: Binding(
                get: { icloudEnabled },
                set: { pendingICloud = $0 }))
            if icloudEnabled {
                Text("iCloud sync takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            pendingICloud == true ? "Turn on iCloud Sync?" : "Turn off iCloud Sync?",
            isPresented: Binding(get: { pendingICloud != nil },
                                 set: { if !$0 { pendingICloud = nil } }),
            titleVisibility: .visible
        ) {
            Button(pendingICloud == true ? "Turn On" : "Turn Off") {
                if let pending = pendingICloud { icloudEnabled = pending }
                pendingICloud = nil
            }
            Button("Cancel", role: .cancel) { pendingICloud = nil }
        } message: {
            // Says what actually happens, not "are you sure" — the caregiver
            // cannot weigh a decision they have not been told the shape of.
            Text(pendingICloud == true
                 ? "Syncing starts at next launch. Anything already in your iCloud "
                   + "will download to this device, which can take a while on a large board."
                 : "This device stops syncing at next launch. Everything already in "
                   + "iCloud is kept, and this device keeps its own copy.")
        }

        // The pre-promotion gate. See docs/cloudkit-schema-checklist.md.
        Section {
            Button {
                let result = CloudKitSchemaExerciser.run(context: modelContext)
                CloudKitSchemaExerciser.cleanUp(context: modelContext)
                schemaProbeResult = result.isComplete
                    ? "Wrote all \(result.written.count) record types. Give sync a minute, "
                      + "then check CloudKit Development."
                    : "Wrote \(result.written.count). FAILED: \(result.failed.joined(separator: ", "))"
            } label: {
                Label("Populate CloudKit Schema", systemImage: "square.stack.3d.up")
            }
            .disabled(!icloudEnabled)

            if let schemaProbeResult {
                Text(schemaProbeResult).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("CloudKit Schema")
        } footer: {
            Text("Writes and then modifies one row of every synced model, so CloudKit "
                 + "materializes all eight record types, then deletes the rows. The schema "
                 + "survives the cleanup. Run this on an iCloud-enabled device before "
                 + "promotion — a record type nothing has written does not exist in "
                 + "Development, and Production is read-only afterwards.")
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
        // Removing a key must not hand the child the mock.
        //
        // Both branches above build a provider, because the engine needs one —
        // but only an *explicit* Mock choice means "generate fake sentences".
        // Choosing OpenAI with no key means this device has no AI, and a device
        // with no AI speaks each word as it is tapped.
        sentenceEngine.isMissingKey = (providerChoice == "openai" && apiKey.isEmpty)
        sentenceEngine.switchProvider(newProvider)
    }
}
