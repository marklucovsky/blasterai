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

    func profile(_ id: String) -> ChildProfile? { childProfiles.first { $0.id == id } }

    /// A profile's page: the name, who is talking, then one short row per
    /// thing a caregiver sets. Changes apply as they are made.
    func profilePage(_ p: ChildProfile, showsRoster: Bool) -> some View {
        let isTalking = p.id == currentProfile?.id
        return List {
            Section {
                ProfileNameField(profile: p)
                if isTalking {
                    Label("Talking now", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Switch to \(p.visibleName)") { profileResolver.setActive(id: p.id) }
                }
            }
            Section {
                NavigationLink(value: AdminPage.stage(p.id)) {
                    LabeledContent("Stage", value: p.brownsStage.label)
                }
                NavigationLink(value: AdminPage.profileAI(p.id)) {
                    LabeledContent("AI", value: ProfileAIPage.summary(of: p))
                }
                NavigationLink(value: AdminPage.voice(p.id)) {
                    LabeledContent("Voice", value: voiceDisplayName(for: p.voiceIdentifier))
                }
                NavigationLink(value: AdminPage.colors(p.id)) {
                    LabeledContent("Colors", value: TileColorMap.decode(p.colorMapData).isEmpty
                                   && p.linkColorMode == .standard ? "Standard" : "Custom")
                }
                NavigationLink("Me Page", value: AdminPage.meTopics(p.id))
            }
            if showsRoster {
                Section {
                    NavigationLink(value: AdminPage.profiles) {
                        LabeledContent("All Profiles", value: "\(childProfiles.count)")
                    }
                }
            }
            if !p.isSystem {
                Section {
                    Button("Delete Profile", role: .destructive) { profileToDelete = p }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
                // The current board first, as on Boards and Vocabulary.
                ForEach(switchableScenes.filter(\.isActive) + switchableScenes.filter { !$0.isActive }) { scene in
                    Button {
                        activateScene(scene)
                    } label: {
                        BoardRow(scene: scene, builtOn: templateNote(scene))
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
