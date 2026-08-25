// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileFormSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Voice Picker

/// Lists installed English voices grouped by quality tier.
///
/// iOS ships three tiers:
///   Default   — built-in, always available, sounds robotic
///   Enhanced  — ~50–150 MB download per voice, noticeably better
///   Premium   — ~200 MB download, on-device neural model (iOS 17+),
///               sounds natural and is indistinguishable from cloud TTS
///
/// Downloads live in Settings → Accessibility → Spoken Content → Voices.
/// Audio never leaves the device regardless of tier.
// VoicePickerSection and AVSpeechSynthesisVoiceQuality.sortOrder live in
// VoicePickerSection.swift now — shared by Admin, the profile form, and
// onboarding so the picker stays consistent.

// MARK: - Voice section header with help popover

private struct VoiceSectionHeader: View {
    @State private var showHelp = false

    var body: some View {
        HStack {
            Text("Voice")
            Spacer()
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                VoiceHelpPopover()
            }
        }
    }
}

private struct VoiceHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice Quality Tiers")
                .font(.headline)
            Text("**Default** — Built-in voices, always available.")
            Text("**Enhanced** — Noticeably better quality. ~50–150 MB download per voice.")
            Text("**Premium** — On-device neural voice, sounds natural. ~200 MB download.")
            Divider()
            Text("To download Enhanced or Premium voices, go to:")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("Settings → Accessibility → Spoken Content → Voices")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(minWidth: 300, maxWidth: 400)
    }
}

// MARK: - Child profile form sheet

/// Compact create/edit form for a `ChildProfile`. Used by the Admin
/// Profiles section. Captures the child's Brown's Stage, which decides both
/// the interaction mode and the tile cap — see `BrownsStage`. There is no age
/// or birthday field: the app does not store a child's date of birth.
struct ChildProfileFormSheet: View {
    enum Mode {
        case create
        case edit(ChildProfile)
    }

    let mode: Mode
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var name: String = ""
    @State private var stage: BrownsStage = .one
    @State private var voiceID: String = ""
    @State private var maxTiles: Int = 4
    @State private var ttsRate: Float = 0.5
    @State private var ttsVolume: Float = 1.0
    @State private var makeActive: Bool = false

    private var titleText: String {
        switch mode {
        case .create: return "New Child Profile"
        case .edit:   return "Edit Child Profile"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Personalize the voice preview when the child's name is filled in:
    /// "Hi Aubrey, I'll be your voice." Otherwise a generic line so the
    /// preview still works while the form is being filled out.
    private var previewPhrase: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? "Hi, I'll be your voice."
            : "Hi \(trimmed), I'll be your voice."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Voice") {
                    VoicePickerSection(
                        voiceIdentifier: $voiceID,
                        previewPhrase: previewPhrase
                    )
                }

                Section("Stage") {
                    Picker("Stage", selection: $stage) {
                        ForEach(BrownsStage.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(stage.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Stage decides how tiles become speech: Stage I speaks one word per tap, later stages build sentences.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .onChange(of: stage) { _, newStage in
                    maxTiles = min(newStage.tileCapRange.upperBound,
                                   max(newStage.tileCapRange.lowerBound, maxTiles))
                }

                Section("Tiles + Audio") {
                    // Only Stage IV+ leaves a number to choose — earlier stages
                    // pin the count, because the count is part of the stage.
                    if stage.allowsTileCapChoice {
                        Stepper(value: $maxTiles, in: stage.tileCapRange) {
                            HStack {
                                Text("Tiles per sentence")
                                Spacer()
                                Text("\(maxTiles)").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        LabeledContent("Tiles per sentence",
                                       value: "\(stage.tileCapRange.lowerBound) (set by \(stage.label))")
                    }
                    VStack(alignment: .leading) {
                        Text("Speech rate \(String(format: "%.2f", ttsRate))")
                            .font(.caption)
                        Slider(value: $ttsRate, in: 0.3...0.7)
                    }
                    VStack(alignment: .leading) {
                        Text("Volume \(String(format: "%.2f", ttsVolume))")
                            .font(.caption)
                        Slider(value: $ttsVolume, in: 0.0...1.0)
                    }
                }

                if case .create = mode {
                    Section {
                        Toggle("Make this profile active", isOn: $makeActive)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if case let .edit(profile) = mode {
            name = profile.displayName
            stage = profile.brownsStage
            voiceID = profile.voiceIdentifier
            maxTiles = profile.effectiveTileCap
            ttsRate = profile.ttsRate
            ttsVolume = profile.ttsVolume
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .create:
            let profile = ChildProfile(
                displayName: trimmed,
                brownsStage: stage,
                voiceIdentifier: voiceID,
                maxSelectedTiles: maxTiles,
                isActive: false
            )
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            modelContext.insert(profile)
            if makeActive {
                profileResolver.setActive(id: profile.id)
            }
        case .edit(let profile):
            profile.displayName = trimmed
            profile.brownsStage = stage
            profile.voiceIdentifier = voiceID
            profile.setTileCap(maxTiles)
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            profile.modifiedAt = .now
            profileResolver.refresh()
        }
        onDismiss()
    }
}
