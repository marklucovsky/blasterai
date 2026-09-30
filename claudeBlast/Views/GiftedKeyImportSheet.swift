// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GiftedKeyImportSheet.swift
//  claudeBlast
//
//  A key someone sent you, arriving.
//

import SwiftUI

/// Confirm-before-install for a `.blasterkey` file.
///
/// Modelled on `PackImportSheet` rather than `ColorwayImportSheet`. A colorway
/// applies on receipt with no prompt, because its recipient is often a parent
/// who cannot work the color editor and a confirmation step is a way for the fix
/// not to arrive. A key is the opposite: it is someone's credential, it costs
/// money to use, and the person tapping it should see whose it is and agree.
struct GiftedKeyImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    /// Optional on purpose.
    ///
    /// This sheet is reached two ways. From a file tap it arrives through
    /// `ImportRouteSheet`, which `ContentView` wraps in `PresentedEnvironment` —
    /// the engine is there. From the onboarding key step it is presented before
    /// the main board exists, and this app does not rely on sheets inheriting
    /// the environment (hence `PresentedEnvironment` existing at all). A
    /// non-optional `@Environment` would trap in that second case, on the one
    /// screen an evaluator is most likely to be standing on.
    @Environment(SentenceEngine.self) private var sentenceEngine: SentenceEngine?

    private enum Phase: Equatable {
        case loading
        case ready(GiftedKeyPayload)
        /// A key is already on this device. Not an error — a refusal, with the
        /// way out named.
        case occupied(GiftedKeyPayload, existing: Existing)
        case verifying(GiftedKeyPayload)
        /// Installed, with whatever OpenAI said about the key. A nil outcome
        /// means it was not checked.
        case installed(GiftedKeyRecord, OpenAIKeyValidator.Outcome?)
        /// OpenAI refused the key outright, so nothing was installed.
        case refused(GiftedKeyPayload)
        case failed(String)
    }

    private enum Existing: Equatable {
        case stored
        case environment
    }

    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Opening…")
                case .ready(let payload):
                    ready(payload)
                case .occupied(let payload, let existing):
                    occupied(payload, existing)
                case .verifying:
                    ProgressView("Checking this key…")
                case .installed(let record, let outcome):
                    installed(record, outcome)
                case .refused(let payload):
                    refused(payload)
                case .failed(let message):
                    ContentUnavailableView("Couldn't Use This Key",
                                           systemImage: "key.slash",
                                           description: Text(message))
                }
            }
            .navigationTitle("Add AI Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") { onDismiss() }
                }
                if case .ready(let payload) = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Install") { Task { await verifyThenInstall(payload) } }
                    }
                }
            }
        }
        .task { load() }
    }

    private var isFinished: Bool {
        switch phase {
        case .installed, .failed, .refused: return true
        default: return false
        }
    }

    // MARK: - States

    private func ready(_ payload: GiftedKeyPayload) -> some View {
        List {
            Section {
                LabeledContent("For", value: payload.label)
                if !payload.issuer.isEmpty {
                    LabeledContent("From", value: payload.issuer)
                }
                LabeledContent("Key") {
                    Text("sk-…\(GiftedKeyObfuscation.lastFour(of: payload.key))").monospaced()
                }
                if let expires = payload.expiresAt,
                   let date = GiftedKeyRecord.parseDate(expires) {
                    LabeledContent("Expires", value: date.formatted(date: .abbreviated, time: .omitted))
                }
            } footer: {
                Text("This key pays for AI features on this device: sentence generation, "
                     + "word review, and pictures for new words. The bill goes to whoever sent it, not to you.")
            }

            Section {
                Text("Nothing else about this device changes. You can remove the key at any "
                     + "time from **Admin → Device**.")
                .font(.callout)
            }
        }
    }

    /// Refusing, before anything is installed.
    ///
    /// Checked at load rather than at Install, so nobody agrees to something that
    /// was never going to happen. A gifted key replacing a caregiver's own would
    /// silently redirect their spending to someone else's account, and the
    /// Keychain holds exactly one key, so the old one is not recoverable
    /// afterwards — this is not a prompt worth offering.
    private func occupied(_ payload: GiftedKeyPayload, _ existing: Existing) -> some View {
        List {
            Section {
                Label("This device already has a key", systemImage: "key.fill")
                    .font(.headline)
            } footer: {
                switch existing {
                case .stored:
                    Text("The key for **\(payload.label)** was not installed, so the key already "
                         + "on this device is untouched. To use the new one instead, remove the "
                         + "current key first: **Admin → Device → Remove API Key**.")
                case .environment:
                    // Unreachable in a shipping build, which has no override —
                    // and the copy names the variable, so it is compiled out.
                    #if DEBUG
                    Text("This build is using a key from the `OPENAI_API_KEY` environment "
                         + "variable, which always wins over a stored one. The key for "
                         + "**\(payload.label)** was not installed. Clear the scheme's "
                         + "environment variable to use it.")
                    #else
                    EmptyView()
                    #endif
                }
            }
        }
    }

    private func installed(_ record: GiftedKeyRecord,
                           _ outcome: OpenAIKeyValidator.Outcome?) -> some View {
        // `.valid` is the ordinary case and says so. Anything else here means
        // the check could not reach a verdict — rate limiting, no network — and
        // the key was installed anyway, because refusing over an unreachable
        // network would strand an evaluator on a plane with a perfectly good key.
        let unverified = outcome != nil && outcome != .valid
        return List {
            Section {
                Label(unverified ? "Key installed, not verified" : "Key installed",
                      systemImage: unverified ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(unverified ? .orange : .green)
                LabeledContent("For", value: record.label)
                if !record.issuer.isEmpty {
                    LabeledContent("From", value: record.issuer)
                }
                LabeledContent("Key") {
                    Text("sk-…\(record.lastFour)").monospaced()
                }
            } footer: {
                if let outcome, unverified {
                    Text("\(outcome.friendlyMessage) The key is saved — it will be tried again "
                         + "the next time the app needs it.")
                } else {
                    Text("AI features are on. If sentences ever stop working, **Admin → Device** "
                         + "says why.")
                }
            }
        }
    }

    /// OpenAI said no, so nothing was stored.
    ///
    /// The whole reason to check at install rather than let the first tile tap
    /// discover it. A dead key that installs silently becomes a device that
    /// mysteriously stops making sentences an hour later, and the evaluator has
    /// no way to connect that to the file they tapped. Here the file, the sender
    /// and the failure are all on screen together, and the fix — ask for another
    /// one — is obvious.
    private func refused(_ payload: GiftedKeyPayload) -> some View {
        List {
            Section {
                Label("OpenAI rejected this key", systemImage: "key.slash")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } footer: {
                Text("Nothing was saved to this device. The key in this file has been revoked, "
                     + "or it never worked. Ask \(payload.issuer.isEmpty ? "whoever sent it" : payload.issuer) "
                     + "for a new file.")
            }
        }
    }

    // MARK: - Work

    private func load() {
        // Security-scoped access, as every other importer does: a file handed
        // over by Messages or Files is not ours to read without asking.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let payload = try GiftedKeyObfuscation.open(try Data(contentsOf: url))
            if OpenAIKeyVault.environmentOverride() != nil {
                phase = .occupied(payload, existing: .environment)
            } else if let existing = OpenAIKeyVault.currentKey(), !existing.isEmpty {
                phase = .occupied(payload, existing: .stored)
            } else {
                phase = .ready(payload)
            }
        } catch let error as GiftedKeyError {
            phase = .failed(error.errorDescription ?? "This key file could not be read.")
        } catch {
            phase = .failed("This key file could not be read.")
        }
    }

    /// Check the key with OpenAI before storing it.
    ///
    /// Matches what typing a key already does — `OpenAIKeyEntrySection`
    /// validates as you paste — so the two routes to a key on this device agree
    /// about when you find out it is bad.
    ///
    /// Only a definitive refusal blocks the install. A rate limit or an
    /// unreachable network says nothing about the key, and refusing on those
    /// would leave an evaluator holding a good key they cannot use because their
    /// hotel wifi is bad. Same rule as `OpenAIFailure`: condemn on a real no,
    /// never on silence.
    private func verifyThenInstall(_ payload: GiftedKeyPayload) async {
        phase = .verifying(payload)
        let outcome = await OpenAIKeyValidator.validate(payload.key)
        guard outcome != .invalidKey else {
            phase = .refused(payload)
            return
        }
        install(payload, outcome: outcome)
    }

    private func install(_ payload: GiftedKeyPayload,
                         outcome: OpenAIKeyValidator.Outcome? = nil) {
        guard OpenAIKeyVault.setKey(payload.key) else {
            phase = .failed("The key could not be saved to this device's Keychain.")
            return
        }
        let record = GiftedKeyRecord.from(payload)
        GiftedKeyRecord.save(record)

        // Tapping a key file is a choice of provider. A device that reached here
        // was almost certainly on Mock because it had no key, and leaving that
        // setting behind would mean the key installs and changes nothing.
        //
        // Written before `adoptKey` so the two agree if anything re-reads the
        // setting in response.
        UserDefaults.standard.set("openai", forKey: AppSettingsKey.providerChoice)

        // Storing a key is not the same as using one — see `adoptKey`, which
        // names the three steps that have to happen together.
        sentenceEngine?.adoptKey(payload.key)

        phase = .installed(record, outcome)
    }
}
