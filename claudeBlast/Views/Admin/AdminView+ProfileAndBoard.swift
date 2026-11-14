// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ProfileAndBoard.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation

extension AdminView {
    // MARK: - The current profile

    /// The profile the board is speaking for. Never nil in practice: the
    /// resolver falls back to the caregiver's own profile, which is created at
    /// bootstrap and cannot be deleted, so Settings has no empty state for it.
    var currentProfile: ChildProfile? { profileResolver.active ?? caregiverProfile }

    /// Settings › Profile: whose settings these are, in short rows. The
    /// longer form (name, colours, Me page) is one row down.
    @ViewBuilder
    var profilePage: some View {
        if let active = currentProfile {
            List {
                Section {
                    Picker("Stage", selection: Binding(
                        get: { active.brownsStage },
                        set: { newStage in
                            active.brownsStage = newStage // reconciles cap, bumps modifiedAt
                            // Start the new stage with a clean tray/strip.
                            sentenceEngine.clearSelection()
                            sentenceEngine.clearStrip()
                            profileResolver.refresh()
                        }
                    )) {
                        ForEach(BrownsStage.allCases) { stage in
                            Text(stage.label).tag(stage)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    modeOverrideNotice

                    // Only Stage IV+ leaves a number to choose. Stages I and
                    // II-III pin the count because the count is part of what
                    // the stage means — and at Stage I there is no message to
                    // count, since each tile speaks the moment it is tapped.
                    if active.brownsStage.allowsTileCapChoice {
                        Stepper(value: Binding(
                            get: { active.effectiveTileCap },
                            set: { active.setTileCap($0); profileResolver.refresh() }
                        ), in: active.brownsStage.tileCapRange) {
                            LabeledContent("Words per Message", value: "\(active.effectiveTileCap)")
                        }
                    } else if active.brownsStage != .one {
                        LabeledContent("Words per Message", value: "\(active.effectiveTileCap)")
                    }
                    NavigationLink(value: AdminPage.voice) {
                        LabeledContent("Voice", value: voiceDisplayName(for: active.voiceIdentifier))
                    }
                    Button("Name, Colours and Me Page") { profileSheet = .edit(active) }
                        .foregroundStyle(.primary)
                }
                Section {
                    NavigationLink(value: AdminPage.profiles) {
                        LabeledContent("All Profiles", value: "\(childProfiles.count)")
                    }
                }
            }
            .navigationTitle(active.displayName)
        }
    }

    /// The device-wide tray override, said where the stage is set, since it
    /// is the one thing that can make the stage not apply.
    @ViewBuilder
    var modeOverrideNotice: some View {
        if let override = profileResolver.modeOverride {
            Label("This device is temporarily set to \(override.label), overriding the stage.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Follow the stage again") {
                profileResolver.setModeOverride(nil)
                sentenceEngine.clearSelection()
                sentenceEngine.clearStrip()
            }
            .font(.caption)
        }
    }

    /// Settings › Profile › Voice, for the current profile.
    @ViewBuilder
    var voicePage: some View {
        if let active = currentProfile {
            List {
                Section {
                    NavigationLink {
                        activeProfileVoicePicker(for: active)
                            .navigationTitle("Voice")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Voice", value: voiceDisplayName(for: active.voiceIdentifier))
                    }
                    LabeledContent("Rate") {
                        Slider(value: Binding(
                            get: { active.ttsRate },
                            set: { active.ttsRate = $0; active.modifiedAt = .now }
                        ), in: 0.3...0.7)
                        .frame(maxWidth: 220)
                    }
                    LabeledContent("Volume") {
                        Slider(value: Binding(
                            get: { active.ttsVolume },
                            set: { active.ttsVolume = $0; active.modifiedAt = .now }
                        ), in: 0.0...1.0)
                        .frame(maxWidth: 220)
                    }
                }
            }
            .navigationTitle("Voice")
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

    // MARK: - Current Board

    /// The scenes a caregiver can switch the board to.
    var switchableScenes: [BlasterScene] {
        scenes.filter { !MeScene.isMeScene($0) && !$0.isCarriedTemplate }
    }

    var activeScene: BlasterScene? { scenes.first(where: \.isActive) }

    /// Whether the active board has levels, so the Level row means something.
    var activeSceneHasLevels: Bool {
        guard let active = activeScene else { return false }
        return BoardLevels(scene: active, system: scenes.first(where: \.isDefault)).count > 0
    }

    /// Settings › Current Board: which board, its level, and the editor.
    /// Making, importing and sharing boards is Boards and Vocabulary.
    var currentBoardPage: some View {
        List {
            Section {
                ForEach(switchableScenes) { scene in
                    Button {
                        activateScene(scene)
                    } label: {
                        HStack {
                            Text(scene.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if scene.isActive {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                if activeSceneHasLevels, let active = activeScene {
                    RevealLevelControl(scene: active)
                        .frame(maxWidth: .infinity)
                }
                Button("Edit This Board") { editActiveBoard() }
                    .disabled(activeScene == nil)
            }
        }
        .navigationTitle("Current Board")
    }

    /// Open the editor on the active board, by the same door as Boards and Vocabulary:
    /// a board we ship, or someone else's template, offers a copy first.
    func editActiveBoard() {
        guard let scene = activeScene else { return }
        if scene.isSystemOwned || scene.isLockedTemplate {
            sceneToClone = scene
        } else {
            navigateToNewScene = scene
        }
    }
}
