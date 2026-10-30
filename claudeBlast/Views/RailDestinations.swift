// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  RailDestinations.swift
//  claudeBlast
//
//  What the caregiver rail opens behind the Admin gate.
//

import SwiftUI
import SwiftData

/// The caregiver rail's Edit: the page the board is showing, in the page
/// editor, without going through Admin › Scenes to find it.
struct RailPageEditor: View {
    let pageKey: String
    @Query(filter: #Predicate<BlasterScene> { $0.isActive }) private var activeScenes: [BlasterScene]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let scene = activeScenes.first, scene.page(withKey: pageKey) != nil {
                    PageEditorView(scene: scene, pageKey: pageKey)
                } else {
                    ContentUnavailableView("This Page Can't Be Edited",
                                           systemImage: "pencil.slash",
                                           description: Text("It is not a page of the active scene."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The Edit menu's Edit Scene: the active scene in the scene editor. BlasterAI
/// 60 is the system's and never reaches here; the menu disables the row.
struct RailSceneEditor: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive }) private var activeScenes: [BlasterScene]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let scene = activeScenes.first, !scene.isDefault {
                    SceneEditorView(scene: scene)
                } else {
                    ContentUnavailableView("This Scene Can't Be Edited",
                                           systemImage: "pencil.slash",
                                           description: Text("BlasterAI 60 is the system's board. Duplicate it in Settings › Scenes to change it."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Child mode off: once the gate has let a caregiver through, the caregiver
/// rail is back and there is nothing to show.
struct CaregiverRailUnlock: View {
    @AppStorage(AppSettingsKey.railChildLock) private var childLock = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .task {
                childLock = false
                dismiss()
            }
    }
}
