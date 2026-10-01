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
                aiFeaturesSection
                sentenceProviderSection
                sentenceTraySection
                aboutSection
                #if DEBUG
                storageSection
                #endif
            }
            .navigationTitle("Device")
            // The AI disclosure and the turn-off confirmation live here, on the
            // List, not on `aiFeaturesSection`. A sheet hosted by a Section is
            // torn down when the Section redraws — and the toggle springs back
            // to off the moment it presents (it only turns on after Enable), so
            // the disclosure closed itself as soon as it opened.
            .sheet(isPresented: $isShowingAIDisclosure) {
                AIDisclosureSheet { accepted in
                    // Also reached from "What is sent to OpenAI" while already
                    // on; accepting again would only move the accepted date.
                    if accepted, !sentenceEngine.hasAIConsent {
                        sentenceEngine.grantAIConsent()
                        apiKey = OpenAIKeyVault.currentKey() ?? ""
                        // Respect the DEBUG provider picker; a no-op for the
                        // environment key, which `grantAIConsent` already adopted.
                        applyProvider()
                    } else if !accepted {
                        AIConsent.markPrompted()
                    }
                }
            }
            .confirmationDialog("Turn off AI features?",
                                isPresented: $isConfirmingAIRevoke,
                                titleVisibility: .visible) {
                Button("Turn Off", role: .destructive) { sentenceEngine.revokeAIConsent() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Nothing will be sent to OpenAI and the board will speak single words. Your key stays on this device, unused, until you turn AI features back on.")
            }
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

    /// Permission to use OpenAI, on or off. See `AIConsent`.
    ///
    /// Turning it on goes through the disclosure, and only an Enable there turns
    /// it on — the toggle never flips by itself. Turning it off leaves the key
    /// installed and unused, so turning it back on is one tap.
    @ViewBuilder
    var aiFeaturesSection: some View {
        Section {
            Toggle("AI Features", isOn: Binding(
                get: { sentenceEngine.hasAIConsent },
                set: { on in
                    if on { isShowingAIDisclosure = true } else { isConfirmingAIRevoke = true }
                }))
            Button("What is sent to OpenAI") { isShowingAIDisclosure = true }
                .font(.callout)
            #if DEBUG
            Button("Reset AI permission (DEBUG)", role: .destructive) {
                AIConsent.resetForTesting()
                sentenceEngine.revokeAIConsent()
            }
            .font(.callout)
            #endif
        } footer: {
            if sentenceEngine.hasAIConsent, let at = AIConsent.acceptedAt() {
                Text("On since \(at.formatted(date: .abbreviated, time: .omitted)). Selected words, word descriptions and scene descriptions are sent to OpenAI when you use those features — never your name or anything that identifies you.")
            } else {
                Text("Off. Nothing is sent to OpenAI, and each tile speaks its word.")
            }
        }
    }

    @ViewBuilder
    var sentenceProviderSection: some View {
        Section("Sentence Provider") {
            if !sentenceEngine.hasAIConsent && !envKeyOverride {
                // No key entry without permission to use one. A key already here
                // is dormant, and says so — and can still be removed without
                // first turning AI back on.
                if apiKey.isEmpty {
                    Text("Turn on AI Features to add an OpenAI key.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("API Key", value: "Installed, unused")
                    Button("Remove API Key", role: .destructive) {
                        isRemovingDormantKey = true
                    }
                    .confirmationDialog("Remove the key from this device?",
                                        isPresented: $isRemovingDormantKey,
                                        titleVisibility: .visible) {
                        Button("Remove Key", role: .destructive) { apiKey = "" }
                        Button("Cancel", role: .cancel) { }
                    }
                }
            } else if envKeyOverride {
                // DEBUG only, rows and all: the copy names the override, and a
                // shipping build has neither the override nor any word of it.
                #if DEBUG
                environmentOverrideRows
                #endif
            } else {
                // The picker is a development affordance and only appears in a
                // development build.
                //
                // Mock is the one way to reach sentence mode without a working
                // key: choosing it leaves `isMissingKey` false, so the child
                // hears invented sentences no model produced. Every other route
                // already falls back to single-word. `ProviderSelection.choose`
                // coerces a stored "mock" away in RELEASE, so a value set here
                // in DEBUG cannot follow a device into someone's home.
                #if DEBUG
                Picker("Provider", selection: $providerChoice) {
                    Text("OpenAI").tag("openai")
                    // Apple Intelligence hidden — on-device safety guardrails
                    // block innocuous AAC content (see PRD discussion log).
                    Text("Mock").tag("mock")
                }
                #endif
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
                            // Whose problem this is depends on whose key it is.
                            // Telling an evaluator to paste a new key sends them
                            // looking for one they were never given; telling
                            // them who to ask is the actionable half.
                            if let gift = giftedKey {
                                Text("The key \(gift.issuer.isEmpty ? "you were given" : "\(gift.issuer) gave you") "
                                     + "has been turned off. Nothing you did caused this, and nothing is being billed to you.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("OpenAI refused it — it may have been revoked or deleted. "
                                     + "Paste a new key below to start generating sentences again.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // The reassurance is the point: a caregiver reading
                            // this needs to know the child is not stuck.
                            Text("Until then this device speaks each word as it is tapped, exactly as it would with no key at all. Nothing else is affected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Out of credit is not a rejected key, and telling someone
                    // to paste a new one sends them looking for a problem that
                    // isn't there. The key is fine; the balance behind it is
                    // not, and it starts working again on its own.
                    //
                    // This reads the same whether the limit is a spend cap on a
                    // key someone was given or a family's own account running
                    // dry — OpenAI reports both as `insufficient_quota`, and for
                    // the person holding the iPad they are the same situation.
                    if sentenceEngine.isQuotaExhausted {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("This key is out of credit", systemImage: "creditcard.trianglebadge.exclamationmark")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            if let gift = giftedKey {
                                Text("The key \(gift.issuer.isEmpty ? "you were given" : "\(gift.issuer) gave you") "
                                     + "has reached its spending limit. The key is fine and this is not your bill — "
                                     + "it starts working again once the limit is raised.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("OpenAI stopped accepting requests because the spending limit on this key has been reached. "
                                     + "The key itself is fine.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Until then this device speaks each word as it is tapped, exactly as it would with no key at all. Nothing else is affected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // Says "close and reopen" because that is what is
                            // true, not because it is good.
                            //
                            // This flag is in memory and nothing on the device
                            // can observe a limit being raised at OpenAI, so
                            // sentences do not come back on their own — verified
                            // 2026-09-16. Everything a caregiver does in Admin
                            // (scenes, art, word review) recovers by itself,
                            // because no authoring path reads this flag; it is
                            // only the child's tile-tap → sentence path that
                            // latches. A "Check Again" button would fix it, and
                            // was deliberately not built: with a soft limit, or
                            // a hard one with alerts at 80% of $20, this state
                            // is nearly unreachable in real use. Promising
                            // automatic recovery in this sentence would have
                            // been the actual bug.
                            Text("Once the limit is raised, close and reopen Blaster to start generating sentences again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // A gifted key is not a key the caregiver typed, and a
                    // masked field is a poor way to say so. Showing who it is
                    // for turns an anonymous secret into a thing with a
                    // provenance — and the name matches what Mark sees against
                    // that key in the OpenAI dashboard, so a support
                    // conversation has a shared noun.
                    if let gift = giftedKey, !apiKey.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Gifted key — \(gift.label)", systemImage: "gift.fill")
                                .font(.headline)
                            Text(gift.issuer.isEmpty
                                 ? "sk-…\(gift.lastFour) · added \(gift.issuedDisplay)"
                                 : "From \(gift.issuer) · sk-…\(gift.lastFour) · added \(gift.issuedDisplay)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Whoever sent this key pays for the AI features on this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        OpenAIKeyEntrySection(apiKey: $apiKey, showCostEstimate: false)
                    }
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

            // Re-read both, because a key can arrive while Admin is closed — the
            // install happens in its own sheet, launched from a file tap, and
            // the `@State` seeded when this view was built knows nothing of it.
            apiKey = OpenAIKeyVault.currentKey() ?? ""
            giftedKey = GiftedKeyRecord.load()

            // Write the coercion through, do not just read around it.
            //
            // `ProviderSelection.choose` ignores a stored "mock" in RELEASE, but
            // the *stored value* stays "mock" — and several things in this
            // section still test it directly, including the `if providerChoice
            // == "openai"` that wraps the key field. A device carrying that
            // value into a shipping build would show no way to enter a key, and
            // no picker to change the setting back, which is a lockout rather
            // than a cosmetic mismatch.
            #if !DEBUG
            if providerChoice != "openai" { providerChoice = "openai" }
            #endif
        }
        .onChange(of: providerChoice) { applyProvider() }
        .onChange(of: apiKey) {
            OpenAIKeyVault.setKey(apiKey)
            // A record outliving its key would label somebody else's key with
            // the evaluator's name, which is worse than showing nothing. The
            // install path writes the record *after* the key, so it survives
            // this; every other route through here is a caregiver typing, and
            // that is exactly when the gift is over.
            if let gift = giftedKey,
               GiftedKeyObfuscation.lastFour(of: apiKey) != gift.lastFour {
                GiftedKeyRecord.clear()
                giftedKey = nil
            }
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
        //
        // Two buttons, and the gap between them is the entire point.
        //
        // This used to be one button that wrote the probe rows and deleted them
        // on the very next line, synchronously. CloudKit uploads
        // asynchronously, so the rows were gone from the local store before
        // anything reached the server and the record types never materialized —
        // while the button reported success, because all eight *local* writes
        // had succeeded. Confirmed 2026-09-17: the Development schema held
        // exactly the five types that bootstrap and ordinary use create on their
        // own, and none of the three only this probe writes.
        //
        // So Populate now leaves its rows in place, and Clean Up is a separate
        // deliberate act — after a human has looked at the console and seen the
        // types arrive. The rows are obviously labelled and harmless in the
        // meantime.
        Section {
            Button {
                let result = CloudKitSchemaExerciser.run(context: modelContext)
                schemaProbePopulated = true
                schemaProbeResult = result.isComplete
                    ? "Wrote all \(result.written.count) record types, and left them in place."
                    : "Wrote \(result.written.count). FAILED: \(result.failed.joined(separator: ", "))"
            } label: {
                Label(schemaProbePopulated ? "Populated" : "Populate CloudKit Schema",
                      systemImage: schemaProbePopulated ? "checkmark.circle.fill" : "square.stack.3d.up")
            }
            .disabled(!icloudEnabled || schemaProbePopulated)

            if let schemaProbeResult {
                Text(schemaProbeResult).font(.caption).foregroundStyle(.secondary)
            }

            if schemaProbePopulated {
                // Naming the types is the instruction. "Check the schema" sends
                // someone to a list of eight and tells them nothing about what
                // they are looking for; these are the ones whose presence
                // actually proves the probe reached the server, because nothing
                // else in ordinary use creates them.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Now check CloudKit → Development → Record Types.")
                        .font(.caption.weight(.semibold))
                    Text("Sync takes a minute or two. All \(CloudKitSchemaExerciser.exercised.count) "
                         + "must be present, and these three prove the probe worked — nothing "
                         + "else creates them:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(CloudKitSchemaExerciser.probeOnly, id: \.self) { name in
                        Text("CD_\(name)").font(.caption.monospaced())
                    }
                    Text("CD_MetricEvent and CD_DeviceProfile must NOT appear — they are "
                         + "device-local by design. Only clean up once you have seen them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Button(role: .destructive) {
                    CloudKitSchemaExerciser.cleanUp(context: modelContext)
                    schemaProbePopulated = false
                    schemaProbeResult = "Cleaned up. The schema survives — record types are "
                        + "permanent once materialized."
                } label: {
                    Label("Clean Up Probe Rows", systemImage: "trash")
                }
            }
        } header: {
            Text("CloudKit Schema")
        } footer: {
            Text("Writes and modifies one row of every synced model so CloudKit materializes "
                 + "all \(CloudKitSchemaExerciser.exercised.count) record types. **Populate, "
                 + "check the console, then clean up** — deleting the rows before they sync "
                 + "means the types never exist. Run on an iCloud-enabled device before "
                 + "promotion: a record type nothing has written does not exist in "
                 + "Development, and Production is read-only afterwards.")
        }
    }
    #endif

    #if DEBUG
    /// The Sentence Provider rows for a build launched with the developer key
    /// override. See `OpenAIKeyVault.environmentOverride`.
    @ViewBuilder
    var environmentOverrideRows: some View {
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
        // Mirrors `ProviderSelection.choose`: in a shipping build there is no
        // Mock, so an empty key means no AI whatever the stored choice says.
        #if DEBUG
        sentenceEngine.isMissingKey = (providerChoice == "openai" && apiKey.isEmpty)
        #else
        sentenceEngine.isMissingKey = apiKey.isEmpty
        #endif
        sentenceEngine.switchProvider(newProvider)
    }
}
