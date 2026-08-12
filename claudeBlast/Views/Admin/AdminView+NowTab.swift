// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+NowTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation

extension AdminView {
    var nowTab: some View {
        NavigationStack {
            List {
                activeProfileSection
                activeSceneSection
                sessionNotesSection
            }
            .navigationTitle("Now")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Now", systemImage: "speaker.wave.2.fill") }
    }

    // MARK: - Section extractions

    @ViewBuilder
    var sessionNotesSection: some View {
        Section("Session Notes") {
            if sentenceEngine.sessionNotes.isEmpty {
                Text("Long-press any tile to add a note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(sentenceEngine.sessionNotes)
                    .font(.caption.monospaced())
                Button {
                    UIPasteboard.general.string = sentenceEngine.sessionNotes
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    sentenceEngine.sessionNotes = ""
                } label: {
                    Label("Clear Notes", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Active Profile section (parent-style quick tweaks)

    /// Top-of-Admin section that edits the *currently active* `ChildProfile`
    /// inline — voice, rate, volume, tile cap. These are the high-frequency
    /// parent-style tweaks; they live at the top of Admin so a parent
    /// landing here for "make her quieter" or "switch her voice" doesn't
    /// have to scroll past the therapist-style management UI.
    @ViewBuilder
    var activeProfileSection: some View {
        if let active = profileResolver.active {
            Section {
                if childProfiles.count > 1 {
                    Picker("Profile", selection: Binding(
                        get: { active.id },
                        set: { newID in profileResolver.setActive(id: newID) }
                    )) {
                        ForEach(childProfiles) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                } else {
                    LabeledContent("Profile", value: active.displayName)
                }
                LabeledContent("Age",
                               value: "\(active.age) (grade \(active.ageGrade))")

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Mode", selection: Binding(
                        get: { active.interactionMode },
                        set: { newMode in
                            active.interactionMode = newMode // bumps modifiedAt
                            // Start the new mode with a clean tray/strip.
                            sentenceEngine.clearSelection()
                            sentenceEngine.clearStrip()
                        }
                    )) {
                        ForEach(InteractionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text(active.interactionMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    activeProfileVoicePicker(for: active)
                        .navigationTitle("Voice")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Voice") {
                        Text(voiceDisplayName(for: active.voiceIdentifier))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Speech rate")
                        Spacer()
                        Text(String(format: "%.2f", active.ttsRate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { active.ttsRate },
                        set: { active.ttsRate = $0; active.modifiedAt = .now }
                    ), in: 0.3...0.7)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text(String(format: "%.2f", active.ttsVolume))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { active.ttsVolume },
                        set: { active.ttsVolume = $0; active.modifiedAt = .now }
                    ), in: 0.0...1.0)
                }

                Stepper(value: Binding(
                    get: { active.maxSelectedTiles },
                    set: { active.maxSelectedTiles = $0; active.modifiedAt = .now }
                ), in: 2...8) {
                    HStack {
                        Text("Tiles per group")
                        Spacer()
                        Text("\(active.maxSelectedTiles)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Active Profile — \(active.displayName)")
            } footer: {
                Text("Voice, speed, and volume apply to this profile only. Switching the active profile applies that profile's preferences.")
            }
        } else {
            Section("Active Profile") {
                Text("No active profile.")
                    .foregroundStyle(.secondary)
                Text("Add one from the Child Profiles section below, or tap an existing profile to make it active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func activeProfileVoicePicker(for profile: ChildProfile) -> some View {
        Form {
            VoicePickerSection(voiceIdentifier: Binding(
                get: { profile.voiceIdentifier },
                set: { profile.voiceIdentifier = $0; profile.modifiedAt = .now }
            ))
        }
    }

    func voiceDisplayName(for identifier: String) -> String {
        if identifier.isEmpty { return "System Default" }
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice.name
        }
        return "Custom"
    }

    // MARK: - Active Scene section (picker only — no editor)

    /// Lets the user switch among installed scenes without exposing the
    /// editor surface. Therapist-style scene management stays in the
    /// "Scenes" section below; this is the parent-style "today is bedtime
    /// → switch to the Bedtime scene" path.
    @ViewBuilder
    var activeSceneSection: some View {
        if !scenes.isEmpty {
            Section("Active Scene") {
                ForEach(scenes) { scene in
                    Button {
                        try? scene.activate(context: modelContext)
                    } label: {
                        HStack {
                            Text(scene.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if scene.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
