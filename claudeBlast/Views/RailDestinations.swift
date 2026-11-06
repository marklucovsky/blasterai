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
///
/// On BlasterAI 60, or any scene the system owns, there is nothing to edit in
/// place: it offers a copy first (`SystemSceneCopyOffer`), and once the copy
/// is the active scene the same page opens in it.
struct RailPageEditor: View {
    let pageKey: String
    @Query(filter: #Predicate<BlasterScene> { $0.isActive }) private var activeScenes: [BlasterScene]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let scene = activeScenes.first, scene.isDefault || scene.isSystemOwned {
                    SystemSceneCopyOffer(scene: scene)
                } else if let scene = activeScenes.first, scene.page(withKey: pageKey) != nil {
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
/// 60 is the system's: it offers a copy first, as Edit This Page does.
struct RailSceneEditor: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive }) private var activeScenes: [BlasterScene]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let scene = activeScenes.first {
                    if scene.isDefault || scene.isSystemOwned {
                        SystemSceneCopyOffer(scene: scene)
                    } else {
                        SceneEditorView(scene: scene)
                    }
                } else {
                    ContentUnavailableView("No Active Scene", systemImage: "pencil.slash")
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

/// A system scene is never edited in place (`BlasterScene.isSystemOwned`):
/// the caregiver who asked to edit it is offered their own copy, made with the
/// usual copy name ("BlasterAI 60 (1)") and switched to, so the editor that
/// asked for it opens on the copy. The copy is the board from then on; the
/// system's own stays in Settings › Scenes.
struct SystemSceneCopyOffer: View {
    let scene: BlasterScene
    @Environment(\.modelContext) private var modelContext
    @State private var failure: String?

    var body: some View {
        ContentUnavailableView {
            Label("Make Your Own Copy", systemImage: "square.on.square")
        } description: {
            Text("\(BlasterScene.copyRoot(of: scene.name)) is the system's board, so it can't be changed. "
                 + "Make a copy to edit; the copy becomes the board the child uses.")
        } actions: {
            Button("Make a Copy and Edit") { makeCopy() }
                .buttonStyle(.borderedProminent)
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func makeCopy() {
        let copy = BlasterScene.cloneForEditing(
            scene, in: modelContext,
            authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
            authorName: DeviceProfileStore.authorName(context: modelContext))
        do {
            _ = try copy.activate(context: modelContext)
            try? modelContext.save()
        } catch {
            modelContext.delete(copy)
            failure = error.localizedDescription
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
